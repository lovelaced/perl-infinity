-- tests/harness/loader.lua
-- Loads an addon the way the client does: parses the TOC (## metadata, SavedVariables,
-- file list with [AllowLoadGameType]/[ExcludeLoadGameType] annotations), runs each
-- Lua file with (addonName, ns) in the sandbox, and handles XML minimally: <Script>,
-- <Include>, virtual templates (registered for CreateFrame), named frames and
-- Bindings.xml. LibEditMode under Libs/ is replaced by the recording stub.

local X = require("xml")

local L = {}

local GAME = { camelot = true, forever = true, mainline = true }

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function allowed(annotations)
  local allow = annotations:match("%[AllowLoadGameType%s+([^%]]+)%]")
  local exclude = annotations:match("%[ExcludeLoadGameType%s+([^%]]+)%]")
  if allow then
    local ok = false
    for t in allow:gmatch("[%w_]+") do if GAME[t] then ok = true end end
    if not ok then return false end
  end
  if exclude then for t in exclude:gmatch("[%w_]+") do if t == "camelot" or t == "forever" then return false end end end
  return true
end

function L.parseToc(path)
  local src = readFile(path)
  if not src then error("loader: cannot read " .. path) end
  local toc = { meta = {}, files = {}, savedVariables = {}, savedVariablesPerCharacter = {}, skipped = {} }
  for line in src:gmatch("[^\r\n]+") do
    local key, value = line:match("^##%s*([^:]+):%s*(.-)%s*$")
    if key then
      toc.meta[key] = value
      if key == "SavedVariables" then for n in value:gmatch("[%w_]+") do table.insert(toc.savedVariables, n) end end
      if key == "SavedVariablesPerCharacter" then for n in value:gmatch("[%w_]+") do table.insert(toc.savedVariablesPerCharacter, n) end end
    elseif not line:match("^%s*#") and line:match("%S") then
      local file, rest = line:match("^%s*([^%[%s][^%[]-)%s*(%[.*)$")
      if not file then file, rest = line:match("^%s*(.-)%s*$"), "" end
      file = file:gsub("%[Family%]", "Mainline"):gsub("%[Game%]", "Camelot"):gsub("\\", "/")
      if allowed(rest) then table.insert(toc.files, file) else table.insert(toc.skipped, file) end
    end
  end
  local header = toc.meta.AllowLoadGameType
  if header then
    local ok = false
    for t in header:gmatch("[%w_]+") do if GAME[t] then ok = true end end
    toc.loadsOnForever = ok
  else
    toc.loadsOnForever = true
  end
  return toc
end

local function sizeOf(node)
  local s = X.child(node, "Size")
  if not s then return nil end
  local abs = X.child(s, "AbsDimension")
  local a = abs and abs.attrs or s.attrs
  return { x = tonumber(a.x), y = tonumber(a.y) }
end

local function attrValue(a)
  local v = a.value
  if a.type == "number" then return tonumber(v) end
  if a.type == "boolean" then return v == "true" end
  return v
end

local FRAME_TAGS = { Frame = 1, Button = 1, CheckButton = 1, StatusBar = 1, Cooldown = 1, EditBox = 1, GameTooltip = 1,
  PlayerModel = 1, Model = 1, Slider = 1, ScrollFrame = 1, AuraContainer = 1, MessageFrame = 1, DressUpModel = 1 }

