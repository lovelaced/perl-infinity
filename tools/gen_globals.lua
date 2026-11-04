-- tools/gen_globals.lua
-- Scans the Blizzard UI source for globals and XML templates that exist on Forever
-- (game type "camelot", which is in the "mainline" family), following each Blizzard
-- addon's TOC and its [AllowLoadGameType]/[ExcludeLoadGameType] annotations.
--
-- Writes:
--   tools/out/wow_globals.lua          globals + members (lint L6, .luacheckrc)
--   tests/harness/blizzard_templates.lua  template names/types (harness; names only)
--
-- usage: luajit tools/gen_globals.lua [uiRoot]

local UI_ROOT = arg[1] or os.getenv("WOW_UI_SOURCE") or "wow-ui-source/Interface/AddOns"
local OUT_GLOBALS = "tools/out/wow_globals.lua"
local OUT_TEMPLATES = "tests/harness/blizzard_templates.lua"

local GAME = { camelot = true, forever = true, mainline = true }
local FAMILY, GAMEDIR = "Mainline", "Camelot"

local function readFile(path)
  local f = io.open(path, "rb"); if not f then return nil end
  local s = f:read("*a"); f:close(); return s
end

local function listDirs(root)
  local r = {}
  local p = assert(io.popen('ls "' .. root .. '"'))
  for name in p:lines() do r[#r + 1] = name end
  p:close(); table.sort(r); return r
end

-- "[AllowLoadGameType a, b] [ExcludeLoadGameType c]" -> allowed on camelot?
local function annotationsAllow(s)
  local allow = s:match("%[AllowLoadGameType%s+([^%]]+)%]")
  local exclude = s:match("%[ExcludeLoadGameType%s+([^%]]+)%]")
  if allow then
    local ok = false
    for t in allow:gmatch("[%w_]+") do if GAME[t] then ok = true end end
    if not ok then return false end
  end
  if exclude then
    for t in exclude:gmatch("[%w_]+") do if t == "camelot" or t == "forever" then return false end end
  end
  return true
end

local globals, members, templates = {}, {}, {}
local filesScanned = 0

local function addMember(tbl, key)
  members[tbl] = members[tbl] or {}
  members[tbl][key] = true
end

local referenced = {}  -- ALL_CAPS globals Blizzard code reads (GlobalStrings, constants)

local function scanLua(src)
  filesScanned = filesScanned + 1
  local fileLocals = {}
  for decl in src:gmatch("local[ \t]+([%w_, \t]+)") do
    for id in decl:gmatch("[%a_][%w_]*") do fileLocals[id] = true end
  end
  for line in (src .. "\n"):gmatch("([^\n]*)\n") do
    local code = line:gsub("%-%-.*$", ""):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''")
    for pre, id in code:gmatch("([%.:]?)%f[%w_]([A-Z][A-Z0-9_]+)%f[^%w_]") do
      if pre == "" and not fileLocals[id] then referenced[id] = true end
    end
    local name = line:match("^function%s+([%a_][%w_]*)%s*%(")
    if name then globals[name] = true end
    local tbl, key = line:match("^function%s+([%a_][%w_]*)[%.:]([%a_][%w_]*)")
    if tbl then globals[tbl] = true; addMember(tbl, key) end
    -- "Name = ..." / "A, B = ..." at column 0 (the "=" may end the line: "Foo =\n{")
    local lhs, after = line:match("^([%a_][%w_]*%s*[,%w_%s]*)=(.?)")
    if lhs and after ~= "=" and not line:match("^local%s") and not line:match("^return") then
      for n in lhs:gmatch("[%a_][%w_]*") do globals[n] = true end
    end
    local t2, k2, after2 = line:match("^([%a_][%w_]*)%.([%a_][%w_]*)%s*=(.?)")
    if t2 and after2 ~= "=" then addMember(t2, k2) end
    for g in line:gmatch('_G%[%s*"([%a_][%w_]*)"%s*%]%s*=') do globals[g] = true end
    -- CreateFrame("Type", "GlobalName", ...) anywhere creates a named global
    for g in line:gmatch('CreateFrame%(%s*["\'][%w_]+["\']%s*,%s*["\']([%a_][%w_]*)["\']') do globals[g] = true end
  end
end

local function attr(tagText, name)
  return tagText:match("%s" .. name .. '%s*=%s*"([^"]*)"')
end

local scanFile
local function scanXml(src, dir)
  filesScanned = filesScanned + 1
  src = src:gsub("<!%-%-.-%-%->", "")
  for tag, body in src:gmatch("<([%a_]+)(%s[^>]*)>") do
    local file = attr(body, "file")
    if (tag == "Script" or tag == "Include") and file then
      scanFile(dir .. "/" .. file:gsub("\\", "/"))
    end
    local name = attr(body, "name")
    if name and not name:find("%$") then
      if attr(body, "virtual") == "true" then
        templates[name] = { type = tag, inherits = attr(body, "inherits"), mixin = attr(body, "mixin") }
      else
        globals[name] = true
      end
      -- fonts are global objects even when virtual
      if tag == "Font" or tag == "FontFamily" then globals[name] = true end
    end
  end
end

function scanFile(path)
  path = path:gsub("%[Family%]", FAMILY):gsub("%[Game%]", GAMEDIR)
  local src = readFile(path)
  if not src then return end
  local dir = path:match("^(.*)/[^/]*$") or "."
  if path:lower():match("%.lua$") then scanLua(src) elseif path:lower():match("%.xml$") then scanXml(src, dir) end
end

local addonsScanned = 0
for _, addon in ipairs(listDirs(UI_ROOT)) do
  if addon ~= "Blizzard_APIDocumentationGenerated" and addon ~= "Blizzard_APIDocumentation" then
    local toc = readFile(UI_ROOT .. "/" .. addon .. "/" .. addon .. ".toc")
    if toc then
      local header = toc:match("##%s*AllowLoadGameType:%s*([^\n]+)")
      local ok = true
      if header then
        ok = false
        for t in header:gmatch("[%w_]+") do if GAME[t] then ok = true end end
      end
      if ok then
        addonsScanned = addonsScanned + 1
        for line in toc:gmatch("[^\r\n]+") do
          if not line:match("^%s*#") and line:match("%S") then
            local file = line:match("^%s*([^%s%[]+[^%[]-)%s*%[") or line:match("^%s*(.-)%s*$")
            local inlineTags = line:match("(%[.*)$") or ""
            -- "[Family]\X.lua [AllowLoadGameType ...]": the first bracket may be a path token
            local pathPart = line:match("^%s*(%S+)")
            if pathPart and annotationsAllow(inlineTags:gsub("^%[Family%]", ""):gsub("^%[Game%]", "")) then
              scanFile(UI_ROOT .. "/" .. addon .. "/" .. pathPart:gsub("\\", "/"))
            end
            local _ = file
          end
        end
      end
    end
  end
end

-- API-documented globals (functions and namespaces) come from api_tags.
local tags = assert(loadfile("tests/harness/api_tags.lua"))()
for key in pairs(tags.functions) do
  local ns, fn = key:match("^([%w_]+)%.([%w_]+)$")
  if ns then globals[ns] = true; addMember(ns, fn) else globals[key] = true end
end
globals.Enum, globals.Constants = true, true

-- If loaded Blizzard code reads an ALL_CAPS global it doesn't define, the client
-- provides it (GlobalStrings.lua and constants are not in the sparse checkout).
local referencedCount = 0
for id in pairs(referenced) do
  if not globals[id] then globals[id] = true; referencedCount = referencedCount + 1 end
end

-- Hand-maintained extras: engine/FrameXML globals present on Forever but absent from
-- the sparse source tree (tools/globals_extra.txt; "Table.member" lines add members).
local extraCount = 0
local ef = io.open("tools/globals_extra.txt", "r")
if ef then
  for line in ef:lines() do
    local name = line:gsub("#.*$", ""):match("^%s*(%S+)")
    if name then
      local t, m = name:match("^([%a_][%w_]*)%.([%a_][%w_]*)$")
      if t then globals[t] = true; addMember(t, m) else globals[name] = true end
      extraCount = extraCount + 1
    end
  end
  ef:close()
end

local function sorted(set)
  local r = {}
  for k in pairs(set) do r[#r + 1] = k end
  table.sort(r); return r
end

os.execute("mkdir -p tools/out")
local fh = assert(io.open(OUT_GLOBALS, "w"))
fh:write("-- GENERATED by tools/gen_globals.lua (Forever 1.60.1.70338 UI source + api_tags). Do not edit.\n")
fh:write("local G = {}\nG.globals = {\n")
for _, g in ipairs(sorted(globals)) do fh:write(string.format("%q,\n", g)) end
fh:write("}\nG.members = {\n")
for _, t in ipairs(sorted(members)) do
  fh:write(string.format("[%q]={", t))
  for _, m in ipairs(sorted(members[t])) do fh:write(string.format("%q,", m)) end
  fh:write("},\n")
end
fh:write("}\nreturn G\n")
fh:close()

fh = assert(io.open(OUT_TEMPLATES, "w"))
fh:write("-- GENERATED by tools/gen_globals.lua. Virtual XML template names that load on Forever,\n")
fh:write("-- with their widget type and inherits list (names only, no Blizzard source).\n")
fh:write("return {\n")
for _, name in ipairs(sorted(templates)) do
  local t = templates[name]
  fh:write(string.format("[%q]={type=%q%s%s},\n", name, t.type,
    t.inherits and string.format(",inherits=%q", t.inherits) or "",
    t.mixin and string.format(",mixin=%q", t.mixin) or ""))
end
fh:write("}\n")
fh:close()

local nG, nT = #sorted(globals), #sorted(templates)
print(string.format("gen_globals: %d addons, %d files scanned, %d GlobalStrings/constants, %d extras; %d globals -> %s; %d templates -> %s",
  addonsScanned, filesScanned, referencedCount, extraCount, nG, OUT_GLOBALS, nT, OUT_TEMPLATES))
