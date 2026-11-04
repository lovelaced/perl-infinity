-- Perl Infinity: X-Perl style unit frames for WoW: Forever.
--
-- Every file adds to the shared namespace `ns`. Modules made with
-- ns:NewModule get Init() once SavedVariables are loaded (ADDON_LOADED) and
-- Login() at PLAYER_LOGIN, in TOC order. Files never do work at load time
-- beyond defining tables and functions.
local addonName, ns = ...

PerlInfinity = ns
ns.name = addonName
ns.modules = {}

-- Forever's interface numbers are 16xxx. This is the only version check in
-- the addon; everything else feature-detects.
local tocVersion = select(4, GetBuildInfo())
ns.supported = tocVersion >= 16000 and tocVersion < 20000 -- lint: allow L4

function ns:NewModule(name)
	local module = { name = name }
	self.modules[#self.modules + 1] = module
	self[name] = module
	return module
end

-- Prints a line in chat with the addon's name in front.
function ns.Print(message, ...)
	if select("#", ...) > 0 then
		message = message:format(...)
	end
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffPerl Infinity|r " .. message)
end

local function RunPhase(method)
	for _, module in ipairs(ns.modules) do
		if module[method] then
			ns.Call(module[method], module)
		end
	end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, loadedName)
	if event == "ADDON_LOADED" then
		if loadedName ~= addonName then
			return
		end
		self:UnregisterEvent("ADDON_LOADED")
		ns.version = C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"
		if not ns.supported then
			ns.Print(ns.L.MSG_UNSUPPORTED)
			return
		end
		RunPhase("Init")
	elseif event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		if ns.supported then
			-- How long setting up took, for the log (see Diag/SelfTest.lua).
			local started = debugprofilestop()
			RunPhase("Login")
			ns.loginMs = debugprofilestop() - started
		end
	end
end)
