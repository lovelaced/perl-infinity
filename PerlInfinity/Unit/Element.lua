-- Elements are the pieces of a unit frame: health, power, name, auras, and so
-- on. Each one lives in its own file under Elements/ and declares:
--
--   unitEvents  events registered per unit with RegisterUnitEvent
--   events      other events this element wants (registered on the frame)
--   poll        true if it should refresh on Poller ticks for units like
--               "targettarget" that have no events of their own
--   Enabled(frame, conf)      is it on for this frame? (default: yes)
--   Create(frame)             build widgets once
--   Configure(frame, conf)    apply settings to the widgets
--   Update(frame, unit)       read the game and push values into widgets
--   Preview(frame, sample)    show sample values (options window previews)
--   Disable(frame)            hide widgets when turned off
--
-- The rules for Update, because unit values may be secret:
--   1. never compare, do math on, or use as a table key any value the API
--      docs mark as possibly secret
--   2. never branch on a possibly secret boolean; use Secret.ShowIf
--   3. never call SetShown with one either (it refuses secrets)
--   4. never measure text (GetStringWidth) on secret text
--   5. don't create tables or closures per update
local _, ns = ...

ns.Elements = {}

function ns.Element(name, definition)
	definition.name = name
	definition.unitEvents = definition.unitEvents or {}
	definition.events = definition.events or {}
	ns.Elements[name] = definition
	return definition
end
