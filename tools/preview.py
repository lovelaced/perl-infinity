#!/usr/bin/env python3
"""Render a harness layout dump (tools/layout.lua output) to a PNG for visual review.

usage: python3 tools/preview.py dump.txt [-o out.png] [--media PerlInfinity/Media] [--scale 2]

Frames are drawn as outlines, status bars as fills, textures from the addon's own
BLP/TGA files when the path resolves (Pillow reads BLP), color textures as fills and
font strings with a system font standing in for the client's fonts. WoW coordinates
start bottom-left; the image is cropped to the dumped frames plus a margin.
"""
import argparse
import os
import re
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

LINE = re.compile(r'^(\s*)(\S+) (\S+) (unanchored|[-\d.]+,[-\d.]+,[-\d.]+,[-\d.]+)(.*)$')
FIELD = re.compile(r'(\w+)=("(?:[^"\\]|\\.)*"(?:\(secret\))?|\S+)')


def parse(path):
    items = []
    with open(path, encoding="utf-8") as f:
        for raw in f:
            m = LINE.match(raw.rstrip("\n"))
            if not m:
                continue
            indent, name, kind, rect, rest = m.groups()
            fields = {k: v for k, v in FIELD.findall(rest)}
            r = None if rect == "unanchored" else [float(x) for x in rect.split(",")]
            items.append({"depth": len(indent) // 2, "name": name, "type": kind, "rect": r, "f": fields})
    return items


def rgba(s, default=(255, 255, 255, 255), alpha=1.0):
    if not s:
        c = default
    else:
        parts = [float(x) for x in s.split(",")]
        c = tuple(int(max(0.0, min(1.0, p)) * 255) for p in parts[:4])
    return c[:3] + (int(c[3] * alpha),)


def texture_file(tex, media):
    m = re.match(r'(?i)interface[\\/]+addons[\\/]+perlinfinity[\\/]+media[\\/]+(.+)$', tex or "")
    if not m:
        return None
    base = os.path.join(media, m.group(1).replace("\\", "/"))
    for ext in ("", ".blp", ".tga", ".png"):
        if os.path.exists(base + ext):
            return base + ext
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("-o", "--out")
    ap.add_argument("--media", default="PerlInfinity/Media")
    ap.add_argument("--scale", type=float, default=2.0)
    a = ap.parse_args()
    items = parse(a.dump)
    # A frame's alpha applies to everything inside it.
    stack = []
    for it in items:
        while stack and stack[-1][0] >= it["depth"]:
            stack.pop()
        inherited = stack[-1][1] if stack else 1.0
        it["alpha"] = inherited * float(it["f"].get("alpha", "1"))
        stack.append((it["depth"], it["alpha"]))
    items = [i for i in items if i["rect"]]
    if not items:
        print("preview: nothing anchored in " + a.dump)
        return 1
    left = min(i["rect"][0] for i in items) - 10
    bottom = min(i["rect"][1] for i in items) - 10
    right = max(i["rect"][0] + i["rect"][2] for i in items) + 10
    top = max(i["rect"][1] + i["rect"][3] for i in items) + 10
    s = a.scale
    img = Image.new("RGBA", (int((right - left) * s), int((top - bottom) * s)), (24, 24, 28, 255))
    # "RGBA" mode blends translucent fills over what is already drawn.
    draw = overlay = ImageDraw.Draw(img, "RGBA")

    def box(r):
        x0 = (r[0] - left) * s
        y0 = (top - (r[1] + r[3])) * s
        return [x0, y0, x0 + r[2] * s, y0 + r[3] * s]

    for it in items:
        b, f, kind = box(it["rect"]), it["f"], it["type"]
        if b[2] - b[0] < 1 or b[3] - b[1] < 1:
            continue
        alpha = it["alpha"]
        if alpha <= 0:
            continue
        if kind == "Texture":
            path = texture_file(f.get("tex", ""), a.media)
            tint = rgba(f.get("vc"))
            if path:
                try:
                    tex = Image.open(path).convert("RGBA").resize((int(b[2] - b[0]), int(b[3] - b[1])))
                    if tint != (255, 255, 255, 255):
                        tex = ImageChops.multiply(tex, Image.new("RGBA", tex.size, tint))
                    if alpha < 1:
                        tex.putalpha(tex.split()[3].point(lambda p: int(p * alpha)))
                    img.alpha_composite(tex, (int(b[0]), int(b[1])))
                    continue
                except Exception as e:  # noqa: BLE001 - preview only
                    print("preview: cannot draw %s: %s" % (path, e), file=sys.stderr)
            if "color" in f:
                overlay.rectangle(b, fill=rgba(f["color"], alpha=alpha))
            elif f.get("tex") or f.get("atlas"):
                # Game art the renderer can't load: a faint outline marks the spot.
                draw.rectangle(b, outline=(90, 90, 110, 255))
        elif kind == "StatusBar":
            # A status bar has no background of its own; backgrounds are
            # separate textures in the dump.
            m = re.match(r'([-\d.]+)/([-\d.]+)\.\.([-\d.]+)', f.get("value", ""))
            if m:
                v, lo, hi = (float(x) for x in m.groups())
                frac = 0 if hi <= lo else max(0.0, min(1.0, (v - lo) / (hi - lo)))
                overlay.rectangle([b[0], b[1], b[0] + (b[2] - b[0]) * frac, b[3]], fill=rgba(f.get("bar"), (40, 200, 60, 255), alpha))
        elif kind == "FontString":
            text = f.get("text", "")
            text = text.replace("(secret)", "")
            if text.startswith('"'):
                text = bytes(text[1:-1], "utf-8").decode("unicode_escape")
            text = re.sub(r'\|c[0-9a-fA-F]{8}|\|r', "", text)
            size = int(float(f.get("size", "12")) * s)
            try:
                font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", size)
            except OSError:
                font = ImageFont.load_default()
            overlay.text((b[0], b[1]), text, fill=rgba(f.get("tc"), (255, 210, 0, 255), alpha), font=font)
        else:
            draw.rectangle(b, outline=rgba(f.get("border"), (120, 120, 140, 255)))
            if "bg" in f:
                overlay.rectangle(b, fill=rgba(f["bg"], alpha=alpha))
    out = a.out or os.path.splitext(a.dump)[0] + ".png"
    img.save(out)
    print("preview: wrote " + out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
