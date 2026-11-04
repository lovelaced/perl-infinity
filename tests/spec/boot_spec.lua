-- tests/spec/boot_spec.lua
-- Boots the real addon (PerlInfinity/PerlInfinity.toc): load every file, fire ADDON_LOADED,
-- PLAYER_LOGIN and PLAYER_ENTERING_WORLD, and require zero errors, zero blocked or
-- forbidden actions, and clean SavedVariables. Skipped until the TOC exists.

local TOC = ROOT .. "/PerlInfinity/PerlInfinity.toc"

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

if not exists(TOC) then
  describe("PerlInfinity boot", function()
    pending("loads and logs in cleanly", "PerlInfinity/PerlInfinity.toc does not exist yet")
  end)
  return
end

local function boot(mode, sv)
  local h = Harness.new({ mode = mode })
  h:loadToc(TOC)
  h:login(sv)
  return h
end

describe("PerlInfinity boot", function()
  it("TOC declares the agreed SavedVariables and loads on Forever", function()
    local h = Harness.new({ mode = MODE })
    local addon = h:loadToc(TOC)
    expect(addon.loadsOnForever).toBe(true)
    expect(addon.savedVariables).toContain("PerlInfinityDB")
    expect(addon.savedVariables).toContain("PerlInfinityLog")
    expect(addon.savedVariablesPerCharacter).toContain("PerlInfinityCharDB")
    expect(addon.meta.Interface or "").toMatch("16001")
  end)

  it("logs in cleanly (" .. MODE .. " mode)", function()
    local h = boot(MODE)
    -- unknown templates are a hint that an XML template name is misspelled
    local unknown = {}
    for name in pairs(h.widgets.unknownTemplates) do unknown[#unknown + 1] = name end
    table.sort(unknown)
    if #unknown > 0 then io.write("    note: unknown templates: ", table.concat(unknown, ", "), "\n") end
  end)

  it("logs in cleanly in every mode", function()
    for _, mode in ipairs({ "open", "field", "strict" }) do boot(mode) end
  end)

  it("survives login in combat", function()
    local h = Harness.new({ mode = MODE })
    h:loadToc(TOC)
    h.world:combat(true)
    h:login()
    h.world:combat(false)
    h:advance(1)
  end)

  it("saves and reloads cleanly", function()
    local h = boot(MODE)
    local h2 = h:reload()
    h2:advance(1)
  end)

  it("handles a short solo fight", function()
    local h = boot(MODE)
    local w = h.world
    w:setTarget({ name = "Defias Thug", npc = true, reaction = 2, level = 18, health = 900, maxHealth = 900 })
    h:advance(0.5)
    w:combat(true)
    w:startCast("target", { name = "Shadow Bolt", duration = 2 })
    w:damage("target", 300)
    w:damage("player", 250)
    w:applyAura("target", { name = "Rend", isHarmful = true, duration = 15 })
    h:advance(2)
    w:stopCast("target")
    w:kill("target")
    w:combat(false)
    w:setTarget(nil)
    h:advance(1)
  end)
end)
