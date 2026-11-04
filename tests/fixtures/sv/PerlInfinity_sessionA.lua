-- Synthetic PerlInfinity.lua for tools/readsv.lua: two sessions, every report section filled.

PerlInfinityDB = {
	["schema"] = 3,
	["profiles"] = {
		["Default"] = {},
		["Healer"] = {},
	},
	["positions"] = {
		["Modern"] = {},
		["Classic"] = {},
	},
}
PerlInfinityLog = {
	["meta"] = {
		["addon"] = "0.1.0-beta-a",
		["build"] = "1.60.1.70338",
		["toc"] = 16001,
		["locale"] = "enUS",
		["loads"] = 2,
	},
	["dropped"] = 0,
	["errors"] = {
		["Interface/AddOns/PerlInfinity/Elements/Health.lua:42: attempt to compare"] = {
			["msg"] = "Interface/AddOns/PerlInfinity/Elements/Health.lua:42: attempt to compare number with a secret value",
			["stack"] = "[string \"@Interface/AddOns/PerlInfinity/Elements/Health.lua\"]:42: in function 'Update'\n[string \"@Interface/AddOns/PerlInfinity/Unit/UnitFrame.lua\"]:88: in function <Interface/AddOns/PerlInfinity/Unit/UnitFrame.lua:80>\n[C]: in function 'securecallfunction'\n[string \"@Interface/AddOns/PerlInfinity/Core/Scheduler.lua\"]:20: in function <...>",
			["count"] = 37,
			["first"] = 1760551200,
			["last"] = 1760551260,
			["ctx"] = { ["combat"] = true, ["instance"] = "none", ["restrictions"] = { "Combat" }, ["frame"] = "target/Health" },
		},
		["Interface/AddOns/PerlInfinity/Diag/SelfTest.lua:120: bad argument"] = {
			["msg"] = "Interface/AddOns/PerlInfinity/Diag/SelfTest.lua:120: bad argument #1 to 'SetCVar'",
			["stack"] = "Interface/AddOns/PerlInfinity/Diag/SelfTest.lua:120: in function <Interface/AddOns/PerlInfinity/Diag/SelfTest.lua:110>",
			["count"] = 1,
			["first"] = 1760551000,
			["last"] = 1760551000,
			["ctx"] = { ["combat"] = false },
		},
	},
	["errorOrder"] = { "Interface/AddOns/PerlInfinity/Elements/Health.lua:42: attempt to compare", "Interface/AddOns/PerlInfinity/Diag/SelfTest.lua:120: bad argument" },
	["blocked"] = {
		["BLOCKED:Button:SetPoint"] = {
			["kind"] = "BLOCKED",
			["fn"] = "Button:SetPoint()",
			["count"] = 2,
			["first"] = 1760551230,
			["last"] = 1760551231,
			["stack"] = "Interface/AddOns/PerlInfinity/EditMode/Movers.lua:61: in function 'Apply'",
		},
	},
	["census"] = {
		["openWorldCombat"] = {
			["UnitHealth.player"] = "secret",
			["UnitName.target"] = "plain:string",
			["UnitIsAFK.party1"] = "nil",
			["GetComboPoints"] = "secret",
		},
		["instanceIdle"] = {
			["UnitHealth.player"] = "secret",
			["UnitName.target"] = "secret",
			["UnitIsAFK.party1"] = "secret",
			["GetComboPoints"] = "plain:number",
		},
	},
	["selfTest"] = {
		["ok"] = 6,
		["failed"] = 1,
		["notes"] = 2,
		["steps"] = {
			{ ["name"] = "Environment", ["ok"] = true },
			{ ["name"] = "Manifest", ["ok"] = true, ["notes"] = "2 missing atlases" },
			{ ["name"] = "Secrecy matrix", ["ok"] = true },
			{ ["name"] = "Forced combat restriction", ["ok"] = false, ["error"] = "SetCVar refused; /console addonCombatRestrictionsForced 1" },
			{ ["name"] = "Headers", ["ok"] = true },
			{ ["name"] = "Auras", ["skipped"] = true, ["reason"] = "in combat" },
			{ ["name"] = "CPU", ["ok"] = true },
		},
		["matrix"] = {
			["UnitHealth.player"] = { ["normal"] = "secret", ["combatForced"] = "secret" },
			["UnitHealthMax.target"] = { ["normal"] = "secret", ["combatForced"] = "secret" },
			["GetRaidTargetIndex.target"] = { ["normal"] = "plain:number", ["combatForced"] = "secret" },
			["C_UnitAuras.GetAuraDataByIndex.player"] = { ["normal"] = "plain:table", ["combatForced"] = "error:Auras cannot be accessed when secret" },
		},
	},
	["sessions"] = {
		{
			["time"] = 1760550000,
			["build"] = "1.60.1.70338",
			["toc"] = 16001,
			["addonBuild"] = "a1b2c3d",
			["char"] = { ["class"] = "DRUID", ["level"] = 60 },
			["matrix"] = {
				["normal"] = {
					["player"] = { ["UnitHealth"] = "S", ["UnitPower"] = "S", ["UnitIsAFK"] = "P:false" },
					["target"] = { ["UnitHealth"] = "S", ["UnitName"] = "P:Defias Thug", ["GetRaidTargetIndex"] = "P:8" },
				},
				["combatForced"] = {
					["player"] = { ["UnitHealth"] = "S", ["UnitPower"] = "S", ["UnitIsAFK"] = "P:false" },
					["target"] = { ["UnitHealth"] = "S", ["UnitName"] = "P:Defias Thug", ["GetRaidTargetIndex"] = "S" },
				},
			},
			["perf"] = {
				["micro"] = {
					["healthPush"] = { ["elapsedMilliseconds"] = 0.0040, ["allocatedBytes"] = 0 },
					["auraRefresh"] = { ["elapsedMilliseconds"] = 0.0300, ["allocatedBytes"] = 64 },
				},
				["flushCount"] = 1200,
				["flushMaxMs"] = 0.8,
			},
			["errors"] = {
				["old"] = { ["msg"] = "Interface/AddOns/PerlInfinity/Frames/Party.lua:10: attempt to index a nil value", ["count"] = 3 },
			},
		},
		{
			["time"] = 1760551000,
			["build"] = "1.60.1.70338",
			["toc"] = 16001,
			["addonBuild"] = "d4e5f6a",
			["char"] = { ["class"] = "DRUID", ["level"] = 60 },
			["phases"] = { ["environment"] = { ["ok"] = true } },
			["matrix"] = {
				["normal"] = {
					["player"] = { ["UnitHealth"] = "S", ["UnitPower"] = "S", ["UnitIsAFK"] = "P:false" },
					["target"] = { ["UnitHealth"] = "S", ["UnitName"] = "P:Defias Thug", ["GetRaidTargetIndex"] = "S" },
				},
				["combatForced"] = {
					["player"] = { ["UnitHealth"] = "S", ["UnitPower"] = "S", ["UnitIsAFK"] = "S" },
					["target"] = { ["UnitHealth"] = "S", ["UnitName"] = "S", ["GetRaidTargetIndex"] = "E:bad argument" },
				},
			},
			["manifest"] = {
				["missing"] = {
					["atlases"] = { "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", "XPerl-Elite" },
					["globals"] = { "DebuffTypeColor" },
				},
			},
			["perf"] = {
				["micro"] = {
					["healthPush"] = { ["elapsedMilliseconds"] = 0.0035, ["allocatedBytes"] = 0 },
					["auraRefresh"] = { ["elapsedMilliseconds"] = 0.0450, ["allocatedBytes"] = 0 },
				},
				["flushCount"] = 1450,
				["flushMaxMs"] = 1.2,
				["profiler"] = { ["SessionAverageTime"] = 0.012, ["PeakTime"] = 3.4 },
				["samples"] = { { ["recentAverageTime"] = 0.010 }, { ["recentAverageTime"] = 0.030 }, { ["recentAverageTime"] = 0.020 } },
				["topK"] = { { ["name"] = "PerlInfinity", ["value"] = 0.03 }, { ["name"] = "Blizzard_UnitFrame", ["value"] = 0.02 } },
			},
			["screenshots"] = {
				{ ["time"] = 1760551100, ["label"] = "combat sampler +1.5s" },
				{ ["time"] = 1760551400, ["label"] = "Edit Mode enter" },
			},
			["errors"] = {
				["health"] = {
					["msg"] = "Interface/AddOns/PerlInfinity/Elements/Health.lua:42: attempt to compare number with a secret value",
					["stack"] = "Interface/AddOns/PerlInfinity/Elements/Health.lua:42: in function 'Update'",
					["count"] = 37,
				},
			},
		},
	},
}
