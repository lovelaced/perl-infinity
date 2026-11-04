-- tests/spec/perlinfinity_spec.lua
-- Perl Infinity's own scenarios: every frame kind through combat in a party and a
-- raid, every page and setting in the options window, Edit Mode, profiles,
-- settings changed mid-fight, and the "idle costs nothing" rule. Each test
-- fails on any Lua error, blocked or forbidden action, or secret that ends
-- up in SavedVariables (see tests/run.lua).

local TOC = ROOT .. "/PerlInfinity/PerlInfinity.toc"

local function boot(opts)
  local h = Harness.new(opts or {})
  h:loadToc(TOC)
  h:login()
  h:advance(0.5)
  return h, h.env.PerlInfinity
end

local function hostile(name)
  return { name = name or "Defias Thug", npc = true, reaction = 2, level = 18, health = 900, maxHealth = 900, classification = "elite" }
end

describe("Perl Infinity frames", function()
  it("creates every single frame and its mover", function()
    local _, F = boot()
    for _, kind in ipairs({ "player", "pet", "target", "focus", "targettarget", "focustarget", "pettarget" }) do
      expect(F.Frames:Get(kind)).toBeTruthy()
      expect(F.Movers:Get(kind)).toBeTruthy()
    end
  end)

  it("follows a target through a fight, casts, auras, threat and death", function()
    local h, F = boot()
    local w = h.world
    w:setTarget(hostile())
    h:advance(0.3)
    expect(F.Frames:Get("target"):IsShown()).toBe(true)
    w:combat(true)
    w:setThreat("player", "target", 3, 100)
    w:startCast("target", { name = "Fireball", duration = 2.5 })
    w:applyAura("target", { name = "Shadow Word: Pain", isHarmful = true, duration = 18, sourceUnit = "player" })
    w:applyAura("target", { name = "Power Word: Fortitude", duration = 1800, isStealable = true })
    w:setRaidTarget("target", 8)
    w:damage("target", 400)
    w:damage("player", 300)
    h:advance(1)
    w:stopCast("target", "interrupted")
    h:advance(1)
    w:kill("target")
    h:advance(0.5)
    w:combat(false)
    w:setTarget(nil)
    h:advance(1)
  end)

  it("shows target of target and focus target, which have no events", function()
    local h, F = boot()
    local w = h.world
    w:setTarget(hostile())
    w:setTarget("player", "target")
    w:setFocus(hostile("Kobold Geomancer"))
    h:advance(1)
    w:damage("player", 100)
    h:advance(0.5)
    expect(F.Poller:IsRunning()).toBe(true)
    w:setTarget(nil)
    w:setFocus(nil)
    h:advance(1)
  end)

  it("runs a party with targets and pets through combat", function()
    local h = boot()
    local w = h.world
    w:setParty({ { class = "WARRIOR" }, { class = "PRIEST" }, { class = "ROGUE" }, { class = "HUNTER" } })
    h:advance(0.5)
    w:summonPet({ name = "Cat" }, "party4")
    w:setTarget(hostile(), "party1")
    h:advance(0.5)
    w:combat(true)
    w:damage("party1", 1200)
    w:applyAura("party2", { name = "Corruption", isHarmful = true, dispelName = "Magic", duration = 12 })
    w:setRange("party3", false)
    w:setFlag("party3", "afk", true)
    w:kill("party4")
    h:advance(1.5)
    w:resurrect("party4", 500)
    w:combat(false)
    h:advance(1)
    w:leaveGroup()
    h:advance(1)
  end)

  it("runs a forty-player raid sorted by group, class and role", function()
    local h, F = boot()
    local w = h.world
    w:setRaid(40, function(i)
      return { role = (i % 10 == 0) and "TANK" or ((i % 4 == 0) and "HEALER" or "DAMAGER") }
    end)
    h:advance(0.5)
    for _, sort in ipairs({ "class", "role", "group" }) do
      F.Config:Set("raid.sortBy", sort)
      h:advance(0.3)
    end
    F.Config:Set("raid.icons", "buffs")
    F.Config:Set("raid.bossDebuff", true)
    w:combat(true)
    for i = 2, 40, 3 do
      w:damage("raid" .. i, 300)
    end
    h:advance(1)
    w:combat(false)
    h:advance(1)
  end)

  it("opens the tank and healer windows in a raid", function()
    local h, F = boot()
    F.Config:Set("tanks.enabled", true)
    F.Config:Set("healers.enabled", true)
    h.world:setRaid(25)
    h:advance(1)
    h.world:combat(true)
    h.world:damage("raid5", 500)
    h:advance(1)
    h.world:combat(false)
    h:advance(0.5)
  end)
end)