local function childSpecs(h, node)
  local specs = {}
  local layers = X.child(node, "Layers")
  if layers then
    for _, layer in ipairs(X.children(layers, "Layer")) do
      for _, r in ipairs(layer.children) do
        if r.tag == "Texture" or r.tag == "FontString" or r.tag == "MaskTexture" then
          local anchors = {}
          local an = X.child(r, "Anchors")
          for _, a in ipairs(an and X.children(an, "Anchor") or {}) do
            local off = X.child(a, "Offset")
            local abs = off and (X.child(off, "AbsDimension") or off)
            anchors[#anchors + 1] = { point = a.attrs.point, relativeKey = a.attrs.relativeKey, relativeTo = a.attrs.relativeTo,
              relativePoint = a.attrs.relativePoint, x = tonumber(a.attrs.x or (abs and abs.attrs.x)) or 0,
              y = tonumber(a.attrs.y or (abs and abs.attrs.y)) or 0 }
          end
          specs[#specs + 1] = { objType = r.tag, name = r.attrs.name, layer = layer.attrs.level, inherits = r.attrs.inherits,
            parentKey = r.attrs.parentKey, parentArray = r.attrs.parentArray, size = sizeOf(r), anchors = anchors,
            setAllPoints = r.attrs.setAllPoints == "true", hidden = r.attrs.hidden == "true", file = r.attrs.file,
            atlas = r.attrs.atlas, text = r.attrs.text }
        end
      end
    end
  end
  local frames = X.child(node, "Frames")
  for _, f in ipairs(frames and frames.children or {}) do
    if FRAME_TAGS[f.tag] then
      specs[#specs + 1] = { objType = f.tag, name = f.attrs.name, inherits = f.attrs.inherits, parentKey = f.attrs.parentKey,
        parentArray = f.attrs.parentArray, size = sizeOf(f), setAllPoints = f.attrs.setAllPoints == "true",
        hidden = f.attrs.hidden == "true" }
    end
  end
  local _ = h
  return specs
end

local function templateFromNode(h, node)
  local t = { name = node.attrs.name, type = node.tag, inherits = node.attrs.inherits, mixin = node.attrs.mixin,
    size = sizeOf(node), source = "xml" }
  if node.attrs.secureMixin then t.mixin = (t.mixin and (t.mixin .. ",") or "") .. node.attrs.secureMixin end
  local attrs = X.child(node, "Attributes")
  if attrs then
    t.attributes = {}
    for _, a in ipairs(X.children(attrs, "Attribute")) do t.attributes[a.attrs.name] = attrValue(a.attrs) end
  end
  local kv = X.child(node, "KeyValues")
  if kv then
    t.keyValues = {}
    for _, k in ipairs(X.children(kv, "KeyValue")) do
      local v = k.attrs.value
      if k.attrs.type == "number" then v = tonumber(v) elseif k.attrs.type == "boolean" then v = v == "true"
      elseif k.attrs.type == "global" then v = h.env[v] end
      t.keyValues[k.attrs.key] = v
    end
  end
  local scripts = X.child(node, "Scripts")
  if scripts then
    t.scripts = {}
    for _, s in ipairs(scripts.children) do
      local text = s.text and s.text:match("^%s*(.-)%s*$") or ""
      t.scripts[s.tag] = { method = s.attrs.method, func = s.attrs["function"], code = (text ~= "" and text or nil),
        intrinsicOrder = s.attrs.intrinsicOrder, inherit = s.attrs.inherit }
    end
  end
  t.children = childSpecs(h, node)
  if #t.children == 0 then t.children = nil end
  return t
end

