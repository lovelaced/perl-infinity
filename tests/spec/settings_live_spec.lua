-- tests/spec/settings_live_spec.lua
-- Settings that have to take effect while you play, without a /reload, and the
-- fixes from the November 2026 review: frames switched on and off, group
-- layouts changed live, settings that used to do nothing, ready checks, cast
-- bars and hidden names, icons in front of the boxes, the low health warning
-- on its own, and the options window preview.

local TOC = ROOT .. "/PerlInfinity/PerlInfinity.toc"
local raw = Harness.Secret.raw

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

local function find(h, kind, unit)
  for _, obj in ipairs(h.widgets.all) do
    if type(obj) == "table" and obj.kind == kind and not obj.preview and (unit == nil or obj.unit == unit) then
      return obj
    end
  end
end

local function visibleChildren(header)
  local list = {}
  for _, child in ipairs(header and header.children or {}) do
    if child:IsVisible() then list[#list + 1] = child end
  end
  return list
end

local function raidButtons(h)
  local list = {}
  for i = 1, 9 do
    for _, child in ipairs(visibleChildren(h.env["PerlInfinity_RaidHeader" .. i])) do
      list[#list + 1] = child
    end
  end
  return list
end

describe("Perl Infinity frame switches", function()
  it("turns a frame on and off without a reload", function()
    local h, F = boot()
    expect(F.Frames:Get("targettargettarget")).toBeNil()
    F.Config:Set("small.targettargettarget.enabled", true)
    h:advance(0.3)
    expect(F.Frames:Get("targettargettarget")).toBeTruthy()
    expect(F.Movers:Get("targettargettarget"):IsShown()).toBe(true)

    local player = F.Frames:Get("player")
    F.Config:Set("player.enabled", false)
    h:advance(0.3)
    expect(player:IsShown()).toBe(false)
    expect(F.Movers:Get("player"):IsShown()).toBe(false)
    F.Config:Set("player.enabled", true)
    h:advance(0.3)
    expect(player:IsShown()).toBe(true)
  end)

  it("waits for combat to end before switching a secure frame", function()
    local h, F = boot()
    h.world:combat(true)
    F.Config:Set("small.targettargettarget.enabled", true)
    h:advance(0.3)
    expect(F.Frames:Get("targettargettarget")).toBeNil()
    h.world:combat(false)
    h:advance(0.3)
    expect(F.Frames:Get("targettargettarget")).toBeTruthy()
  end)

  it("keeps the party hidden while it's off, even when other party settings change", function()
    local h, F = boot()
    h.world:setParty({ { class = "WARRIOR" }, { class = "PRIEST" } })
    h:advance(0.5)
    local header = h.env.PerlInfinity_PartyHeader
    expect(header:IsShown()).toBe(true)
    F.Config:Set("party.enabled", false)
    h:advance(0.3)
    expect(header:IsShown()).toBe(false)
    F.Config:Set("party.direction", "right")
    h:advance(0.3)
    h.world:setParty({ { class = "WARRIOR" }, { class = "PRIEST" }, { class = "MAGE" } })
    h:advance(0.3)
    expect(header:IsShown()).toBe(false)
    F.Config:Set("party.enabled", true)
    h:advance(0.3)
    expect(header:IsShown()).toBe(true)
  end)

  it("lets the key binding show and hide raid frames, pets included", function()
    local h, F = boot()
    h.world:setRaid(10)
    h:advance(1)
    expect(#raidButtons(h)).toBe(10)
    F.Bindings.Toggle("raid.enabled")
    h:advance(0.3)
    expect(#raidButtons(h)).toBe(0)
    local pets = h.env.PerlInfinity_RaidPetHeader
    expect(pets == nil or not pets:IsShown()).toBe(true)
    F.Bindings.Toggle("raid.enabled")
    h:advance(0.3)
    expect(#raidButtons(h)).toBe(10)
  end)

  it("builds raid frames that were off at login once you turn them on", function()
    local h, F = boot()
    F.Config:Set("raid.enabled", false)
    h:advance(0.3)
    local h2 = h:reload()
    h2:advance(0.5)
    local F2 = h2.env.PerlInfinity
    expect(F2.Config:Get("raid.enabled")).toBe(false)
    h2.world:setRaid(10)
    h2:advance(0.5)
    expect(#raidButtons(h2)).toBe(0)
    F2.Config:Set("raid.enabled", true)
    h2:advance(1)
    expect(#raidButtons(h2)).toBe(10)
  end)
end)

describe("Perl Infinity group layouts changed live", function()
  local function tops(children)
    local list = {}
    for i, child in ipairs(children) do list[i] = child:GetTop() end
    return list
  end

  it("lines the party up in a row after switching from a column", function()
    local h, F = boot()
    h.world:setParty({ { class = "WARRIOR" }, { class = "PRIEST" }, { class = "ROGUE" } })
    h:advance(0.5)
    F.Config:Set("party.direction", "right")
    h:advance(0.5)
    local children = visibleChildren(h.env.PerlInfinity_PartyHeader)
    expect(#children).toBe(3)
    local list = tops(children)
    for i = 2, #list do
      expect(list[i]).toBeCloseTo(list[1], 0.01)
      expect(children[i]:GetLeft()).toBeGreaterThan(children[i - 1]:GetLeft())
    end
  end)

  it("stacks raid columns cleanly after changing the sort and direction", function()
    local h, F = boot()
    h.world:setRaid(10)
    h:advance(1)
    F.Config:Set("raid.direction", "right")
    h:advance(0.5)
    F.Config:Set("raid.sortBy", "class")
    h:advance(0.5)
    F.Config:Set("raid.direction", "down")
    h:advance(0.5)
    for i = 1, 9 do
      local header = h.env["PerlInfinity_RaidHeader" .. i]
      local children = visibleChildren(header)
      for j = 2, #children do
        expect(children[j]:GetLeft()).toBeCloseTo(children[1]:GetLeft(), 0.01)
        expect(children[j - 1]:GetTop()).toBeGreaterThan(children[j]:GetTop())
      end
    end
  end)

  it("still shows the raid sorted by role with a class unticked", function()
    local h, F = boot()
    h.world:setRaid(10)
    h:advance(1)
    F.Config:Set("raid.sortBy", "role")
    -- Warriors are the first class in the raid's class order.
    F.Config:Set("raid.classes", F.Util.SetBit(F.Config:Get("raid.classes"), 1, false))
    h:advance(0.5)
    local buttons = raidButtons(h)
    expect(#buttons).toBeGreaterThan(0)
    for _, button in ipairs(buttons) do
      local _, class = h.env.UnitClass(button.unit)
      expect(raw(class) ~= "WARRIOR").toBe(true)
    end
  end)
end)

describe("Perl Infinity settings that used to do nothing", function()
  it("fades every frame by the frame opacity", function()
    local h, F = boot()
    h.world:setTarget(hostile())
    h:advance(0.3)
    F.Config:Set("look.frameAlpha", 0.5)
    h:advance(0.3)
    expect(raw(F.Frames:Get("player"):GetAlpha())).toBeCloseTo(0.5, 0.001)
    expect(raw(F.Frames:Get("target"):GetAlpha())).toBeCloseTo(0.5, 0.001)
  end)

  it("hides raid frames in a battleground and brings them back after", function()
    local h, F = boot()
    F.Config:Set("raid.hideInBattlegrounds", true)
    h.world:setRaid(10)
    h:advance(1)
    expect(#raidButtons(h)).toBe(10)
    h.world:instance("pvp")
    h:advance(0.5)
    expect(#raidButtons(h)).toBe(0)
    h.world:instance("none")
    h:advance(0.5)
    expect(#raidButtons(h)).toBe(10)
  end)

  it("drops the tank window's third column when it's turned off", function()
    local h, F = boot()
    F.Config:Set("tanks.enabled", true)
    h.world:setRaid(10, function(i) if i == 2 then return { role = "TANK", raidRole = "MAINTANK" } end end)
    -- The tank fights a mob that's attacking the tank, so all three columns fill.
    h.world:setTarget(hostile(), "raid2")
    h.world:setTarget("raid2", "raid2target")
    h:advance(1)
    local row = visibleChildren(h.env.PerlInfinity_TankHeader)[1]
    expect(row).toBeTruthy()
    expect(row.TankTargetTarget:IsShown()).toBe(true)
    local width = F.Movers:Get("tanks"):GetWidth()
    F.Config:Set("tanks.showTargetTarget", false)
    h:advance(0.5)
    expect(row.TankTargetTarget:IsShown()).toBe(false)
    expect(F.Movers:Get("tanks"):GetWidth() < width).toBe(true)
  end)

  it("sizes tank and healer rows by their Height sliders", function()
    local h, F = boot()
    F.Config:Set("tanks.enabled", true)
    F.Config:Set("healers.enabled", true)
    h.world:setRaid(10, function(i)
      if i == 2 then return { role = "TANK", raidRole = "MAINTANK", class = "WARRIOR" } end
      if i == 3 then return { class = "PRIEST" } end
    end)
    h:advance(1)
    F.Config:Set("tanks.height", 44)
    F.Config:Set("healers.height", 50)
    h:advance(0.5)
    local tank = visibleChildren(h.env.PerlInfinity_TankHeader)[1]
    expect(tank:GetHeight()).toBeCloseTo(44, 0.01)
    expect(tank.TankTarget:GetHeight()).toBeCloseTo(44, 0.01)
    local healer = visibleChildren(h.env.PerlInfinity_HealerHeader)[1]
    expect(healer:GetHeight()).toBeCloseTo(50, 0.01)
    expect(healer.HealerTarget:GetHeight()).toBeCloseTo(50, 0.01)
  end)

  it("gives the healer window's target column its own settings", function()
    local h, F = boot()
    F.Config:Set("healers.enabled", true)
    h.world:setRaid(10, function(i) if i == 3 then return { class = "PRIEST" } end end)
    h:advance(1)
    local healer = visibleChildren(h.env.PerlInfinity_HealerHeader)[1]
    expect(healer.HealerTarget.kind).toBe("healertarget")
    expect(healer.HealerTarget.healthText).toBe("percent")
    F.Config:Set("healers.width", 80)
    h:advance(0.5)
    expect(healer.HealerTarget:GetWidth()).toBeCloseTo(healer:GetWidth(), 0.01)
  end)

  it("offers the highlight style whatever the party highlight is set to", function()
    local _, F = boot()
    for _, page in ipairs(F.OptionPages.list) do
      for _, option in ipairs(page.rows) do
        if option.path == "highlight.debuffStyle" then
          expect(option.parent).toBeNil()
        end
      end
    end
  end)
end)

describe("Perl Infinity ready checks", function()
  it("shows the check mark, which is an atlas on Forever", function()
    local h, F = boot()
    h.world:setParty({ { class = "WARRIOR" } })
    h:advance(0.5)
    h.world:get("player").readyCheck = "waiting"
    h.world:get("party1").readyCheck = "ready"
    h:fire("READY_CHECK", "Leader", 30)
    h:advance(0.1)
    local party = find(h, "party", "party1")
    expect(party.ReadyIcon:GetAtlas()).toBe("UI-LFG-ReadyMark")
    expect(raw(party.ReadyIcon:GetAlpha())).toBe(1)
    local player = F.Frames:Get("player")
    expect(player.ReadyIcon:GetAtlas()).toBe("UI-LFG-PendingMark")
  end)
end)

describe("Perl Infinity cast bars and hidden names", function()
  it("keeps a party member's name hidden after they cast", function()
    local h, F = boot()
    F.Config:Set("party.names", false)
    h.world:setParty({ { class = "PRIEST" } })
    h:advance(0.5)
    local frame = find(h, "party", "party1")
    expect(frame.NameText:IsShown()).toBe(false)
    h.world:startCast("party1", { name = "Heal", duration = 1 })
    h:advance(0.5)
    h.world:stopCast("party1")
    h:advance(2)
    expect(frame.Castbar:IsShown()).toBe(false)
    expect(frame.NameText:IsShown()).toBe(false)
  end)

  it("gives the name back after a cast when names are on", function()
    local h = boot()
    h.world:setParty({ { class = "PRIEST" } })
    h:advance(0.5)
    local frame = find(h, "party", "party1")
    h.world:startCast("party1", { name = "Heal", duration = 1 })
    h:advance(0.5)
    expect(frame.NameText:IsShown()).toBe(false)
    h.world:stopCast("party1")
    h:advance(2)
    expect(frame.NameText:IsShown()).toBe(true)
  end)
end)

describe("Perl Infinity icons in front of the boxes", function()
  local function level(region)
    if region:IsObjectType("Frame") then return region:GetFrameLevel() end
    return region:GetParent():GetFrameLevel()
  end

  it("draws target icons and the debuff outline over the type box, dragon and portrait", function()
    local h, F = boot()
    h.world:setTarget(hostile())
    h:advance(0.5)
    local target = F.Frames:Get("target")
    local container = target.AuraContainers.icons
    for _, key in ipairs({ "TypeBox", "Dragon", "PortraitBox", "LevelBox" }) do
      expect(level(container) > level(target[key])).toBe(true)
    end
  end)

  it("puts the creature type under the bars when the portrait is off", function()
    local h, F = boot()
    F.Config:Set("target.portrait", false)
    h.world:setTarget(hostile())
    h:advance(0.5)
    local target = F.Frames:Get("target")
    expect(target.TypeBox:GetTop()).toBeCloseTo(target.StatsBox:GetBottom() + 2, 0.01)
  end)

  it("adds icons switched on in combat once combat ends", function()
    local h, F = boot()
    h.world:combat(true)
    F.Config:Set("player.auras.buffs", true)
    h:advance(0.5)
    local container = F.Frames:Get("player").AuraContainers.icons
    expect(next(container.groups)).toBeNil()
    h.world:combat(false)
    h:advance(0.5)
    expect(next(container.groups)).toBeTruthy()
  end)
end)

describe("Perl Infinity low health warning", function()
  it("works with the player frame turned off, and stops when you turn it off", function()
    local h, F = boot()
    F.Config:Set("player.enabled", false)
    h:advance(0.3)
    local overlay = F.LowHealth.overlay
    local me = h.world:get("player")
    h.world:damage("player", me.maxHealth * 0.9)
    h:advance(0.3)
    expect(raw(overlay:GetAlpha())).toBeGreaterThan(0)
    F.Config:Set("alerts.lowHealth", false)
    h:advance(0.3)
    expect(raw(overlay:GetAlpha())).toBe(0)
  end)
end)

describe("Perl Infinity options preview", function()
  local function previewFrames(h)
    local list = {}
    for _, obj in ipairs(h.widgets.all) do
      if type(obj) == "table" and obj.preview and obj.kind and obj:IsVisible() then
        list[#list + 1] = obj
      end
    end
    return list
  end

  local function edges(region)
    local l, b, w, hgt = region:GetRect()
    local s = region:GetEffectiveScale()
    return l * s, (l + w) * s, b * s, (b + hgt) * s
  end

  it("draws sample frames for every page with a preview, inside the pane", function()
    local h, F = boot()
    F.Options:Open()
    local pane = h.env.PerlInfinityOptionsFrame.Preview
    local pl, pr = edges(pane)
    local pages = 0
    for _, page in ipairs(F.OptionPages.list) do
      F.Options:ShowPage(page.key)
      h:advance(0.05)
      local frames = previewFrames(h)
      if page.preview and page.preview ~= "tools" then
        pages = pages + 1
        if #frames == 0 then error("page " .. page.key .. " has an empty preview") end
        for _, frame in ipairs(frames) do
          local l, r = edges(frame)
          local what = page.key .. " " .. frame.kind
          if frame:GetWidth() <= 0 or frame:GetHeight() <= 0 then error(what .. " has no size") end
          if l < pl - 0.5 or r > pr + 0.5 then error(what .. " spills out of the preview") end
          if frame.NameText:IsShown() and (raw(frame.NameText:GetText()) or "") == "" then
            error(what .. " shows an empty name")
          end
        end
        -- Frames at different scales still never land on top of each other.
        for i = 1, #frames do
          for j = i + 1, #frames do
            local al, ar, ab, at = edges(frames[i])
            local bl, br, bb, bt = edges(frames[j])
            if al < br - 0.5 and bl < ar - 0.5 and ab < bt - 0.5 and bb < at - 0.5 then
              error(page.key .. ": " .. frames[i].kind .. " overlaps " .. frames[j].kind)
            end
          end
        end
      elseif not page.preview then
        expect(#frames).toBe(0)
      end
    end
    expect(pages).toBeGreaterThan(5)
  end)

  it("follows setting changes while it's open", function()
    local h, F = boot()
    F.Options:Open()
    F.Options:ShowPage("party")
    h:advance(0.05)
    F.Config:Set("party.names", false)
    F.Config:Set("look.frameAlpha", 0.6)
    h:advance(0.3)
    local party = 0
    for _, frame in ipairs(previewFrames(h)) do
      if frame.kind == "party" then
        party = party + 1
        expect(frame.NameText:IsShown()).toBe(false)
        expect(raw(frame:GetAlpha())).toBeCloseTo(0.6, 0.001)
      end
    end
    expect(party).toBe(4)
  end)

  it("shows ready check marks and samples on the party page", function()
    local h, F = boot()
    F.Options:Open()
    F.Options:ShowPage("party")
    h:advance(0.05)
    local marks = 0
    for _, frame in ipairs(previewFrames(h)) do
      if frame.kind == "party" and raw(frame.ReadyIcon:GetAlpha()) == 1 then
        expect(frame.ReadyIcon:GetAtlas()).toBe("UI-LFG-ReadyMark")
        marks = marks + 1
      end
    end
    expect(marks).toBe(2)
  end)

  it("never builds aura containers or secure frames for the preview", function()
    local h, F = boot()
    F.Options:Open()
    for _, page in ipairs(F.OptionPages.list) do
      F.Options:ShowPage(page.key)
      h:advance(0.02)
    end
    for _, frame in ipairs(previewFrames(h)) do
      expect(frame.AuraContainers == nil or next(frame.AuraContainers) == nil).toBe(true)
      expect(frame:IsProtected()).toBeFalsy()
    end
  end)
end)

describe("Perl Infinity player reports, November 2026", function()
  local function level(region)
    if region:IsObjectType("Frame") then return region:GetFrameLevel() end
    return region:GetParent():GetFrameLevel()
  end

  it("hides the reputation bar when you turn it off", function()
    local h, F = boot()
    local player = F.Frames:Get("player")
    F.Config:Set("player.repBar", true)
    h:advance(0.3)
    local rep = player.RepBar
    expect(rep:IsShown()).toBe(true)
    F.Config:Set("player.repBar", false)
    h:advance(0.3)
    expect(rep:IsShown()).toBe(false)
    expect(player.RepBar).toBeNil()
  end)

  it("moves the reputation bar up without the XP bar's rested overlay", function()
    local h, F = boot()
    local player = F.Frames:Get("player")
    F.Config:Set("player.xpBar", true)
    F.Config:Set("player.repBar", true)
    h:advance(0.3)
    local xp = player.XPBar
    F.Config:Set("player.xpBar", false)
    h:advance(0.3)
    expect(xp:IsShown()).toBe(false)
    expect(player.RepBar ~= xp).toBe(true)
    expect(player.RepBar:IsShown()).toBe(true)
    expect(player.RepBar.Rested).toBeNil()
  end)

  it("hides the creature type box for players and shows it for creatures", function()
    local h, F = boot()
    h.world:setTarget({ name = "Somebody", class = "MAGE", level = 60, reaction = 5 })
    h:advance(0.3)
    local target = F.Frames:Get("target")
    expect(target.TypeBox:IsShown()).toBe(false)
    h.world:setTarget({ name = "Plainstrider", npc = true, reaction = 2, level = 12, creatureType = "Beast" })
    h:advance(0.3)
    expect(target.TypeBox:IsShown()).toBe(true)
    expect(raw(target.TypeBox.Text:GetText())).toBe("Beast")
  end)

  it("can show the creature type above the frame", function()
    local h, F = boot()
    F.Config:Set("target.creatureTypePosition", "above")
    h.world:setTarget(hostile())
    h:advance(0.3)
    local target = F.Frames:Get("target")
    expect(target.TypeBox:IsShown()).toBe(true)
    expect(target.TypeBox:GetBottom()).toBeCloseTo(target.NameBox:GetTop() - 2, 0.01)
  end)

  it("gives the small frames' empty space to the health bar", function()
    local h, F = boot()
    h.world:setTarget(hostile())
    h.world:setTarget("player", "target")
    h:advance(0.5)
    local tot = F.Frames:Get("targettarget")
    expect(tot.Health:GetHeight()).toBeCloseTo(18, 0.01)
    -- The power bar ends where the stats box's inner edge starts.
    expect(tot.Power:GetBottom() - tot.StatsBox:GetBottom()).toBeCloseTo(5, 0.01)
  end)

  it("draws names, percents and cast text in front of the elite dragon", function()
    local h, F = boot()
    h.world:setTarget(hostile())
    h:advance(0.3)
    local target = F.Frames:Get("target")
    local dragon = level(target.Dragon)
    for _, key in ipairs({ "NameText", "HealthPercent", "PowerPercent" }) do
      expect(level(target[key]) > dragon).toBe(true)
    end
    expect(level(target.Castbar.Text) > dragon).toBe(true)
    expect(level(target.Castbar.Time) > dragon).toBe(true)
    -- Still inside their boxes, so range fading reaches them.
    expect(target.NameText:GetParent():GetParent()).toBe(target.NameBox)
    expect(target.HealthPercent:GetParent():GetParent()).toBe(target.StatsBox)
  end)

  it("lets you keep the Zzz without the resting glow", function()
    local h, F = boot()
    F.Config:Set("player.restGlow", false)
    h.world.resting = true
    h:fire("PLAYER_UPDATE_RESTING")
    h:advance(0.3)
    local frame = F.Frames:Get("player")
    expect(raw(frame.RestIcon:GetAlpha())).toBe(1)
    expect(frame.RestLoop:IsPlaying()).toBe(true)
    expect(raw(frame.RestGlow:GetAlpha())).toBe(0)
    F.Config:Set("player.restGlow", true)
    h:advance(0.3)
    expect(raw(frame.RestGlow:GetAlpha())).toBe(1)
  end)

  it("centers names when you ask", function()
    local h, F = boot()
    expect(F.Frames:Get("player").NameText:GetJustifyH()).toBe("LEFT")
    F.Config:Set("look.centerNames", true)
    h:advance(0.3)
    expect(F.Frames:Get("player").NameText:GetJustifyH()).toBe("CENTER")
  end)
end)
