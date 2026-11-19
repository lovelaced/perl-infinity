-- tests/spec/profiles_spec.lua
-- Profiles, the way a player uses them: the Profiles page's dropdowns and
-- buttons, the popups they open, export and import strings, /pinf profile,
-- and what survives a reload or a new character logging in.

local TOC = ROOT .. "/PerlInfinity/PerlInfinity.toc"
local raw = Harness.Secret.raw

local function boot(opts)
  local h = Harness.new(opts or {})
  h:loadToc(TOC)
  h:login(opts and opts.savedVariables)
  h:advance(0.5)
  return h, h.env.PerlInfinity
end

-- The row for `key` on the Profiles page, with the options window open there.
local function row(h, F, key)
  if not F.Options:IsShown() then F.Options:Open() end
  F.Options:ShowPage("profiles")
  h:advance(0.05)
  for _, child in ipairs({ h.env.PerlInfinityOptionsFrame.List:GetChildren() }) do
    if child.option and child.option.key == key and child:IsShown() then return child end
  end
  error("no row " .. key .. " on the Profiles page")
end

local function click(h, F, key)
  row(h, F, key).Control:Click()
  h:advance(0.05)
end

local function dropdown(h, F, key)
  local menu = row(h, F, key).Control.Dropdown
  menu:GenerateMenu()
  return menu
end

