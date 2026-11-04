-- tools/layout.lua
-- Boots an addon in the harness (open mode, a small party and a target) and writes a
-- layout dump per addon-created top-level frame to tools/out/layout/<name>.txt, for
-- golden snapshots and tools/preview.py.
--
-- usage: luajit tools/layout.lua [path/to/Addon.toc] [outDir]

local toc = arg[1] or "PerlInfinity/PerlInfinity.toc"
local outDir = arg[2] or "tools/out/layout"
local Harness = dofile("tests/harness/init.lua")

local h = Harness.new({ mode = "open" })
h:loadToc(toc)
h:login()
h.world:setParty({ { class = "PRIEST" }, { class = "WARRIOR", role = "TANK" } })
h.world:setTarget({ name = "Defias Thug", npc = true, reaction = 2, level = 18, health = 600, maxHealth = 900 })
h:advance(0.5)

os.execute('mkdir -p "' .. outDir .. '"')
local W = h.widgets
local n = 0
for _, obj in ipairs(W.all) do
  local st = W.state[obj]
  if st.kind == "frame" and st.parent == W.UIParent and not st.blizzard and st.name ~= "EditModeManagerFrame"
      and not st.harnessInternal and W.isVisible(obj) then
    local name = (st.name or ("frame" .. st.created)):gsub("[^%w_]", "_")
    local f = assert(io.open(outDir .. "/" .. name .. ".txt", "w"))
    f:write(W.layoutDump(obj), "\n")
    f:close()
    n = n + 1
  end
end
print(string.format("layout: %d dumps in %s (%d problems)", n, outDir, #h:problems()))
for _, p in ipairs(h:problems()) do print("  " .. p) end
