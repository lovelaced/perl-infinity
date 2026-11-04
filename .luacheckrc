-- .luacheckrc for Perl Infinity (luacheck 1.2, run from the repo root: `make lint`).
-- WoW globals come from tools/out/wow_globals.lua (`make gen`: API docs + FrameXML scan +
-- tools/globals_extra.txt). Without it, the API-doc names and the extras list are used.
-- Only locals here: every global assignment in this file becomes a luacheck option.

-- WoW's Lua 5.1 additions to the standard library
stds.wow_lua = {
	read_globals = {
		bit = { fields = { "band", "bor", "bxor", "bnot", "lshift", "rshift", "arshift", "mod", "tobit", "tohex" } },
		table = { fields = { "wipe", "count", "isempty", "removemulti", "create" } },
		string = { fields = { "split", "join", "trim", "rtgsub" } },
	},
}
std = "lua51+wow_lua"
max_line_length = false
codes = true
-- 212: unused arguments (event handlers and mixin methods keep WoW's signatures)
ignore = { "212" }
exclude_files = { "PerlInfinity/Libs/**", "tools/out/**", ".release/**" }

local function readLines(path)
	local f = io.open(path, "r")
	if not f then return {} end
	local lines = {}
	for line in f:lines() do lines[#lines + 1] = line end
	f:close()
	return lines
end

-- name -> member set (C_ namespaces get field checking; other tables stay open)
local wow, members = {}, {}
local ok, G = pcall(dofile, "tools/out/wow_globals.lua")
if ok and type(G) == "table" then
	for _, g in ipairs(G.globals or {}) do wow[g] = true end
	for t, list in pairs(G.members or {}) do
		members[t] = members[t] or {}
		for _, m in ipairs(list) do members[t][m] = true end
	end
else
	local okTags, T = pcall(dofile, "tests/harness/api_tags.lua")
	if okTags and type(T) == "table" then
		for key in pairs(T.functions) do
			local ns, fn = key:match("^([%w_]+)%.([%w_]+)$")
			if ns then
				wow[ns] = true
				members[ns] = members[ns] or {}
				members[ns][fn] = true
			else
				wow[key] = true
			end
		end
	end
	for _, line in ipairs(readLines("tools/globals_extra.txt")) do
		local name = line:gsub("#.*$", ""):match("^%s*(%S+)")
		if name then wow[name:match("^([%a_][%w_]*)")] = true end
	end
	wow.Enum, wow.Constants = true, true
end

-- Writable: our own globals, plus Blizzard tables addons are meant to add to.
local own = {
	"PerlInfinity", "PerlInfinityDB", "PerlInfinityCharDB", "PerlInfinityLog", "SLASH_PERLINFINITY1", "SLASH_PERLINFINITY2", "BINDING_HEADER_PERLINFINITY",
	"PerlInfinity_OnAddonCompartmentClick", "PerlInfinity_OnAddonCompartmentEnter", "PerlInfinity_OnAddonCompartmentLeave",
	"PerlInfinityUnitButtonMixin", "PerlInfinityPreviewRowMixin",
	"SlashCmdList", "hash_SlashCmdList", "StaticPopupDialogs", "UISpecialFrames", "ClickCastFrames",
}
-- BINDING_NAME_PERLINFINITY_* from Bindings.xml
for _, line in ipairs(readLines("PerlInfinity/Bindings.xml")) do
	local name = line:match('<Binding%s+name="([%w_]+)"')
	if name then own[#own + 1] = "BINDING_NAME_" .. name end
end
globals = own

local ownSet = {}
for _, g in ipairs(own) do ownSet[g] = true end
local rg = { "LibStub", "BugGrabber" } -- optional third-party, always nil-checked
for name in pairs(wow) do
	if not ownSet[name] then
		if name:match("^C_") and members[name] then
			local fields = {}
			for m in pairs(members[name]) do fields[m] = { read_only = true } end
			rg[name] = { fields = fields }
		else
			rg[#rg + 1] = name
		end
	end
end
read_globals = rg

-- Test fixtures are addon code: WoW std plus the fixture's own globals.
files["tests/fixtures/**"] = {
	globals = { "FixtureDB", "FixtureCharDB", "SLASH_FIXTURE1", "FixtureUnitButtonMixin", "FixtureAddon_ToggleBinding" },
}
-- Harness, runner, specs and tools run under plain LuaJIT.
-- secret.lua patches string.format on purpose (secret-aware formatting)
files["tests/harness/**"] = { std = "luajit", ignore = { "212", "213", "542", "122/string" } }
-- `not (v > n)` is deliberate in assertions (NaN-safe)
files["tests/run.lua"] = { std = "luajit", ignore = { "212", "581" } }
files["tests/spec/**"] = {
	std = "luajit",
	read_globals = { "describe", "it", "expect", "pending", "Harness", "Secret", "MODE", "FUZZ", "ROOT", "VERBOSE" },
}
files["tools/**"] = { std = "luajit" }
