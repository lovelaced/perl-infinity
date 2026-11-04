<div align="center">

# Perl Infinity

*The classic X-Perl unit frames, rewritten from scratch for WoW: Forever.*

[![License](https://img.shields.io/badge/license-GPL--3.0--or--later-blue?style=flat-square)](LICENSE)
[![Game version](https://img.shields.io/badge/WoW%3A%20Forever-1.60.1-2b6cb0?style=flat-square)](#install)
[![Latest version](https://img.shields.io/github/v/tag/lovelaced/perl-infinity?style=flat-square&label=version)](https://github.com/lovelaced/perl-infinity/tags)

<!-- TODO: add a hero screenshot from the game at assets/screenshots/party-and-target.png -->

</div>

Perl Infinity brings the dark boxes, square portraits and original bar textures of X-Perl to World of Warcraft: Forever. It replaces the game's player, target, party and raid frames, and you set it up with the game's own tools.

## Features

- **The X-Perl look**: dark translucent boxes, square portraits and the original bar textures.
- **All your frames**: player, pet, target, target of target, focus, party with each member's target and pet, and raid with raid pets.
- **Placement in Edit Mode**: drag your frames in the game's own layout editor, with snapping and positions saved per layout.
- **A settings window that feels native**: built from the game's own controls, with a live preview beside your settings.
- **Raid tools that work from your own client**: tank targets, a healer mana window, class buff checks, aggro warnings and saved raid layouts.
- **Healing and debuff cues**: incoming heals, heal over time bars, and highlights for debuffs you can remove.
- **Updates only when something changes**: frames follow game events, with a small timer only for units the game doesn't report on, like target of target.
- **Profiles**: share settings between characters, or export a profile as a line of text and send it to a friend.

## Install

Perl Infinity isn't on CurseForge yet. To install it now:

1. Download this repo with **Code > Download ZIP**, or clone it.
2. Copy the `PerlInfinity` folder into `World of Warcraft/_forever_/Interface/AddOns/`.
3. Restart the game.

Perl Infinity only loads on WoW: Forever.

## Usage

Type `/perlinfinity` or `/pinf` to open the options. You can also find it under **Options > AddOns**, or in the addon button on your minimap.

To move a frame, open Edit Mode with `/pinf move` and drag it. A party member's pet and target move with their party frame.

| Command | What it does |
|---|---|
| `/pinf` | Opens the options |
| `/pinf move` | Opens Edit Mode so you can move your frames |
| `/pinf player`, `pet`, `target`, `tot`, `focus`, `party`, `raid`, `tools`, `profiles` | Opens that page |
| `/pinf profile [name]` | Switches to a profile. With no name, lists your profiles |
| `/pinf tanks` | Shows or hides the tank targets window |
| `/pinf mana` | Shows or hides the healer mana window |
| `/pinf layouts save [name]`, `load [name]`, `stop` | Saves your raid groups, puts everyone back, or stops |
| `/pinf buffs` | Lists who in your group is missing a class buff |
| `/pinf names` | Opens a list of your raid's names you can copy |
| `/pinf reset positions` | Puts every frame back where it started |
| `/pinf selftest` | Checks Perl Infinity against your game and saves a report |

### What's different from X-Perl

Forever limits what addons can read, especially in combat, so a few things changed:

- Some old options are gone because the game blocks the data behind them, like raid-wide durability and resistance checks.
- Range checking uses your class spells automatically, or a single 40-yard mode.
- There's no compatibility code for older addons, and nothing that duplicates a feature the game already has.

### Reporting a bug

Run `/pinf selftest`, then [open an issue](https://github.com/lovelaced/perl-infinity/issues) and describe what you saw. The report is saved in `WTF/Account/<your account>/SavedVariables/PerlInfinity.lua`, so attach that too if you're happy to share it.

## Development

The tests run outside the game and need [LuaJIT](https://luajit.org/).

```bash
make test-all   # runs the offline test suite in all three modes
make lint       # checks the code (uses luacheck if you have it)
make deploy     # copies the addon into the game (set WOW_DIR if yours isn't the default macOS path)
make package    # builds PerlInfinity-<version>.zip in .release/
```

`make gen` regenerates the test suite's API data. It needs a copy of the game's interface source, which you point to with `WOW_UI_SOURCE`.

## Credits

Perl Infinity is new code, but it comes from a long line of unit frames: Perl UnitFrames by Nymbia, X-Perl UnitFrames by Zek, and Z-Perl by Resike and contributors. The frame and bar textures come from Z-Perl.

This project began under the working name F-Perl. Zeta0xD published [F-Perl](https://www.curseforge.com/wow/addons/fperl) first, so that name is theirs. It's a separate addon, and worth a look if you're comparing your options.

## License

Perl Infinity is released under the [GPL-3.0-or-later](LICENSE).

The bundled library in `PerlInfinity/Libs/LibEditMode` is by Adrian L Lange and keeps its own license, which is included in that folder. It's redistributed unmodified, as its terms allow.
