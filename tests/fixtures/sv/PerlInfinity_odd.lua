-- Synthetic PerlInfinity.lua with wrong types and missing fields: readsv must not crash.

PerlInfinityDB = "not a table"
PerlInfinityLog = {
	["meta"] = "oops",
	["errors"] = { "a bare string error", { ["count"] = "many", ["stack"] = 5, ["ctx"] = "combat" }, 7 },
	["blocked"] = 7,
	["census"] = { ["openWorldCombat"] = 4 },
	["selfTest"] = true,
	["sessions"] = {
		"bad",
		{ ["matrix"] = { ["normal"] = "S" }, ["perf"] = { ["micro"] = { ["a"] = 5 } }, ["screenshots"] = { "label only" }, ["manifest"] = { ["missing"] = { "GetSpellInfo", "UnitAura" } } },
		{ ["matrix"] = { ["normal"] = { ["player"] = 3 } }, ["perf"] = "slow", ["char"] = "DRUID" },
	},
}