describe("Perl Infinity options window", function()
  it("opens every page and searches", function()
    local h, F = boot()
    F.Options:Open()
    for _, page in ipairs(F.OptionPages.list) do
      F.Options:ShowPage(page.key)
      h:advance(0.05)
    end
    F.Options:Toggle()
    h:advance(0.1)
  end)

  it("shows a tooltip for every row on every page", function()
    local h, F = boot()
    F.Options:Open()
    local list = h.env.PerlInfinityOptionsFrame.List
    local hovered = 0
    for _, page in ipairs(F.OptionPages.list) do
      F.Options:ShowPage(page.key)
      h:advance(0.02)
      for _, row in ipairs({ list:GetChildren() }) do
        local enter, leave = row:GetScript("OnEnter"), row:GetScript("OnLeave")
        if row.option and row:IsShown() and enter then
          enter(row)
          expect(h.env.GameTooltip:NumLines() > 0).toBe(true)
          leave(row)
          hovered = hovered + 1
        end
      end
    end
    expect(hovered > 50).toBe(true)
  end)

  it("changes every setting on every page without errors", function()
    local h, F = boot()
    h.world:setParty({ {}, {} })
    h.world:setTarget(hostile())
    F.Options:Open()
    for _, page in ipairs(F.OptionPages.list) do
      F.Options:ShowPage(page.key)
      for _, option in ipairs(page.rows) do
        if option.path and not option.get then
          local value = F.Config:Get(option.path)
          if option.type == "checkbox" then
            F.Config:Set(option.path, not value)
          elseif option.type == "slider" then
            F.Config:Set(option.path, option.max)
            F.Config:Set(option.path, option.min)
          elseif option.type == "dropdown" then
            local choices = type(option.choices) == "function" and option.choices() or option.choices
            for _, choice in ipairs(choices) do
              F.Config:Set(option.path, type(choice) == "table" and choice.value or choice)
              h:advance(0.02)
            end
          elseif option.type == "multi" then
            F.Config:Set(option.path, 0)
            F.Config:Set(option.path, value)
          elseif option.type == "color" then
            F.Config:Set(option.path, "ff336699")
          end
          h:advance(0.02)
        end
      end
    end
    h:advance(0.5)
    F.Config:Reset("")
    h:advance(0.5)
  end)

  it("opens at a comfortable size and remembers the preview being hidden", function()
    local h, F = boot()
    F.Options:Open()
    local window = h.env.PerlInfinityOptionsFrame
    expect(window:GetWidth()).toBe(1240)
    expect(window:GetHeight()).toBe(800)
    expect(window.Preview:IsShown()).toBe(true)
    local narrow = window.List:GetWidth()

    window.PreviewToggle:Click()
    expect(window.Preview:IsShown()).toBe(false)
    expect(window.List:GetWidth() > narrow).toBe(true)
    expect(h.env.PerlInfinityDB.global.optionsWindow.previewHidden).toBe(true)

    F.Options:Toggle()
    F.Options:Open()
    expect(window.Preview:IsShown()).toBe(false)
    window.PreviewToggle:Click()
    expect(window.Preview:IsShown()).toBe(true)
    expect(h.env.PerlInfinityDB.global.optionsWindow.previewHidden).toBeNil()
  end)

  it("gives every label room at any window size", function()
    local h, F = boot()
    local W = h.widgets
    F.Options:Open()
    local window = h.env.PerlInfinityOptionsFrame
    local function check()
      for _, page in ipairs(F.OptionPages.list) do
        F.Options:ShowPage(page.key)
        for _, row in ipairs({ window.List:GetChildren() }) do
          if row:IsShown() and row.Control then
            local textWidth = row.Text:GetWidth()
            expect(textWidth >= 200).toBe(true)
            -- Fits in the two lines a label may wrap to.
            expect(W.stringWidth(row.Text) <= textWidth * 2).toBe(true)
            -- The control starts after the label ends (both from the row's left).
            local _, _, _, labelX = row.Text:GetPoint(1)
            local _, _, _, controlX = row.Control:GetPoint(1)
            expect(controlX >= labelX + textWidth).toBe(true)
          end
        end
      end
    end
    check()
    -- Dragged as small as it goes, with and without the preview.
    window.Grip:DragTo(100, 100)
    expect(window:GetWidth() >= window.Grip.minWidth).toBe(true)
    check()
    window.PreviewToggle:Click()
    window.Grip:DragTo(100, 100)
    check()
    expect(h.env.PerlInfinityDB.global.optionsWindow.width).toBeTruthy()
  end)

  it("applies settings changed in combat once combat ends", function()
    local h, F = boot()
    h.world:combat(true)
    F.Config:Set("player.scale", 1.2)
    F.Config:Set("party.direction", "right")
    F.Config:Set("raid.sortBy", "class")
    h:advance(0.5)
    expect(F.Combat:HasPending()).toBe(true)
    h.world:combat(false)
    h:advance(0.5)
    expect(F.Combat:HasPending()).toBe(false)
  end)
end)

describe("Perl Infinity and the game's own frames", function()
  local function reloadLines(h)
    local n = 0
    for _, line in ipairs(h.chatLines) do
      if line:find("/reload", 1, true) then n = n + 1 end
    end
    return n
  end

  it("says in chat when a change needs a reload, once, naming what returns", function()
    local h, F = boot()
    expect(F.BlizzardHide:IsHidden("playerCast")).toBe(true)
    F.Config:Set("player.keepBlizzardCastBar", true)
    h:frame()
    expect(reloadLines(h)).toBe(1)
    expect(h.chatLines[#h.chatLines]).toMatch("cast bar")
    -- Unrelated changes don't repeat it.
    F.Config:Set("player.scale", 1.1)
    h:frame()
    expect(reloadLines(h)).toBe(1)
    -- Changing your mind back needs no reload and says nothing.
    F.Config:Set("player.keepBlizzardCastBar", false)
    h:frame()
    expect(reloadLines(h)).toBe(1)
  end)

  it("names everything coming back in one line", function()
    local h, F = boot()
    F.Config:Set("target.enabled", false)
    F.Config:Set("focus.enabled", false)
    h:frame()
    expect(reloadLines(h)).toBe(1)
    local line = h.chatLines[#h.chatLines]
    expect(line).toMatch("target frame")
    expect(line).toMatch("focus frame")
  end)

  it("hides the game's frame right away when a Perl Infinity frame is turned on", function()
    local h = Harness.new({})
    h:loadToc(TOC)
    h:login({ PerlInfinityDB = { profiles = { Default = { focus = { enabled = false } } } } })
    h:advance(0.5)
    local F = h.env.PerlInfinity
    expect(F.BlizzardHide:IsHidden("focus")).toBe(false)
    F.Config:Set("focus.enabled", true)
    h:frame()
    expect(F.BlizzardHide:IsHidden("focus")).toBe(true)
    expect(reloadLines(h)).toBe(0)
  end)
end)

describe("Perl Infinity Edit Mode", function()
  it("shows placeholders, follows layouts and saves positions per layout", function()
    local h, F = boot()
    h.lem:enter()
    h:advance(0.2)
    h.lem:move(F.Movers:Get("player"), "TOPLEFT", 40, -40)
    h.lem:switchLayout(h.lem.layoutNames and h.lem.layoutNames[2] or "Classic")
    h:advance(0.2)
    h.lem:exit()
    h:advance(0.2)
    expect(h.env.PerlInfinityDB.positions).toBeTruthy()
  end)
end)

describe("Perl Infinity Edit Mode snapping", function()
  local function snapper()
    local _, F = boot()
    return F.Snap.Find
  end
  local function rect(l, b, w, hgt) return { l = l, r = l + w, b = b, t = b + hgt } end
  local world = { width = 1000, height = 600, frames = {} }

  it("snaps to the screen's edges and center", function()
    local find = snapper()
    local dx, dy, lines = find(rect(5, 300, 100, 40), world, 8)
    expect(dx).toBe(-5)
    expect(dy).toBe(0)
    expect(lines[1].vertical).toBe(true)
    expect(lines[1].at).toBe(0)
    -- Centered within range on both axes snaps both ways at once.
    dx, dy, lines = find(rect(453, 284, 100, 40), world, 8)
    expect(dx).toBe(-3)
    expect(dy).toBe(-4)
    expect(#lines).toBe(2)
  end)

  it("leaves a frame alone when nothing is close", function()
    local find = snapper()
    local dx, dy, lines = find(rect(200, 200, 100, 40), world, 8)
    expect(dx).toBe(0)
    expect(dy).toBe(0)
    expect(#lines).toBe(0)
  end)

  it("snaps to grid lines while the grid shows", function()
    local find = snapper()
    local grid = { width = 1000, height = 600, gridX = { 250 }, gridY = { 150 }, frames = {} }
    local dx, dy = find(rect(246, 152, 100, 40), grid, 8)
    expect(dx).toBe(4)
    expect(dy).toBe(-2)
  end)

  it("snaps edge to edge with a frame beside it, lining up the corner", function()
    local find = snapper()
    local neighbor = rect(100, 200, 160, 60)
    local near = { width = 1000, height = 600, frames = { neighbor } }
    -- 5 to the right of it and 3 lower: lands flush, tops lined up.
    local dx, dy, lines = find(rect(265, 197, 120, 60), near, 8)
    expect(dx).toBe(-5)
    expect(dy).toBe(3)
    expect(#lines).toBe(2)
    -- Not level with it: no snap to that frame.
    dx = find(rect(265, 400, 120, 60), near, 8)
    expect(dx).toBe(0)
  end)

  it("snaps a dragged Perl Infinity frame and saves where it landed", function()
    local h, F = boot()
    h.lem:enter()
    local mover = F.Movers:Get("player")
    -- Dropped 4 from the screen's left edge, in a corner with nothing else.
    h.lem:drag(mover, "BOTTOMLEFT", 4, 40)
    local point, _, _, x, y = mover:GetPoint(1)
    expect(point).toBe("BOTTOMLEFT")
    expect(math.abs(x) < 0.01).toBe(true)
    expect(y).toBe(40)
    local saved = h.env.PerlInfinityDB.positions[next(h.env.PerlInfinityDB.positions)].player
    expect(math.abs(saved.x) < 0.01).toBe(true)
    -- With Snap off in Edit Mode, it stays where it was dropped.
    h.env.EditModeManagerFrame.snapEnabled = false
    h.lem:drag(mover, "BOTTOMLEFT", 4, 40)
    point, _, _, x = mover:GetPoint(1)
    expect(x).toBe(4)
    h.lem:exit()
  end)
end)

describe("Perl Infinity profiles", function()
  it("creates, exports, imports, copies and deletes profiles", function()
    local h, F = boot()
    local P = F.Profiles
    F.Config:Set("player.scale", 1.3)
    expect(P:Create("Raiding", P:Active())).toBe(true)
    expect(P:Use("Raiding")).toBe(true)
    expect(F.db.player.scale).toBe(1.3)
    local text = P:Export("Raiding", false)
    expect(text).toMatch("^PERLINFINITY1:")
    local payload = P:Decode(text)
    expect(payload).toBeTruthy()
    expect(P:Import("Shared", payload, false)).toBe(true)
    expect(P:Copy("Default", "Raiding")).toBe(true)
    expect(P:Delete("Shared")).toBe(true)
    expect(P:Decode("nonsense")).toBeNil()
    h:advance(0.5)
  end)
end)

describe("Perl Infinity CPU rules", function()
  it("does no periodic work when idle and alone", function()
    local h, F = boot()
    h:advance(2)
    expect(F.Scheduler:IsIdle()).toBe(true)
    expect(F.Poller:IsRunning()).toBe(false)
    expect(F.Elements.Range.IsTicking()).toBe(false)
  end)

  it("builds nothing for frames nobody can see at login", function()
    local h, F = boot()
    local containers, raidButtons = 0, 0
    for _, o in ipairs(h.widgets.all) do
      local st = h.widgets.state[o]
      if st.type == "AuraContainer" then containers = containers + 1 end
      if type(o) == "table" and o.kind == "raid" and not o.preview then raidButtons = raidButtons + 1 end
    end
    -- Solo: no aura buttons for hidden frames, no raid buttons at all.
    expect(containers).toBe(0)
    expect(raidButtons).toBe(0)
    expect(F.Frames:Get("focus").stale).toBe(true)
  end)

  it("spreads a raid's aura buttons over several frames", function()
    local h, F = boot()
    -- Real timings vary by machine; with no budget each frame builds one
    -- container, which shows the spreading without depending on speed.
    F.AuraHost.budget = 0
    h.world:setRaid(40)
    h:frame()
    expect(F.AuraHost.Waiting() > 0).toBe(true)
    h:advance(2)
    expect(F.AuraHost.Waiting()).toBe(0)
    local withAuras = 0
    for _, o in ipairs(h.widgets.all) do
      if type(o) == "table" and o.kind == "raid" and not o.preview and o:IsVisible() then
        expect(o.stale).toBe(false)
        if o.AuraContainers and o.AuraContainers.icons then withAuras = withAuras + 1 end
      end
    end
    expect(withAuras).toBe(40)
  end)

  it("rebuilds frames at most ten times a second while a slider moves", function()
    local h, F = boot()
    h.world:setRaid(40)
    h:advance(2)
    local rebuilds = 0
    local reconfigure = F.Frames.Reconfigure
    F.Frames.Reconfigure = function(self, kind, ...)
      if kind == "raid" then rebuilds = rebuilds + 1 end
      return reconfigure(self, kind, ...)
    end
    for width = 0, 40, 2 do
      F.Config:Set("raid.width", width)
      h:frame()
    end
    h:advance(0.3)
    -- 21 steps over 0.35 s: a handful of rebuilds, not 21, and the last
    -- value still lands.
    expect(rebuilds <= 6).toBe(true)
    expect(F.db.raid.width).toBe(40)
    F.Frames.Reconfigure = reconfigure
  end)

  it("touches one raid frame for one unit's health change", function()
    local h, F = boot()
    h.world:setRaid(40)
    h:advance(1)
    local flushes = F.Scheduler.stats.flushes
    h.world:damage("raid17", 100)
    h:advance(1 / 60)
    expect(F.Scheduler.stats.flushes - flushes).toBe(1)
  end)
end)

describe("Perl Infinity Edit Mode handles", function()
  -- Edges in screen units, so frames at different scales compare fairly.
  local function edges(frame)
    local l, b, width, height = frame:GetRect()
    local s = frame:GetEffectiveScale()
    return l * s, (l + width) * s, b * s, (b + height) * s
  end

  local function expectCovered(selection, frame, what)
    local sl, sr, sb, st = edges(selection)
    local l, r, b, t = edges(frame)
    local inside = l >= sl - 0.01 and r <= sr + 0.01 and b >= sb - 0.01 and t <= st + 0.01
    if not inside then
      error(("%s sits outside the handle: frame %.1f..%.1f x %.1f..%.1f, handle %.1f..%.1f x %.1f..%.1f"):format(what, l, r, b, t, sl, sr, sb, st))
    end
  end

  local function shownSubFrames(h)
    local list = {}
    for _, child in ipairs(h.env.PerlInfinity_PartyHeader.children) do
      for _, sub in ipairs(child.subFrames or {}) do
        if sub:IsVisible() then list[#list + 1] = sub end
      end
    end
    return list
  end

  local function partyWithPetAndTarget()
    local h, F = boot()
    local w = h.world
    w:setParty({ { class = "WARRIOR" }, { class = "HUNTER" } })
    h:advance(0.5)
    w:summonPet({ name = "Cat" }, "party2")
    w:setTarget(hostile(), "party1")
    h:advance(0.5)
    return h, F, w
  end

  it("lets you grab a party member's pet and target", function()
    local h, F = partyWithPetAndTarget()
    h.lem:enter()
    h:advance(0.2)
    local selection = h.lem.frameSelections[F.Movers:Get("party")]
    local subs = shownSubFrames(h)
    expect(#subs >= 2).toBeTruthy()
    for _, sub in ipairs(subs) do
      expectCovered(selection, sub, "party " .. tostring(sub.kind))
    end
  end)

  it("puts a party member's pet and target beside the frame at any scale", function()
    for _, mirror in ipairs({ false, true }) do
      for _, scale in ipairs({ 0.8, 1.2 }) do
        local h, F = boot()
        F.db.party.mirror, F.db.party.scale = mirror, scale
        F.Frames:Reconfigure("party")
        h:advance(0.5)
        local w = h.world
        w:setParty({ { class = "HUNTER" } })
        h:advance(0.5)
        w:summonPet({ name = "Cat" }, "party1")
        w:setTarget(hostile(), "party1")
        h:advance(0.5)
        local member = h.env.PerlInfinity_PartyHeader.children[1]
        local _, right, _, top = edges(member)
        for _, sub in ipairs({ member.PartyTarget, member.PartyPet }) do
          expect(sub:IsVisible()).toBeTruthy()
          local l = edges(sub)
          expect(math.abs(l - (right - 2 * member:GetEffectiveScale())) < 0.01).toBeTruthy()
        end
        local _, _, _, petTop = edges(member.PartyPet)
        expect(petTop < top).toBeTruthy()
      end
    end
  end)

  it("grows the handle when a pet appears, and doesn't shrink it when one leaves", function()
    local h, F, w = partyWithPetAndTarget()
    h.lem:enter()
    h:advance(0.2)
    local selection = h.lem.frameSelections[F.Movers:Get("party")]
    local _, rightBefore = edges(selection)
    w:summonPet({ name = "Wolf" }, "party1")
    h:advance(0.2)
    for _, sub in ipairs(shownSubFrames(h)) do
      expectCovered(selection, sub, "party " .. tostring(sub.kind))
    end
    local _, rightDuring = edges(selection)
    expect(rightDuring >= rightBefore).toBeTruthy()
    w:setTarget(nil, "party1")
    h:advance(0.2)
    local _, rightAfter = edges(selection)
    expect(rightAfter).toBe(rightDuring)
  end)

  it("keeps the handle on the party frame's position when dropped", function()
    local h, F = partyWithPetAndTarget()
    h.lem:enter()
    h:advance(0.2)
    local mover = F.Movers:Get("party")
    h.env.EditModeManagerFrame.snapEnabled = false
    h.lem:drag(mover, "TOPLEFT", 300, -300)
    local point, _, _, x, y = mover:GetPoint(1)
    expect(point).toBe("TOPLEFT")
    expect(x).toBe(300)
    expect(y).toBe(-300)
  end)

  it("doesn't draw samples over a real party", function()
    local h, F = partyWithPetAndTarget()
    local mover = F.Movers:Get("party")
    h.lem:enter()
    h:advance(0.2)
    local shownSamples = 0
    for _, child in ipairs({ mover:GetChildren() }) do
      if child.preview and child:IsShown() then shownSamples = shownSamples + 1 end
    end
    expect(shownSamples).toBe(0)
  end)

  it("keeps party samples inside the handle whichever way the party grows", function()
    for _, direction in ipairs({ "down", "up", "right", "left" }) do
      local h, F = boot()
      F.db.party.direction = direction
      F.Frames:Reconfigure("party")
      h:advance(0.5)
      h.lem:enter()
      h:advance(0.2)
      local mover = F.Movers:Get("party")
      local selection = h.lem.frameSelections[mover]
      local samples = 0
      for _, child in ipairs({ mover:GetChildren() }) do
        if child.preview and child:IsShown() then
          samples = samples + 1
          expectCovered(selection, child, "sample growing " .. direction)
        end
      end
      expect(samples).toBe(4)
    end
  end)
end)
