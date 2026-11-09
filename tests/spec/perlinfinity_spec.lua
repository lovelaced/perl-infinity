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
    -- Your own frame is on screen, and its debuff highlight needs a container.
    local own = F.Frames:Get("player").AuraContainers.icons
    local containers, raidButtons = 0, 0
    for _, o in ipairs(h.widgets.all) do
      local st = h.widgets.state[o]
      if st.type == "AuraContainer" and o ~= own then containers = containers + 1 end
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

  it("gives party targets and pets their own Edit Mode boxes", function()
    local h, F = partyWithPetAndTarget()
    h.lem:enter()
    h:advance(0.2)
    local party = h.env.PerlInfinity_PartyHeader
    for _, member in ipairs(party.children) do
      if member.PartyTarget:IsVisible() then
        expectCovered(h.lem.frameSelections[F.Movers:Get("partytarget")], member.PartyTarget, "party target")
      end
      if member.PartyPet:IsVisible() then
        expectCovered(h.lem.frameSelections[F.Movers:Get("partypet")], member.PartyPet, "party pet")
      end
    end
    expect(#shownSubFrames(h) >= 2).toBeTruthy()
  end)

  it("moves party pets without moving the party or their targets", function()
    local h, F = partyWithPetAndTarget()
    h.env.EditModeManagerFrame.snapEnabled = false
    h.lem:enter()
    h:advance(0.2)
    local party = h.env.PerlInfinity_PartyHeader
    local member = party.children[2]
    local memberLeft, _, _, memberTop = edges(member)
    local targetLeft, _, _, targetTop = edges(party.children[1].PartyTarget)

    h.lem:drag(F.Movers:Get("partypet"), "TOPLEFT", 700, -300)
    h:advance(0.2)

    local left, _, _, top = edges(member.PartyPet)
    local scale = F.Movers:Get("partypet"):GetEffectiveScale()
    local pitch = member.rects.height + (-party:GetAttribute("yOffset"))
    local below = pitch * F.Movers:Get("party"):GetEffectiveScale()
    expect(math.abs(left - 700 * scale) < 0.01).toBeTruthy()
    expect(math.abs(top - (h.env.UIParent:GetHeight() * h.env.UIParent:GetEffectiveScale() - 300 * scale - below)) < 0.01).toBeTruthy()

    local nowLeft, _, _, nowTop = edges(member)
    expect(nowLeft).toBe(memberLeft)
    expect(nowTop).toBe(memberTop)
    local tLeft, _, _, tTop = edges(party.children[1].PartyTarget)
    expect(tLeft).toBe(targetLeft)
    expect(tTop).toBe(targetTop)
  end)

  it("leaves a moved column where you put it when the party moves", function()
    local h, F = partyWithPetAndTarget()
    h.env.EditModeManagerFrame.snapEnabled = false
    h.lem:enter()
    h:advance(0.2)
    local party = h.env.PerlInfinity_PartyHeader
    local pet = party.children[2].PartyPet
    local target = party.children[1].PartyTarget
    h.lem:drag(F.Movers:Get("partypet"), "TOPLEFT", 700, -300)
    h:advance(0.2)
    local petLeft = edges(pet)
    local targetLeft = edges(target)

    h.lem:drag(F.Movers:Get("party"), "TOPLEFT", 100, -100)
    h:advance(0.2)

    -- The pets were moved, so they stay. The targets weren't, so they follow.
    expect(edges(pet)).toBe(petLeft)
    expect(edges(target) ~= targetLeft).toBeTruthy()
    local _, right = edges(party.children[1])
    expect(math.abs(edges(target) - (right - 2 * party.children[1]:GetEffectiveScale())) < 0.01).toBeTruthy()
  end)

  it("puts a moved column back beside the party with Reset position", function()
    local h, F = partyWithPetAndTarget()
    h.env.EditModeManagerFrame.snapEnabled = false
    h.lem:enter()
    h:advance(0.2)
    local party = h.env.PerlInfinity_PartyHeader
    local member = party.children[2]
    local before = edges(member.PartyPet)
    local mover = F.Movers:Get("partypet")
    h.lem:drag(mover, "TOPLEFT", 700, -300)
    h:advance(0.2)
    expect(edges(member.PartyPet) ~= before).toBeTruthy()

    h.lem:resetPosition(mover)
    h:advance(0.2)
    expect(math.abs(edges(member.PartyPet) - before) < 0.01).toBeTruthy()
    local layout = F.db and h.env.PerlInfinityDB.positions
    for _, saved in pairs(layout or {}) do
      expect(saved.partypet).toBeNil()
    end
  end)

  it("remembers a moved column across a reload", function()
    local h, F = partyWithPetAndTarget()
    h.env.EditModeManagerFrame.snapEnabled = false
    h.lem:enter()
    h:advance(0.2)
    h.lem:drag(F.Movers:Get("partytarget"), "TOPLEFT", 650, -250)
    h:advance(0.2)
    h.lem:exit()
    h:advance(0.2)
    h = h:reload()
    h:advance(0.5)
    local mover = h.env.PerlInfinity.Movers:Get("partytarget")
    local point, relative, _, x, y = mover:GetPoint(1)
    expect(point).toBe("TOPLEFT")
    expect(relative).toBe(h.env.UIParent)
    expect(x).toBe(650)
    expect(y).toBe(-250)
  end)

  it("hides a column's box when that kind of frame is off", function()
    local h, F = boot()
    h.world:setParty({ { class = "HUNTER" } })
    h:advance(0.5)
    expect(F.Movers:Get("partypet"):IsShown()).toBe(true)
    F.Config:Set("party.pets", false)
    h:advance(0.5)
    expect(F.Movers:Get("partypet"):IsShown()).toBe(false)
    expect(F.Movers:Get("partytarget"):IsShown()).toBe(true)
    F.Config:Set("party.pets", true)
    h:advance(0.5)
    expect(F.Movers:Get("partypet"):IsShown()).toBe(true)
  end)

  it("applies the party size slider right away", function()
    local h, F = boot()
    F.Config:Set("party.scale", 1.1)
    h:advance(0.5)
    expect(F.Movers:Get("party"):GetScale()).toBe(1.1)
    expect(math.abs(F.Movers:Get("partytarget"):GetScale() - 1.1 * 0.9) < 0.001).toBeTruthy()
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

  it("keeps samples of party targets and pets inside their boxes whichever way the party grows", function()
    for _, direction in ipairs({ "down", "up", "right", "left" }) do
      local h, F = boot()
      F.db.party.direction = direction
      F.Frames:Reconfigure("party")
      h:advance(0.5)
      h.lem:enter()
      h:advance(0.2)
      for _, key in ipairs({ "partytarget", "partypet" }) do
        local mover = F.Movers:Get(key)
        local selection = h.lem.frameSelections[mover]
        local samples = 0
        for _, child in ipairs({ mover:GetChildren() }) do
          if child.preview and child:IsShown() then
            samples = samples + 1
            expectCovered(selection, child, key .. " sample growing " .. direction)
          end
        end
        expect(samples).toBe(4)
      end
    end
  end)

  it("lines up with each member whichever way the party grows", function()
    for _, direction in ipairs({ "down", "up", "right", "left" }) do
      local h, F = boot()
      F.db.party.direction = direction
      F.Frames:Reconfigure("party")
      h:advance(0.5)
      local w = h.world
      w:setParty({ { class = "WARRIOR" }, { class = "HUNTER" } })
      h:advance(0.5)
      for i, unit in ipairs({ "party1", "party2" }) do
        w:summonPet({ name = "Cat" .. i }, unit)
      end
      h:advance(0.5)
      for _, member in ipairs(h.env.PerlInfinity_PartyHeader.children) do
        if member.PartyPet:IsVisible() then
          local _, right, _, top = edges(member)
          local scale = member:GetEffectiveScale()
          local left, _, _, petTop = edges(member.PartyPet)
          expect(math.abs(left - (right - 2 * scale)) < 0.01).toBeTruthy()
          expect(math.abs(petTop - (top + member.rects.statsBox.y * scale)) < 0.01).toBeTruthy()
        end
      end
    end
  end)
end)

describe("Perl Infinity taint watch", function()
  -- The harness treats everything as tainted, so these say exactly what is.
  local function bootTainted(tainted)
    local h = Harness.new({})
    h.env.issecurevariable = function(a, b)
      local name = b or a
      if tainted[name] then return false, "PerlInfinity" end
      return true
    end
    h:loadToc(TOC)
    h:login()
    h:advance(0.5)
    return h
  end

  local function currentRun(h)
    local watch = h.env.PerlInfinityLog.taintWatch
    return watch.runs[#watch.runs]
  end

  it("does nothing until you turn it on", function()
    local h = bootTainted({ PET_ACTION_HIGHLIGHT_MARKS = true })
    h:advance(3)
    expect(h.env.PerlInfinityLog.taintWatch).toBeNil()
  end)

  it("records a tainted global and what was going on", function()
    local tainted = {}
    local h = bootTainted(tainted)
    h.env.PET_ACTION_HIGHLIGHT_MARKS = {}
    h.env.SlashCmdList.PERLINFINITY("taintwatch")
    h:advance(1)
    expect(next(currentRun(h).findings)).toBeNil()
    tainted.PET_ACTION_HIGHLIGHT_MARKS = true
    h:advance(1)
    local found = currentRun(h).findings.PET_ACTION_HIGHLIGHT_MARKS
    expect(found).toBeTruthy()
    expect(found.by).toBe("PerlInfinity")
    expect(found.group).toBe("solo")
  end)

  it("finds a stray global anywhere in _G, but not the ones we make on purpose", function()
    local tainted = { PerlInfinityOptionsFrame = true, SLASH_PERLINFINITY1 = true }
    local h = bootTainted(tainted)
    h.env.SomeStrayGlobal = 1
    tainted.SomeStrayGlobal = true
    h.env.SlashCmdList.PERLINFINITY("taintwatch")
    h:advance(5)
    local findings = currentRun(h).findings
    expect(findings.SomeStrayGlobal).toBeTruthy()
    expect(findings.PerlInfinityOptionsFrame).toBeNil()
    expect(findings.SLASH_PERLINFINITY1).toBeNil()
  end)

  it("catches the stack of a tainted write as it happens", function()
    local tainted = {}
    local h = bootTainted(tainted)
    h.env.PET_ACTION_HIGHLIGHT_MARKS = {}
    h.env.PetActionBar = { ClearPetActionHighlightMarks = function() end }
    h.env.SlashCmdList.PERLINFINITY("taintwatch")
    h:advance(0.5)
    tainted.PET_ACTION_HIGHLIGHT_MARKS = true
    h.env.PetActionBar:ClearPetActionHighlightMarks()
    local found = currentRun(h).findings.PET_ACTION_HIGHLIGHT_MARKS
    expect(found).toBeTruthy()
    expect(type(found.stack)).toBe("string")
    expect(#found.stack > 0).toBe(true)
  end)

  it("reports tainted fields on Blizzard frames, skipping our own markers", function()
    local tainted = {}
    local h = bootTainted(tainted)
    h.env.StanceBar = { isShownExternal = true, perlInfinityBlocked = true }
    tainted.isShownExternal = true
    tainted.perlInfinityBlocked = true
    h.env.SlashCmdList.PERLINFINITY("taintwatch")
    h:advance(5)
    local findings = currentRun(h).findings
    expect(findings["StanceBar.isShownExternal"]).toBeTruthy()
    expect(findings["StanceBar.perlInfinityBlocked"]).toBeNil()
  end)

  it("stays on through a reload and stops when you turn it off", function()
    local tainted = {}
    local h = bootTainted(tainted)
    h.env.SlashCmdList.PERLINFINITY("taintwatch")
    expect(h.env.PerlInfinityLog.taintWatch.on).toBe(true)
    h.env.SlashCmdList.PERLINFINITY("taintwatch")
    expect(h.env.PerlInfinityLog.taintWatch.on).toBeNil()
    h.env.LateGlobal = 1
    tainted.LateGlobal = true
    h:advance(5)
    expect(currentRun(h).findings.LateGlobal).toBeNil()
  end)
end)

describe("Perl Infinity screen edge warnings", function()
  local function controlGlow(h)
    for _, obj in ipairs(h.widgets.all) do
      if obj.GetTexture and obj:GetTexture() == "Interface\\FullScreenTextures\\OutOfControl" then
        return obj:GetParent()
      end
    end
  end

  it("glows while you've lost control of your character", function()
    local h = boot()
    local glow = controlGlow(h)
    expect(glow:GetAlpha()).toBe(0)
    h:fire("PLAYER_CONTROL_LOST")
    expect(glow:GetAlpha()).toBe(1)
    h:fire("PLAYER_CONTROL_GAINED")
    expect(glow:GetAlpha()).toBe(0)
  end)

  it("stays off on a flight path", function()
    local h = boot()
    local glow = controlGlow(h)
    h.world:get("player").onTaxi = true
    h:fire("PLAYER_CONTROL_LOST")
    expect(glow:GetAlpha()).toBe(0)
    h:advance(2)
    expect(glow:GetAlpha()).toBe(0)
    h.world:get("player").onTaxi = false
    h:fire("PLAYER_CONTROL_GAINED")
    expect(glow:GetAlpha()).toBe(0)
  end)

  it("turns off if the game reports the flight after the event", function()
    local h = boot()
    local glow = controlGlow(h)
    h:fire("PLAYER_CONTROL_LOST")
    expect(glow:GetAlpha()).toBe(1)
    h.world:get("player").onTaxi = true
    h:advance(1)
    expect(glow:GetAlpha()).toBe(0)
  end)
end)

describe("Perl Infinity names", function()
  local function partyFrame(h, unit)
    for _, obj in ipairs(h.widgets.all) do
      if obj.kind == "party" and obj.unit == unit then return obj end
    end
  end

  local function shownName(frame)
    return Harness.Secret.raw(frame.NameText:GetText())
  end

  local function joined(h, first, last)
    return first .. h.env.Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR .. last
  end

  it("shows a player's first name and surname", function()
    local h, F = boot()
    h.world:setParty({ { name = "Elwyn", surname = "Ashford" } })
    h:advance(0.5)
    expect(shownName(partyFrame(h, "party1"))).toBe(joined(h, "Elwyn", "Ashford"))
    h.world:setTarget({ name = "Tamsin", surname = "Holloway", isPlayer = true, class = "MAGE" })
    h:advance(0.5)
    expect(shownName(F.Frames:Get("target"))).toBe(joined(h, "Tamsin", "Holloway"))
  end)

  it("shows one name for anyone without a surname", function()
    local h, F = boot()
    h.world:setParty({ { name = "Elwyn" }, { name = "Ow", surname = "" } })
    h.world:setTarget(hostile("Defias Thug"))
    h:advance(0.5)
    expect(shownName(partyFrame(h, "party1"))).toBe("Elwyn")
    expect(shownName(F.Frames:Get("target"))).toBe("Defias Thug")
    -- Strict mode makes the empty surname secret, which can't be told apart.
    -- The game's own code treats any surname it returns as a real one.
    if h.mode ~= "strict" then
      expect(shownName(partyFrame(h, "party2"))).toBe("Ow")
    end
  end)

  it("still shows names the game has made secret", function()
    local h, F = boot()
    h.world:setTarget({ name = "Elwyn", surname = "Ashford", isPlayer = true, class = "MAGE" })
    h.env.UnitName = function()
      return Harness.Secret.wrap("Elwyn"), Harness.Secret.wrap("Ashford")
    end
    F.Frames:Get("target"):UpdateAll()
    h:advance(0.5)
    expect(shownName(F.Frames:Get("target"))).toBe(joined(h, "Elwyn", "Ashford"))
  end)
end)

describe("Perl Infinity aura frame record", function()
  it("saves what each party frame's icons were doing at logout", function()
    local h = boot()
    h.world:setParty({ { class = "WARRIOR" } })
    h:advance(0.5)
    h.world:applyAura("party1", { name = "Fort", duration = 1800 })
    h:advance(0.5)
    h:saveVariables()
    local sessions = h.env.PerlInfinityLog.sessions
    local record = sessions[#sessions].auraFrames
    expect(record).toBeTruthy()
    expect(record.frames[1].unit).toBe("party1")
    expect(record.frames[1].kind).toBe("party")
    expect(record.frames[1].containerUnit).toBe("party1")
    -- Strict mode keeps auras secret all the time, and the record says so.
    if h.mode ~= "strict" then
      expect(record.frames[1].gameHasBuff).toBe("plain:table")
    end
  end)

  it("saves nothing when you're not in a group", function()
    local h = boot()
    h:saveVariables()
    local sessions = h.env.PerlInfinityLog.sessions
    expect(sessions[#sessions].auraFrames).toBeNil()
  end)
end)

describe("Perl Infinity aura icons", function()
  local function partyFrame(h, unit)
    for _, obj in ipairs(h.widgets.all) do
      if obj.kind == "party" and obj.unit == unit then return obj end
    end
  end

  -- The game places aura buttons but never sizes them: a layout's elementWidth
  -- only sets how much room a button takes up, so an unsized button draws nothing.
  local function expectSized(container, key, size)
    local count = container:GetAuraGroupFrameCount(key)
    expect(count > 0).toBe(true)
    for i = 1, count do
      local width, height = container:GetAuraGroupFrame(key, i):GetSize()
      expect(Harness.Secret.raw(width)).toBe(size)
      expect(Harness.Secret.raw(height)).toBe(size)
    end
  end

  it("gives party icons a size you can see", function()
    local h, F = boot()
    h.world:setParty({ { class = "PRIEST" } })
    h:advance(0.5)
    local container = partyFrame(h, "party1").AuraContainers.icons
    local auras = F.db.party.auras
    expectSized(container, "buffs", auras.buffSize)
    expectSized(container, "debuffs", auras.debuffSize)
  end)

  it("gives target icons a size you can see", function()
    local h, F = boot()
    h.world:setTarget(hostile())
    h:advance(0.5)
    local container = F.Frames:Get("target").AuraContainers.icons
    expectSized(container, "buffs", F.db.target.auras.buffSize)
    expectSized(container, "debuffs", F.db.target.auras.debuffSize)
  end)

  it("resizes icons when you change the setting", function()
    local h, F = boot()
    h.world:setParty({ { class = "PRIEST" } })
    h:advance(0.5)
    local frame = partyFrame(h, "party1")
    F.db.party.auras.buffSize = 30
    frame:Configure()
    h:advance(0.5)
    -- Strict mode keeps auras secret, so resizing waits, but the size is remembered.
    if h.mode ~= "strict" then
      expectSized(frame.AuraContainers.icons, "buffs", 30)
    end
  end)

  -- How the game sorts an aura into a group: the filter string, then any
  -- candidate filters. "PLAYER" means yours, whatever isFromPlayerOrPlayerPet says.
  local function belongs(aura, group)
    local wants = {}
    for token in group.filter:gmatch("[^|]+") do
      if token:sub(1, 1) == "!" then wants[token:sub(2)] = false else wants[token] = true end
    end
    if (wants.HARMFUL and not aura.harmful) or (wants.HELPFUL and aura.harmful) then return false end
    if wants.PLAYER ~= nil and aura.mine ~= wants.PLAYER then return false end
    local candidates = group.candidates or {}
    for field, value in pairs(candidates) do
      if aura[field] ~= value then return false end
    end
    return true
  end

  it("puts every aura in exactly one group, even when the game's flags disagree", function()
    local F = select(2, boot())
    local auras = {}
    for _, harmful in ipairs({ false, true }) do
      for _, mine in ipairs({ true, false }) do
        for _, fromAPlayer in ipairs({ true, false }) do
          for _, stealable in ipairs({ true, false }) do
            auras[#auras + 1] = { harmful = harmful, mine = mine, isFromPlayerOrPlayerPet = fromAPlayer, isStealable = stealable }
          end
        end
      end
    end
    for _, hostile in ipairs({ true, false }) do
      for _, bigOwn in ipairs({ true, false }) do
        for _, markStealable in ipairs({ true, false }) do
          local groups = F.AuraHost.Groups(F.db.target.auras, { bigOwn = bigOwn, markStealable = markStealable }, hostile)
          for _, aura in ipairs(auras) do
            local count = 0
            for _, group in ipairs(groups) do
              if belongs(aura, group) then count = count + 1 end
            end
            expect(count).toBe(1)
          end
        end
      end
    end
  end)

  it("never shows the game's made-up Edit Mode auras on real frames", function()
    local h, F = boot()
    h.world:setParty({ { class = "PRIEST" } })
    h.world:setTarget(hostile())
    h:advance(0.5)
    expect(partyFrame(h, "party1").AuraContainers.icons:IsEditModePreviewEnabled()).toBe(false)
    expect(F.Frames:Get("target").AuraContainers.icons:IsEditModePreviewEnabled()).toBe(false)
  end)

  it("leaves room between party members for every icon they could show", function()
    local h, F = boot()
    h.world:setParty({ { class = "PRIEST" }, { class = "MAGE" } })
    h:advance(0.5)
    local header = h.env.PerlInfinity_PartyHeader
    local member = partyFrame(h, "party1")
    local auras = F.db.party.auras
    local lineWidth = member.rects.width - member.rects.statsBox.x

    -- Lay out the fullest rows by hand: big buffs, small buffs, then debuffs.
    local big = math.floor(auras.buffSize * 1.4 + 0.5)
    local bigCount = math.floor(lineWidth / (big + 2)) * auras.rows
    local smallCount = math.floor(lineWidth / (auras.buffSize + 2)) * auras.rows
    local debuffCount = math.floor(lineWidth / (auras.debuffSize + 2)) * auras.rows
    expect(bigCount).toBe(4)
    expect(smallCount).toBe(5)
    expect(debuffCount).toBe(4)
    -- One row of each, plus a little room above and below.
    local needed = big + 2 + auras.buffSize + 2 + auras.debuffSize + 4
    expect(-header:GetAttribute("yOffset")).toBe(needed)
  end)

  it("uses the exact spacing when you turn off making room, or when members sit side by side", function()
    local h, F = boot()
    local header
    F.Config:Set("party.fitIcons", false)
    h:advance(0.5)
    header = h.env.PerlInfinity_PartyHeader
    expect(-header:GetAttribute("yOffset")).toBe(F.db.party.spacing)

    F.Config:Set("party.fitIcons", true)
    F.Config:Set("party.direction", "right")
    h:advance(0.5)
    expect(header:GetAttribute("xOffset")).toBe(F.db.party.spacing)
  end)

  it("uses your spacing when it's bigger than the icons need", function()
    local h, F = boot()
    F.Config:Set("party.spacing", 60)
    F.Config:Set("party.auras.buffs", false)
    F.Config:Set("party.auras.debuffs", false)
    h:advance(0.5)
    expect(-h.env.PerlInfinity_PartyHeader:GetAttribute("yOffset")).toBe(60)
  end)

  it("gives heal over time bars a size you can see", function()
    local h, F = boot()
    F.db.highlight.hotBars = true
    h.world:setParty({ { class = "PRIEST" } })
    h:advance(0.5)
    local bars = partyFrame(h, "party1").AuraContainers.hotBars
    local _, height = bars:GetAuraGroupFrame("hotBars", 1):GetSize()
    expect(Harness.Secret.raw(height)).toBe(2)
  end)
end)

describe("Perl Infinity weapon enchants", function()
  local function enchantFrames(h, F)
    local container = F.Frames:Get("player").AuraContainers
    container = container and container.icons
    local frames = {}
    if container then
      for _, name in ipairs({ "MainHand", "OffHand", "Ranged" }) do
        frames[name] = container:GetItemEnchantmentFrame(h.env.AuraContainerItemEnchantmentSlot[name])
      end
    end
    return frames, container
  end

  it("stays off until you turn it on", function()
    local h, F = boot()
    h:advance(0.5)
    expect(F.db.player.auras.weaponEnchants).toBe(false)
    local frames = enchantFrames(h, F)
    expect(next(frames)).toBeNil()
  end)

  it("shows each hand on your frame, sized, and right-click cancels", function()
    local h, F = boot()
    F.Config:Set("player.auras.weaponEnchants", true)
    h:advance(0.5)
    local frames, container = enchantFrames(h, F)
    for _, name in ipairs({ "MainHand", "OffHand", "Ranged" }) do
      local button = frames[name]
      expect(button).toBeTruthy()
      expect(button.testCancelButtons).toBe("RightButtonUp")
      local slot = h.env.AuraContainerItemEnchantmentSlot[name]
      expect(container:IsItemEnchantmentEnabled(slot)).toBe(true)
      local width = button:GetSize()
      expect(Harness.Secret.raw(width)).toBe(31)
    end
  end)

  it("works with the buff and debuff switches off, and turns off again", function()
    local h, F = boot()
    F.Config:Set("player.auras.weaponEnchants", true)
    h:advance(0.5)
    local _, container = enchantFrames(h, F)
    expect(container).toBeTruthy()
    F.Config:Set("player.auras.weaponEnchants", false)
    h:advance(0.5)
    for _, name in ipairs({ "MainHand", "OffHand", "Ranged" }) do
      expect(container:IsItemEnchantmentEnabled(h.env.AuraContainerItemEnchantmentSlot[name])).toBe(false)
    end
  end)

  it("waits until combat ends to add them", function()
    local h, F = boot()
    F.Config:Set("player.auras.buffs", true)
    h:advance(0.5)
    h.world:combat(true)
    h:advance(0.1)
    F.Config:Set("player.auras.weaponEnchants", true)
    h:advance(0.5)
    local frames = enchantFrames(h, F)
    expect(frames.MainHand).toBeNil()
    h.world:combat(false)
    h:advance(0.5)
    frames = enchantFrames(h, F)
    expect(frames.MainHand).toBeTruthy()
  end)

  it("only offers them on your own frame", function()
    local h, F = boot()
    h.world:setTarget(hostile())
    h:advance(0.5)
    local target = F.Frames:Get("target")
    expect(target.AuraContainers.icons.enchantSlots).toBeNil()
  end)

  it("draws a sample in the options preview", function()
    local h, F = boot()
    F.Config:Set("player.auras.weaponEnchants", true)
    h:advance(0.5)
    local preview = F.Frames:CreatePreview("player", h.env.UIParent)
    local shown = 0
    for _, icon in ipairs(preview.PreviewAuras or {}) do
      if icon:IsShown() then shown = shown + 1 end
    end
    expect(shown).toBe(1)
  end)
end)

describe("Perl Infinity and your own buffs and debuffs", function()
  local function reloadLine(h)
    for i = #h.chatLines, 1, -1 do
      if h.chatLines[i]:find("/reload", 1, true) then return h.chatLines[i] end
    end
  end

  local function iconCount(container, key)
    return container and container.groups[key] and container:GetAuraGroupFrameCount(key) or 0
  end

  it("leaves the game's displays alone and adds no icons by default", function()
    local h, F = boot()
    for _, name in ipairs({ "BuffFrame", "DebuffFrame" }) do
      local display = h.env[name]
      expect(display:IsRolesetFiltered()).toBe(false)
      expect(display:IsEventRegistered("UNIT_AURA")).toBe(true)
      expect(display.perlInfinityBlocked).toBe(nil)
    end
    expect(F.BlizzardHide:IsHidden("buffs")).toBe(false)
    expect(F.BlizzardHide:IsHidden("debuffs")).toBe(false)
    -- The container is there for the debuff highlight, with no icon groups.
    local container = F.Frames:Get("player").AuraContainers.icons
    expect(next(container.groups)).toBeNil()
  end)

  it("lets you choose either, both or neither for each of the four displays", function()
    for _, keepBuffs in ipairs({ true, false }) do
      for _, keepDebuffs in ipairs({ true, false }) do
        for _, showBuffs in ipairs({ true, false }) do
          for _, showDebuffs in ipairs({ true, false }) do
            local h, F = boot()
            F.Config:Set("player.keepBlizzardBuffs", keepBuffs)
            F.Config:Set("player.keepBlizzardDebuffs", keepDebuffs)
            F.Config:Set("player.auras.buffs", showBuffs)
            F.Config:Set("player.auras.debuffs", showDebuffs)
            h:advance(0.5)
            expect(h.env.BuffFrame:IsRolesetFiltered()).toBe(not keepBuffs)
            expect(h.env.DebuffFrame:IsRolesetFiltered()).toBe(not keepDebuffs)
            local container = F.Frames:Get("player").AuraContainers
            container = container and container.icons
            local buffCount = iconCount(container, "buffs") + iconCount(container, "buffsMine")
            expect(buffCount > 0).toBe(showBuffs)
            expect(iconCount(container, "debuffs") > 0).toBe(showDebuffs)
          end
        end
      end
    end
  end)

  it("stops the game's buff display listening, but keeps the debuff warning running", function()
    local h, F = boot()
    F.Config:Set("player.keepBlizzardBuffs", false)
    F.Config:Set("player.keepBlizzardDebuffs", false)
    h:advance(0.5)
    expect(h.env.BuffFrame:IsEventRegistered("UNIT_AURA")).toBe(false)
    expect(h.env.DebuffFrame:IsEventRegistered("UNIT_AURA")).toBe(true)
  end)

  it("says in chat that the game's displays need a reload to come back", function()
    local h, F = boot()
    F.Config:Set("player.keepBlizzardBuffs", false)
    F.Config:Set("player.keepBlizzardDebuffs", false)
    h:advance(0.5)
    expect(reloadLine(h)).toBe(nil)
    F.Config:Set("player.keepBlizzardBuffs", true)
    F.Config:Set("player.keepBlizzardDebuffs", true)
    h:advance(0.5)
    expect(reloadLine(h)).toMatch("buffs and debuffs will come back")
  end)

  it("sizes your icons and only lets you cancel buffs, on your own frame", function()
    local h, F = boot()
    F.Config:Set("player.auras.buffs", true)
    F.Config:Set("player.auras.debuffs", true)
    h.world:setParty({ { class = "PRIEST" } })
    h:advance(0.5)
    local icons = F.Frames:Get("player").AuraContainers.icons
    local buff = icons:GetAuraGroupFrame("buffs", 1)
    local width = buff:GetSize()
    expect(Harness.Secret.raw(width)).toBe(F.db.player.auras.buffSize)
    expect(buff.testCancelButtons).toBe("RightButtonUp")
    expect(icons:GetAuraGroupFrame("buffsMine", 1).testCancelButtons).toBe("RightButtonUp")
    expect(icons:GetAuraGroupFrame("debuffs", 1).testCancelButtons).toBe(nil)
    for _, obj in ipairs(h.widgets.all) do
      if obj.kind == "party" and obj.unit == "party1" then
        expect(obj.AuraContainers.icons:GetAuraGroupFrame("buffs", 1).testCancelButtons).toBe(nil)
      end
    end
  end)

  it("keeps a row of icons inside a frame with its portrait on the left", function()
    local h, F = boot()
    F.Config:Set("player.auras.buffs", true)
    h:advance(0.5)
    if h.mode == "strict" then return end
    local frame = F.Frames:Get("player")
    local icons = frame.AuraContainers.icons
    expect(icons:GetFlowLayoutMaximumLineSize()).toBe(frame.rects.statsBox.w)
    expect(frame.rects.statsBox.w < frame.rects.width).toBe(true)
  end)

  it("starts icons below a shaman's totem row", function()
    local h, F = boot()
    h.world:get("player").class = "SHAMAN"
    F.Config:Set("player.auras.buffs", true)
    h:advance(0.5)
    if h.mode == "strict" then return end
    local frame = F.Frames:Get("player")
    expect(frame.TotemRow ~= nil).toBe(true)
    local _, _, _, _, y = frame.AuraContainers.icons:GetPoint(1)
    expect(Harness.Secret.raw(y)).toBe(-2 - frame.TotemRow.height - 2)
  end)
end)

describe("Perl Infinity markers in front of the frame", function()
  -- A frame's own textures draw behind its child frames, and a frame with a
  -- higher level draws in front of a lower one. So an icon is in front of a
  -- box when the frame it's drawn on sits above the box and everything in it.
  local function level(region)
    if region:IsObjectType("Frame") then return region:GetFrameLevel() end
    return region:GetParent():GetFrameLevel()
  end

  local BOXES = { "NameBox", "StatsBox", "PortraitBox", "LevelBox", "TypeBox", "ComboBox", "Health", "Power",
    "PortraitModel", "Dragon" }
  local ICONS = { "LeaderIcon", "LooterIcon", "RaidIcon", "PvPIcon", "StateIcon", "RestIcon", "ReadyIcon",
    "ResurrectIcon", "RoleIcon", "CharmGlow", "RangeHand" }

  local function expectInFront(frame, label)
    local checked = 0
    for _, iconKey in ipairs(ICONS) do
      local icon = frame[iconKey]
      if icon then
        for _, boxKey in ipairs(BOXES) do
          local box = frame[boxKey]
          if box then
            if level(icon) <= level(box) then
              error(string.format("%s %s (level %d) is behind %s (level %d)", label, iconKey, level(icon), boxKey, level(box)))
            end
            checked = checked + 1
          end
        end
      end
    end
    if checked == 0 then error(label .. ": no icons or boxes to compare") end
  end

  local function find(h, kind, unit)
    for _, obj in ipairs(h.widgets.all) do
      if type(obj) == "table" and obj.kind == kind and not obj.preview and (unit == nil or obj.unit == unit) then
        return obj
      end
    end
  end

  it("draws raid markers, leader crowns and PvP badges in front of every box", function()
    local h, F = boot()
    h.world:setParty({ { class = "WARRIOR" }, { class = "PRIEST" } })
    h.world:setTarget(hostile())
    h.world:setRaidTarget("target", 8)
    h:advance(0.5)
    expectInFront(F.Frames:Get("player"), "player")
    expectInFront(F.Frames:Get("target"), "target")
    h.world:setFocus(hostile("Kobold Geomancer"))
    h:advance(0.5)
    expectInFront(F.Frames:Get("focus"), "focus")
    expectInFront(find(h, "party", "party1"), "party1")
    h.world:setRaid(10)
    h:advance(0.5)
    expectInFront(find(h, "raid"), "raid")
  end)
end)

describe("Perl Infinity elites and rares", function()
  local function level(region)
    if region:IsObjectType("Frame") then return region:GetFrameLevel() end
    return region:GetParent():GetFrameLevel()
  end

  local function edge(box)
    local r, g, b = box:GetBackdropBorderColor()
    return string.format("%.2f %.2f %.2f", r, g, b)
  end

  local GOLD, ICE, PLAIN = "1.00 0.82 0.00", "0.55 0.85 1.00", "0.50 0.50 0.50"

  local function target(h, classification)
    local spec = hostile()
    spec.classification = classification
    h.world:setTarget(spec)
    h:advance(0.5)
  end

  it("uses the dragon unless you pick something else", function()
    local _, F = boot()
    expect(F.Config:Get("target.elite")).toBe("dragon")
    expect(F.Config:Get("focus.elite")).toBe("dragon")
  end)

  it("wraps an elite's portrait in a gold dragon that sits behind the portrait and level", function()
    local h, F = boot()
    -- Rogues get the combo point box beside the level, which the wing passes under.
    h.world:get("player").class = "ROGUE"
    F.Config:Set("target.combo", 3)
    target(h, "elite")
    local frame = F.Frames:Get("target")
    expect(frame.Dragon:IsShown()).toBe(true)
    expect(frame.DragonArt:GetTexture()).toBe(F.Media.ELITE)
    for _, key in ipairs({ "NameBox", "StatsBox", "Health", "Power" }) do
      expect(level(frame.Dragon) > level(frame[key])).toBe(true)
    end
    for _, key in ipairs({ "PortraitBox", "PortraitModel", "LevelBox", "TypeBox", "ComboBox" }) do
      -- Strict mode hides even your own class, so there's no combo box there.
      if frame[key] or key ~= "ComboBox" then
        expect(level(frame.Dragon) < level(frame[key])).toBe(true)
      end
    end
    expect(edge(frame.NameBox)).toBe(GOLD)
    expect(edge(frame.PortraitBox)).toBe(GOLD)
    expect(frame.MarkTab:IsShown()).toBe(false)
    expect(frame.MarkGlow.Pulse:IsPlaying()).toBe(false)
  end)

  it("makes a rare hard to miss, then clears it all for an ordinary target", function()
    local h, F = boot()
    target(h, "rare")
    local frame = F.Frames:Get("target")
    expect(frame.Dragon:IsShown()).toBe(true)
    expect(frame.DragonArt:GetTexture()).toBe(F.Media.RARE)
    expect(frame.MarkTab:IsShown()).toBe(true)
    expect(frame.MarkTab.Text:GetText()).toBe(F.L.CLASS_RARE)
    expect(frame.MarkGlow.Pulse:IsPlaying()).toBe(true)
    expect(frame.MarkGlow:GetAlpha()).toBe(1)
    expect(edge(frame.StatsBox)).toBe(ICE)

    target(h, "rareelite")
    expect(frame.DragonArt:GetTexture()).toBe(F.Media.ELITE)
    expect(frame.MarkTab.Text:GetText()).toBe(F.L.CLASS_RARE_ELITE)
    expect(frame.MarkGlow.Pulse:IsPlaying()).toBe(true)

    target(h, "normal")
    expect(frame.Dragon:IsShown()).toBe(false)
    expect(frame.MarkTab:IsShown()).toBe(false)
    expect(frame.MarkGlow.Pulse:IsPlaying()).toBe(false)
    expect(frame.MarkGlow:GetAlpha()).toBe(0)
    expect(edge(frame.NameBox)).toBe(PLAIN)
    expect(edge(frame.LevelBox)).toBe(PLAIN)
  end)

  it("marks with a label instead when you pick it, or when there's no portrait to wrap", function()
    local h, F = boot()
    local frame = F.Frames:Get("target")
    F.Config:Set("target.elite", "text")
    target(h, "elite")
    expect(frame.Dragon:IsShown()).toBe(false)
    expect(frame.MarkTab:IsShown()).toBe(true)
    expect(frame.MarkTab.Text:GetText()).toBe(F.L.CLASS_ELITE)
    expect(edge(frame.NameBox)).toBe(GOLD)

    F.Config:Set("target.elite", "none")
    h:advance(0.5)
    expect(frame.Dragon:IsShown()).toBe(false)
    expect(frame.MarkTab:IsShown()).toBe(false)
    expect(edge(frame.NameBox)).toBe(PLAIN)

    F.Config:Set("target.elite", "dragon")
    F.Config:Set("target.portrait", false)
    h:advance(0.5)
    expect(frame.Dragon:IsShown()).toBe(false)
    expect(frame.MarkTab:IsShown()).toBe(true)
  end)

  it("never marks players", function()
    local h, F = boot()
    h.world:setTarget({ name = "Tamsin", isPlayer = true, class = "MAGE", classification = "elite" })
    h:advance(0.5)
    local frame = F.Frames:Get("target")
    expect(frame.Dragon:IsShown()).toBe(false)
    expect(frame.MarkTab:IsShown()).toBe(false)
    expect(edge(frame.NameBox)).toBe(PLAIN)
  end)
end)

describe("Perl Infinity resting", function()
  local function rest(h, on)
    h.world.resting = on
    h:fire("PLAYER_UPDATE_RESTING")
    h:advance(0.3)
  end

  it("plays the sleepy Zzz and a gold glow while you rest, and stops in combat", function()
    local h, F = boot()
    local frame = F.Frames:Get("player")
    expect(frame.RestIcon:GetAlpha()).toBe(0)
    rest(h, true)
    expect(frame.RestIcon:GetAlpha()).toBe(1)
    expect(frame.RestIcon:GetAtlas()).toBe("UI-HUD-UnitFrame-Player-Rest-Flipbook")
    expect(frame.RestLoop:IsPlaying()).toBe(true)
    expect(frame.RestGlow.Pulse:IsPlaying()).toBe(true)
    expect(frame.StateIcon:GetAlpha()).toBe(0)

    h.world:combat(true)
    h:advance(0.3)
    expect(frame.RestIcon:GetAlpha()).toBe(0)
    expect(frame.RestLoop:IsPlaying()).toBe(false)
    expect(frame.RestGlow.Pulse:IsPlaying()).toBe(false)
    expect(frame.StateIcon:GetAlpha()).toBe(1)

    h.world:combat(false)
    h:advance(0.3)
    expect(frame.RestLoop:IsPlaying()).toBe(true)

    rest(h, false)
    expect(frame.RestIcon:GetAlpha()).toBe(0)
    expect(frame.RestGlow:GetAlpha()).toBe(0)
    expect(frame.StateIcon:GetAlpha()).toBe(0)
  end)

  it("shows the still rest icon when the animation is off", function()
    local h, F = boot()
    local frame = F.Frames:Get("player")
    F.Config:Set("player.restAnimation", false)
    rest(h, true)
    expect(frame.StateIcon:GetAlpha()).toBe(1)
    expect(frame.RestIcon:GetAlpha()).toBe(0)
    expect(frame.RestLoop:IsPlaying()).toBe(false)
    expect(frame.RestGlow.Pulse:IsPlaying()).toBe(false)
  end)

  it("shows the animation in the options preview", function()
    local h, F = boot()
    F.Options:Open()
    F.Options:ShowPage("player")
    h:advance(0.3)
    local playing = false
    for _, obj in ipairs(h.widgets.all) do
      if type(obj) == "table" and obj.preview and obj.kind == "player" and obj:IsShown() and obj.RestLoop then
        playing = playing or obj.RestLoop:IsPlaying()
      end
    end
    expect(playing).toBe(true)
  end)
end)

describe("Perl Infinity debuff highlight", function()
  local raw = Harness.Secret.raw

  local function partyFrame(h, unit)
    for _, obj in ipairs(h.widgets.all) do
      if obj.kind == "party" and obj.unit == unit then return obj end
    end
  end

  local function slotButton(frame)
    local container = frame.AuraContainers and frame.AuraContainers.icons
    return container and container.slots.dispel and container:GetAuraSlotFrame("dispel"), container
  end

  local function alphas(button)
    local edges = {}
    for i, edge in ipairs(button.Edges) do edges[i] = raw(edge:GetAlpha()) end
    return edges, raw(button.Wash:GetAlpha())
  end

  -- Forever has no DebuffTypeColor. Without a color for a type, the game
  -- painted its own at full strength, which turned poisoned party members lime.
  it("has a color for every debuff type without DebuffTypeColor", function()
    local h, F = boot()
    expect(h.env.DebuffTypeColor).toBeNil()
    local colors = F.AuraHost.DispelColors()
    for _, kind in ipairs({ "Magic", "Curse", "Disease", "Poison", "None" }) do
      expect(colors[kind]).toBeTruthy()
    end
  end)

  -- The game keeps only red, green and blue from our colors, so the wash's
  -- strength has to come from the texture's own alpha.
  it("keeps the background faint on party frames", function()
    local h = boot()
    h.world:setParty({ { class = "PRIEST" } })
    h:advance(0.5)
    local button = slotButton(partyFrame(h, "party1"))
    expect(button).toBeTruthy()
    expect(button:GetDispelTypeTextureCount()).toBe(5)
    local edges, wash = alphas(button)
    for _, alpha in ipairs(edges) do expect(alpha).toBe(1) end
    expect(wash).toBe(0.3)
    expect(button.Wash:GetBlendMode()).toBe("ADD")
  end)

  it("shows only the border or only the background when you pick one", function()
    local h, F = boot()
    h.world:setParty({ { class = "PRIEST" } })
    h:advance(0.5)
    -- Strict mode keeps auras secret, so restyling waits; the choice is remembered.
    if h.mode == "strict" then return end
    F.Config:Set("highlight.debuffStyle", "border")
    h:advance(0.5)
    local button = slotButton(partyFrame(h, "party1"))
    local edges, wash = alphas(button)
    for _, alpha in ipairs(edges) do expect(alpha).toBe(1) end
    expect(wash).toBe(0)
    F.Config:Set("highlight.debuffStyle", "background")
    h:advance(0.5)
    edges, wash = alphas(button)
    for _, alpha in ipairs(edges) do expect(alpha).toBe(0) end
    expect(wash).toBe(0.3)
  end)

  it("colors your own frame for any debuff, with no icons needed", function()
    local h, F = boot()
    h:advance(0.5)
    local player = F.Frames:Get("player")
    expect(F.db.player.debuffHighlight).toBe(true)
    expect(F.db.player.auras.debuffs).toBe(false)
    local button, container = slotButton(player)
    expect(button).toBeTruthy()
    expect(container:IsAuraSlotEnabled("dispel")).toBe(true)
    expect(h.widgets.state[container].aura.slots.dispel.filter).toBe("HARMFUL")
    F.Config:Set("player.debuffHighlight", false)
    h:advance(0.5)
    expect(container:IsAuraSlotEnabled("dispel")).toBe(false)
  end)

  it("colors your target with its icons turned off", function()
    local h, F = boot()
    F.Config:Set("target.debuffHighlight", "both")
    F.Config:Set("target.auras.buffs", false)
    F.Config:Set("target.auras.debuffs", false)
    h.world:setTarget(hostile())
    h:advance(0.5)
    local button, container = slotButton(F.Frames:Get("target"))
    expect(button).toBeTruthy()
    expect(container:IsAuraSlotEnabled("dispel")).toBe(true)
  end)
end)