-- Loads a Lua file with (addonName, ns); errors are recorded, loading continues.
local function runLua(h, addon, path)
  local fn, err = loadfile(path)
  if not fn then
    h:dispatchError(err, "load " .. path)
    return false
  end
  setfenv(fn, h.env)
  local ok = h:protectedCall(fn, "load " .. path, addon.name, addon.ns)
  addon.loaded[#addon.loaded + 1] = path
  return ok
end

local function isLEM(path) return path:lower():find("libs/libeditmode/", 1, true) ~= nil end

local function installLEM(h, addon)
  if addon.lemInstalled then return end
  addon.lemInstalled = true
  addon.ns.LibEditMode = require("LibEditMode").new(h)
end

local loadXml
local function loadFile(h, addon, path)
  if isLEM(path) then
    installLEM(h, addon)
    addon.substituted[#addon.substituted + 1] = path
    return
  end
  local lower = path:lower()
  if lower:match("%.lua$") then runLua(h, addon, path)
  elseif lower:match("%.xml$") then loadXml(h, addon, path)
  else h:warn("loader: unknown file type " .. path) end
end

function loadXml(h, addon, path)
  local src = readFile(path)
  if not src then h:dispatchError("loader: missing file " .. path, "load"); return end
  local ok, tree = pcall(X.parse, src, path)
  if not ok then h:dispatchError(tree, "parse " .. path); return end
  local dir = path:match("^(.*)/[^/]*$") or "."
  local ui = X.child(tree, "Ui") or tree
  for _, node in ipairs(ui.children) do
    local file = node.attrs.file
    if (node.tag == "Script" or node.tag == "Include") and file then
      loadFile(h, addon, dir .. "/" .. file:gsub("\\", "/"))
    elseif node.tag == "Script" then
      local code = node.text:match("^%s*(.-)%s*$")
      if code ~= "" then
        local fn, err = loadstring(code, "=" .. path .. ":Script")
        if fn then setfenv(fn, h.env); h:protectedCall(fn, "xml script " .. path) else h:dispatchError(err, path) end
      end
    elseif FRAME_TAGS[node.tag] or node.tag == "Font" then
      local name = node.attrs.name
      if node.attrs.virtual == "true" then
        if not name then h:dispatchError("virtual template without a name in " .. path, "load") else
          if h.widgets.templates[name] and h.widgets.templates[name].source == "xml" then
            h:warn("template '" .. name .. "' defined twice")
          end
          h.widgets.templates[name] = templateFromNode(h, node)
          addon.templates[#addon.templates + 1] = name
        end
      elseif node.tag ~= "Font" then
        local parent = node.attrs.parent and h.env[node.attrs.parent] or h.env.UIParent
        h:protectedCall(function()
          local f = h.env.CreateFrame(node.tag, name, parent, node.attrs.inherits)
          local t = templateFromNode(h, node)
          h.widgets.applyTemplate(f, t, {})
          if node.attrs.hidden == "true" then f:Hide() end
        end, "xml frame " .. tostring(name))
      end
    elseif node.tag ~= "Ui" then
      h:warn("loader: XML element <" .. node.tag .. "> not modelled (" .. path .. ")")
    end
  end
end

local function loadBindings(h, addon)
  local path = addon.dir .. "/Bindings.xml"
  local src = readFile(path)
  if not src then return end
  local ok, tree = pcall(X.parse, src, path)
  if not ok then h:dispatchError(tree, "parse " .. path); return end
  local root = X.child(tree, "Bindings") or tree
  for _, b in ipairs(X.children(root, "Binding")) do
    addon.bindings[#addon.bindings + 1] = { name = b.attrs.name, header = b.attrs.header, category = b.attrs.category,
      runOnUp = b.attrs.runOnUp, code = b.text:match("^%s*(.-)%s*$") }
  end
end

-- Runs a binding's body like the client would (for tests).
function L.runBinding(h, name, keystate)
  for _, b in ipairs(h.addon.bindings) do
    if b.name == name then
      local fn, err = loadstring("local keystate = ...; " .. b.code, "=Bindings.xml:" .. name)
      if not fn then h:dispatchError(err, "binding " .. name); return false end
      setfenv(fn, h.env)
      return h:protectedCall(fn, "binding " .. name, keystate or "down")
    end
  end
  error("no binding " .. tostring(name))
end

function L.load(h, tocPath, opts)
  local toc = L.parseToc(tocPath)
  local dir = tocPath:match("^(.*)/[^/]*$") or "."
  local name = (opts and opts.name) or tocPath:match("([^/]+)%.toc$"):gsub("_[%a]+$", "")
  local addon = { name = name, dir = dir, tocPath = tocPath, meta = toc.meta, files = toc.files, skipped = toc.skipped,
    savedVariables = toc.savedVariables, savedVariablesPerCharacter = toc.savedVariablesPerCharacter,
    ns = {}, loaded = {}, substituted = {}, templates = {}, bindings = {}, loadsOnForever = toc.loadsOnForever }
  h.addon = addon
  h.addonName = name
  require("secret").taint = name
  if not toc.loadsOnForever then h:warn("TOC AllowLoadGameType does not include camelot/forever") end
  for _, file in ipairs(toc.files) do loadFile(h, addon, dir .. "/" .. file) end
  loadBindings(h, addon)
  return addon
end

return L