local function labels(menu)
  local list = {}
  for _, entry in ipairs(menu.entries) do list[#list + 1] = entry.text end
  return table.concat(list, ",")
end

local function pick(h, F, key, label)
  local menu = dropdown(h, F, key)
  for i, entry in ipairs(menu.entries) do
    if entry.text == label then
      menu:PickEntry(i)
      h:advance(0.3)
      return
    end
  end
  error("no " .. label .. " in " .. key .. " (" .. labels(menu) .. ")")
end

local function printed(h, text)
  for _, line in ipairs(h.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

local function playerScale(F)
  return raw(F.Movers:Get("player"):GetScale())
end

-- The game shares four popup frames between every popup, and a popup that
-- sets a length limit on its edit box leaves it there for the next one. Adding
-- a friend is a common way to end up with a 77 letter box.
local function openFriendPopup(h)
  h.env.StaticPopupDialogs.TEST_ADD_FRIEND = { text = "Add a friend", hasEditBox = true, maxLetters = 12 + 1 + 64, hideOnEscape = true }
  h.env.StaticPopup_Show("TEST_ADD_FRIEND")
  h:clickPopup("TEST_ADD_FRIEND", 2)
end

-- Enough changes that the export string runs well past 77 letters.
local function customize(F)
  F.Config:Set("player.scale", 1.3)
  F.Config:Set("look.centerNames", true)
  F.Config:Set("look.background", "ff336699")
  F.Config:Set("party.auras.buffSize", 24)
  F.Config:Set("target.debuffHighlight", "both")
end

describe("Perl Infinity profiles page", function()
  it("makes a new profile from your current settings and switches to it", function()
    local h, F = boot()
    F.Config:Set("player.scale", 1.3)
    click(h, F, "profileNew")
    expect(h:popup("PERLINFINITY_PROFILE_NEW")).toBeTruthy()
    expect(h:acceptPopup("PERLINFINITY_PROFILE_NEW", "  Raiding  ")).toBe(true)
    h:advance(0.3)
    expect(F.Profiles:Active()).toBe("Raiding")
    expect(F.db.player.scale).toBe(1.3)
    expect(dropdown(h, F, "profiles.active"):SelectedText()).toBe("Raiding")
    expect(labels(dropdown(h, F, "profiles.active"))).toBe("Default,Raiding")
    -- A copy, not the same table: changing one leaves the other alone.
    F.Config:Set("player.scale", 1.1)
    expect(F.Config:DB().profiles.Default.player.scale).toBe(1.3)
  end)

  it("makes the new profile when you press Enter, too", function()
    local h, F = boot()
    click(h, F, "profileNew")
    h:typeInPopup("PERLINFINITY_PROFILE_NEW", "Raiding")
    h:pressInPopup("PERLINFINITY_PROFILE_NEW", "ENTER")
    expect(F.Profiles:Active()).toBe("Raiding")
    expect(h:popup("PERLINFINITY_PROFILE_NEW")).toBeNil()
  end)

  it("won't reuse a name, and waits for one if you leave it empty", function()
    local h, F = boot()
    click(h, F, "profileNew")
    h:acceptPopup("PERLINFINITY_PROFILE_NEW", "Default")
    expect(printed(h, "There's already a profile with that name.")).toBe(true)
    expect(#F.Profiles:List()).toBe(1)

    h.printed = {}
    click(h, F, "profileNew")
    h:acceptPopup("PERLINFINITY_PROFILE_NEW", "   ")
    expect(printed(h, "There's already a profile")).toBe(false)
    expect(h:popup("PERLINFINITY_PROFILE_NEW")).toBeTruthy()
    expect(#F.Profiles:List()).toBe(1)
  end)

  it("switches profiles from the dropdown, and your frames follow", function()
    local h, F = boot()
    F.Profiles:Create("Big")
    F.Profiles:Use("Big")
    F.Config:Set("player.scale", 1.3)
    h:advance(0.3)
    expect(playerScale(F)).toBe(1.3)

    pick(h, F, "profiles.active", "Default")
    expect(F.Profiles:Active()).toBe("Default")
    expect(playerScale(F)).toBe(F.Config:GetDefault("player.scale"))
    pick(h, F, "profiles.active", "Big")
    expect(playerScale(F)).toBe(1.3)
  end)

  it("switches in combat and resizes your frames when the fight ends", function()
    local h, F = boot()
    F.Profiles:Create("Big")
    F.Config:DB().profiles.Big.player = { scale = 1.3 }
    h.world:combat(true)
    pick(h, F, "profiles.active", "Big")
    expect(F.db.player.scale).toBe(1.3)
    h.world:combat(false)
    h:advance(0.3)
    expect(playerScale(F)).toBe(1.3)
  end)

  it("copies another profile's settings into the one you're using", function()
    local h, F = boot()
    F.Profiles:Create("Raiding")
    F.Config:DB().profiles.Raiding.player = { scale = 1.3 }
    local menu = dropdown(h, F, "profiles.copyFrom")
    expect(labels(menu)).toBe("Raiding")
    pick(h, F, "profiles.copyFrom", "Raiding")
    local popup = h:popup("PERLINFINITY_PROFILE_COPY")
    expect(popup).toBeTruthy()
    expect(popup.text1).toBe("Raiding")
    expect(popup.text2).toBe("Default")
    h:acceptPopup("PERLINFINITY_PROFILE_COPY")
    h:advance(0.3)
    expect(F.Profiles:Active()).toBe("Default")
    expect(F.db.player.scale).toBe(1.3)
    expect(playerScale(F)).toBe(1.3)
    F.Config:Set("player.scale", 1.1)
    expect(F.Config:DB().profiles.Raiding.player.scale).toBe(1.3)
  end)

  it("leaves your settings alone when you cancel the copy", function()
    local h, F = boot()
    F.Profiles:Create("Raiding")
    F.Config:DB().profiles.Raiding.player = { scale = 1.3 }
    pick(h, F, "profiles.copyFrom", "Raiding")
    h:clickPopup("PERLINFINITY_PROFILE_COPY", 2)
    expect(F.db.player.scale).toBe(F.Config:GetDefault("player.scale"))
  end)

  it("renames the profile you're using", function()
    local h, F = boot()
    F.Profiles:Create("Raiding")
    click(h, F, "profileRename")
    local popup = h:popup("PERLINFINITY_PROFILE_RENAME")
    expect(popup).toBeTruthy()
    expect(popup.EditBox:GetText()).toBe("Default")
    h:acceptPopup("PERLINFINITY_PROFILE_RENAME", "Main")
    h:advance(0.3)
    expect(F.Profiles:Active()).toBe("Main")
    expect(F.Profiles:Exists("Default")).toBe(false)
    expect(F.Config:DB().newCharacterProfile).toBe("Main")
    expect(dropdown(h, F, "profiles.active"):SelectedText()).toBe("Main")
    expect(dropdown(h, F, "profiles.newCharacters"):SelectedText()).toBe("Main")

    click(h, F, "profileRename")
    h:typeInPopup("PERLINFINITY_PROFILE_RENAME", "Raiding")
    h:pressInPopup("PERLINFINITY_PROFILE_RENAME", "ENTER")
    expect(printed(h, "There's already a profile with that name.")).toBe(true)
    expect(F.Profiles:Active()).toBe("Main")
  end)

  it("deletes the profile you're using and moves you to another", function()
    local h, F = boot()
    F.Profiles:Create("Raiding")
    F.Config:DB().profiles.Raiding.player = { scale = 1.3 }
    F.Profiles:Use("Raiding")
    h:advance(0.3)
    click(h, F, "profileDelete")
    expect(h:popup("PERLINFINITY_PROFILE_DELETE").text1).toBe("Raiding")
    h:acceptPopup("PERLINFINITY_PROFILE_DELETE")
    h:advance(0.3)
    expect(F.Profiles:Active()).toBe("Default")
    expect(F.Profiles:Exists("Raiding")).toBe(false)
    expect(playerScale(F)).toBe(F.Config:GetDefault("player.scale"))
    expect(labels(dropdown(h, F, "profiles.active"))).toBe("Default")

    -- The last profile stays.
    click(h, F, "profileDelete")
    expect(h:popup("PERLINFINITY_PROFILE_DELETE")).toBeNil()
    expect(printed(h, "You need at least one profile.")).toBe(true)
  end)

  it("moves new characters to another profile when theirs is deleted", function()
    local h, F = boot()
    F.Profiles:Create("Raiding")
    pick(h, F, "profiles.newCharacters", "Raiding")
    F.Profiles:Use("Raiding")
    click(h, F, "profileDelete")
    h:acceptPopup("PERLINFINITY_PROFILE_DELETE")
    expect(F.Config:DB().newCharacterProfile).toBe("Default")
    expect(F.Profiles:Active()).toBe("Default")
  end)

  it("resets the profile you're using and nothing else", function()
    local h, F = boot()
    F.Profiles:Create("Raiding")
    F.Config:DB().profiles.Raiding.player = { scale = 1.3 }
    F.Config:Set("player.scale", 1.2)
    h:advance(0.3)
    click(h, F, "profileReset")
    h:acceptPopup("PERLINFINITY_PROFILE_RESET")
    h:advance(0.3)
    expect(F.db.player.scale).toBe(F.Config:GetDefault("player.scale"))
    expect(playerScale(F)).toBe(F.Config:GetDefault("player.scale"))
    expect(F.Config:DB().profiles.Raiding.player.scale).toBe(1.3)
  end)

  -- The Defaults button shares the popup code: one page's settings, or all.
  it("puts one page back to defaults, or every page", function()
    local h, F = boot()
    F.Config:Set("player.scale", 1.3)
    F.Config:Set("party.scale", 1.2)
    F.Options:Open()
    F.Options:ShowPage("player")
    h.env.PerlInfinityOptionsFrame.Defaults:Click()
    expect(h:popup("PERLINFINITY_DEFAULTS").data.key).toBe("player")
    h:acceptPopup("PERLINFINITY_DEFAULTS")
    expect(F.db.player.scale).toBe(F.Config:GetDefault("player.scale"))
    expect(F.db.party.scale).toBe(1.2)

    h.env.PerlInfinityOptionsFrame.Defaults:Click()
    h:clickPopup("PERLINFINITY_DEFAULTS", 3)
    expect(F.db.party.scale).toBe(F.Config:GetDefault("party.scale"))
  end)

  it("won't open profile popups in combat", function()
    local h, F = boot()
    h.world:combat(true)
    click(h, F, "profileNew")
    expect(h:popup("PERLINFINITY_PROFILE_NEW")).toBeNil()
    expect(printed(h, "That has to wait until you're out of combat.")).toBe(true)
  end)
end)

describe("Perl Infinity profile sharing", function()
  -- The export and import boxes are the game's shared popup boxes. Any popup
  -- that limits its box, like adding a friend, used to leave the limit
  -- behind, so the export string was cut short and imports failed.
  it("exports and imports a whole profile after another popup limited the box", function()
    local h, F = boot()
    customize(F)
    local full = F.Profiles:Export("Default", false)
    expect(#full > 200).toBe(true)
    openFriendPopup(h)

    click(h, F, "profileExport")
    local popup = h:popup("PERLINFINITY_PROFILE_EXPORT")
    expect(popup).toBeTruthy()
    local text = popup.EditBox:GetText()
    expect(#text).toBe(#full)
    h:clickPopup("PERLINFINITY_PROFILE_EXPORT", 1)

    F.Config:Reset("")
    h:advance(0.3)
    openFriendPopup(h)
    click(h, F, "profileImport")
    h:acceptPopup("PERLINFINITY_PROFILE_IMPORT", text)
    h:advance(0.3)
    expect(F.Profiles:Active()).toBe("Imported")
    expect(printed(h, "Added the profile Imported.")).toBe(true)
    expect(F.db.player.scale).toBe(1.3)
    expect(F.db.look.centerNames).toBe(true)
    expect(F.db.party.auras.buffSize).toBe(24)
    expect(playerScale(F)).toBe(1.3)

    -- A second import gets its own name.
    click(h, F, "profileImport")
    h:typeInPopup("PERLINFINITY_PROFILE_IMPORT", text)
    h:pressInPopup("PERLINFINITY_PROFILE_IMPORT", "ENTER")
    expect(F.Profiles:Active()).toBe("Imported 2")
  end)

  it("closes the export box with Escape", function()
    local h, F = boot()
    click(h, F, "profileExport")
    h:pressInPopup("PERLINFINITY_PROFILE_EXPORT", "ESCAPE")
    expect(h:popup("PERLINFINITY_PROFILE_EXPORT")).toBeNil()
  end)

  it("keeps the import box open when the text isn't a profile", function()
    local h, F = boot()
    click(h, F, "profileImport")
    h:acceptPopup("PERLINFINITY_PROFILE_IMPORT", "hello")
    expect(printed(h, "That doesn't look like a Perl Infinity profile.")).toBe(true)
    expect(h:popup("PERLINFINITY_PROFILE_IMPORT")).toBeTruthy()
    expect(#F.Profiles:List()).toBe(1)
    expect(F.Profiles:Active()).toBe("Default")

    -- Half a profile, as a cut-off copy would give.
    customize(F)
    local text = F.Profiles:Export("Default", false)
    h:acceptPopup("PERLINFINITY_PROFILE_IMPORT", text:sub(1, 77))
    expect(#F.Profiles:List()).toBe(1)
  end)

  it("turns down a profile from a newer version", function()
    local h, F = boot()
    local E = h.env.C_EncodingUtil
    local payload = E.SerializeCBOR({ schema = F.Config.SCHEMA + 1, settings = {} })
    local text = "PERLINFINITY1:" .. E.EncodeBase64(E.CompressString(payload, h.env.Enum.CompressionMethod.Deflate))
    click(h, F, "profileImport")
    h:acceptPopup("PERLINFINITY_PROFILE_IMPORT", text)
    expect(printed(h, "This profile is from a newer version of Perl Infinity.")).toBe(true)
    expect(#F.Profiles:List()).toBe(1)
  end)

  it("keeps only settings Perl Infinity knows, with the right kind of value", function()
    local h, F = boot()
    local E = h.env.C_EncodingUtil
    local payload = E.SerializeCBOR({
      schema = F.Config.SCHEMA,
      settings = { player = { scale = 1.3, enabled = "yes", madeUp = 5 }, nonsense = { a = 1 } },
    })
    local text = "PERLINFINITY1:" .. E.EncodeBase64(E.CompressString(payload, h.env.Enum.CompressionMethod.Deflate))
    click(h, F, "profileImport")
    h:acceptPopup("PERLINFINITY_PROFILE_IMPORT", text)
    h:advance(0.3)
    local imported = F.Config:DB().profiles.Imported
    expect(imported.player.scale).toBe(1.3)
    expect(imported.player.enabled).toBeNil()
    expect(imported.player.madeUp).toBeNil()
    expect(imported.nonsense).toBeNil()
    expect(F.db.player.enabled).toBe(true)
  end)

  it("never limits the export or import boxes", function()
    local h, F = boot()
    openFriendPopup(h)
    for _, which in ipairs({ "PERLINFINITY_PROFILE_EXPORT", "PERLINFINITY_PROFILE_IMPORT" }) do
      h.env.StaticPopup_Show(which)
      expect(h:popup(which).EditBox:GetMaxLetters()).toBe(0)
      h:clickPopup(which, 2)
    end
  end)

  -- The raid names list shares the same boxes. Field mode, where names read
  -- as plain text the way they do in the game outside special cases.
  it("shows a whole raid's names after another popup limited the box", function()
    local h, F = boot({ mode = "field" })
    h.world:setRaid(20)
    h:advance(0.5)
    openFriendPopup(h)
    F.RaidNames:Show()
    local names = raw(F.RaidNames:Text())
    expect(#names > 77).toBe(true)
    expect(#raw(h:popup("PERLINFINITY_RAID_NAMES").EditBox:GetText())).toBe(#names)
  end)
end)

describe("Perl Infinity profiles over time", function()
  it("keeps each character on its profile through a reload", function()
    local h, F = boot()
    F.Profiles:Create("Raiding")
    F.Config:DB().profiles.Raiding.player = { scale = 1.3 }
    pick(h, F, "profiles.active", "Raiding")
    local h2 = h:reload()
    h2:advance(0.5)
    local F2 = h2.env.PerlInfinity
    expect(F2.Profiles:Active()).toBe("Raiding")
    expect(F2.db.player.scale).toBe(1.3)
    expect(raw(F2.Movers:Get("player"):GetScale())).toBe(1.3)
  end)

  it("starts a new character on the profile chosen for new characters", function()
    local h, F = boot()
    F.Profiles:Create("Raiding")
    F.Config:DB().profiles.Raiding.player = { scale = 1.3 }
    pick(h, F, "profiles.newCharacters", "Raiding")
    expect(F.Profiles:Active()).toBe("Default")

    local saved = require("savedvars").parse(h:saveVariables())
    saved.PerlInfinityCharDB = nil
    local h2, F2 = boot({ savedVariables = saved })
    expect(F2.Profiles:Active()).toBe("Raiding")
    expect(F2.db.player.scale).toBe(1.3)
  end)

  it("moves a character whose profile was renamed elsewhere to the new-character profile", function()
    local _, F = boot({ savedVariables = {
      PerlInfinityDB = { profiles = { Default = {}, Main = { player = { scale = 1.3 } } }, newCharacterProfile = "Main" },
      PerlInfinityCharDB = { profile = "Gone" },
    } })
    expect(F.Profiles:Active()).toBe("Main")
    expect(F.db.player.scale).toBe(1.3)
  end)

  it("switches and lists profiles with /pinf profile", function()
    local h, F = boot()
    F.Profiles:Create("Raid team")
    h:slash("/pinf profile Raid team")
    expect(F.Profiles:Active()).toBe("Raid team")
    expect(printed(h, "Now using the Raid team profile.")).toBe(true)
    h:slash("/pinf profile")
    expect(printed(h, "Profiles: Default, Raid team. This character uses Raid team.")).toBe(true)
    h:slash("/pinf profile Nope")
    expect(printed(h, "There's no profile called Nope.")).toBe(true)
    expect(F.Profiles:Active()).toBe("Raid team")
  end)

  it("never moves your frames when you switch", function()
    local h, F = boot()
    local before = { F.Movers:Get("player"):GetPoint() }
    F.Profiles:Create("Raiding")
    pick(h, F, "profiles.active", "Raiding")
    local after = { F.Movers:Get("player"):GetPoint() }
    for i = 1, 5 do expect(raw(after[i])).toBe(raw(before[i])) end
  end)
end)
