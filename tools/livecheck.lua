-- tools/livecheck.lua
-- Does every setting work without a /reload? For each setting the options
-- window offers, this changes it while you play and compares the screen with
-- a fresh login that has the setting saved, then changes it back and compares
-- with a fresh login on defaults. It also switches, resets and copies whole
-- profiles. Any difference means something only applies after a reload (or
-- only before one).
--
-- Differences only in Blizzard's own frames are expected: Perl Infinity can
-- hide them right away, but bringing them back needs a reload (see
-- Blizzard/Hide.lua). Those are listed, not failed.
--
-- usage (from the repo root; `make livecheck` runs every job in parallel):
--   luajit tools/livecheck.lua --jobs                      list the jobs, one per line
--   luajit tools/livecheck.lua --scenario=raid --base=on --shard=2/8 [--out=DIR]
--   luajit tools/livecheck.lua --profiles --scenario=party [--out=DIR]
--   luajit tools/livecheck.lua --summary=DIR               sum up a run; exits 1 on failures
-- Add --only=PATTERN (a Lua pattern on the setting path) and --verbose anywhere.

package.path = "tests/harness/?.lua;tests/harness/stubs/?.lua;" .. package.path
local Harness = dofile("tests/harness/init.lua")
local Secret = Harness.Secret
local TOC = "PerlInfinity/PerlInfinity.toc"

local opts = {}
for _, a in ipairs(arg) do
  local k, v = a:match("^%-%-(%w+)=?(.*)$")
  if k then opts[k] = v ~= "" and v or true end
end

---------------------------------------------------------------------------
-- Jobs: scenario x base x shard. Raid boots are slow, so it gets more shards.
---------------------------------------------------------------------------
local SHARDS = { solo = 2, party = 3, raid = 8 }
local SCENARIO_ORDER = { "solo", "party", "raid" }

if opts.jobs then
  for _, base in ipairs({ "default", "on" }) do
    for _, sc in ipairs(SCENARIO_ORDER) do
      for i = 0, SHARDS[sc] - 1 do
        print(string.format("--scenario=%s --base=%s --shard=%d/%d", sc, base, i, SHARDS[sc]))
      end
    end
  end
  for _, sc in ipairs(SCENARIO_ORDER) do
    print("--profiles --scenario=" .. sc)
  end
  return
end

---------------------------------------------------------------------------
-- Summary of a finished run
---------------------------------------------------------------------------
if opts.summary then
  local dir = opts.summary
  local failures, expected, noise, done, jobs = {}, {}, {}, 0, 0
  local listing = io.popen('ls "' .. dir .. '"/*.txt 2>/dev/null')
  for file in listing:lines() do
    jobs = jobs + 1
    local current
    for line in io.lines(file) do
      if line:match("^FAIL ") or line:match("^NOISE ") then
        current = line
        local list = line:match("^FAIL ") and failures or noise
        list[#list + 1] = { line }
      elseif line:match("^RELOAD ") then
        current = nil
        expected[line:gsub("^RELOAD ", ""):gsub(" %[.*$", "")] = true
      elseif line:match("^done:") then
        done = done + 1
      elseif current and line:match("^    ") then
        local list = current:match("^FAIL ") and failures or noise
        table.insert(list[#list], line)
      end
    end
  end
  listing:close()
  local names = {}
  for name in pairs(expected) do names[#names + 1] = name end
  table.sort(names)
  if #names > 0 then
    print("Needs a reload by design (Blizzard's own frames come back only after one):")
    for _, name in ipairs(names) do print("  " .. name) end
    print("")
  end
  for _, group in ipairs({ noise, failures }) do
    for _, entry in ipairs(group) do
      for i, line in ipairs(entry) do
        if i <= 9 or opts.verbose then print(line) end
      end
    end
  end
  print(string.format("livecheck: %d of %d jobs finished, %d failures, %d noisy scenarios, %d expected", done, jobs,
    #failures, #noise, #names))
  os.exit((#failures + #noise > 0 or done < jobs or jobs == 0) and 1 or 0)
end

---------------------------------------------------------------------------
-- The world each comparison runs in
---------------------------------------------------------------------------
local function hostile()
  return { name = "Defias Thug", npc = true, reaction = 2, level = 18, health = 600, maxHealth = 900,
    classification = "elite", creatureType = "Humanoid" }
end

local SCENARIOS = {
  solo = function(h)
    h.world:summonPet({ name = "Wolf" })
    h.world:setTarget(hostile())
    h.world:setFocus({ name = "Friendo", class = "PRIEST", level = 60, reaction = 5, isPlayer = true })
    h.world:applyAura("target", { name = "Rend", duration = 15, sourceUnit = "player", harmful = true })
    h.world:applyAura("player", { name = "Mark of the Wild", duration = 1800, sourceUnit = "player" })
    h.world:setComboPoints(3)
  end,
  party = function(h)
    h.world:setParty({ { class = "PRIEST" }, { class = "WARRIOR", role = "TANK" }, { class = "HUNTER" } })
    h:advance(0.2)
    h.world:summonPet({ name = "Cat" }, "party3")
    h.world:setTarget(hostile(), "party2")
    h.world:setTarget(hostile())
    h.world:applyAura("party1", { name = "Power Word: Fortitude", duration = 1800, sourceUnit = "party1" })
    h.world:applyAura("party1", { name = "Rejuvenation", duration = 12, sourceUnit = "player" })
    h.world:applyAura("party2", { name = "Poison", duration = 30, harmful = true, dispelName = "Poison" })
  end,
  raid = function(h)
    h.world:setRaid(15, function(i) if i == 2 then return { raidRole = "MAINTANK", role = "TANK" } end end)
    h:advance(0.2)
    h.world:setTarget(hostile())
    h.world:applyAura("raid3", { name = "Poison", duration = 30, harmful = true, dispelName = "Poison" })
    h.world:applyAura("raid4", { name = "Rejuvenation", duration = 12, sourceUnit = "player" })
  end,
}

-- Switches that are off by default. With --base=on both runs start with them
-- on, so the settings under them have something to show.
local BASE_ON = {
  "tanks.enabled", "healers.enabled", "small.targettargettarget.enabled",
  "player.auras.buffs", "player.auras.debuffs", "player.auras.weaponEnchants",
  "player.xpBar", "player.repBar", "pet.xpBar", "highlight.hotBars", "highlight.healing",
  "highlight.target", "raid.bossDebuff", "range.icon",
}

---------------------------------------------------------------------------
-- Snapshot: every visible widget Perl Infinity made, one sorted line each.
-- Labels use the field a widget is stored under, never a creation index,
-- so two runs that build things in a different order still line up.
---------------------------------------------------------------------------
local function fmt(n) return n and string.format("%.1f", Secret.raw(n)) or "?" end
local function rgba(c) local t = {}; for i = 1, 4 do t[i] = fmt(c[i] or 1) end; return table.concat(t, ",") end
local DRAWN_FRAMES = { StatusBar = true, Model = true, PlayerModel = true, Cooldown = true }

local function snapshot(h)
  local W = h.widgets
  local lines = {}
  local function label(o, parentPath)
    local s = W.state[o]
    local key
    if s.parent then
      for k, v in pairs(s.parent) do
        if v == o and type(k) == "string" and (not key or k < key) then key = k end
      end
    end
    return parentPath .. "/" .. (key or s.name or s.type)
  end
  local function visit(o, path, parentAlpha)
    local s = W.state[o]
    if not s.shown then return end
    local alpha = (parentAlpha or 1) * (Secret.raw(s.alpha) or 1)
    if alpha < 0.001 then return end
    -- Empty text and bare containers draw nothing; their children still count.
    local drawn = not (s.type == "FontString" and (s.text == nil or s.text == ""))
      and not (s.kind == "frame" and not s.backdropColor and not s.barColor and not DRAWN_FRAMES[s.type])
    if drawn then
      local r = W.rect(o)
      local parts = { path, s.type, r and (fmt(r[1]) .. "," .. fmt(r[2]) .. "," .. fmt(r[3]) .. "," .. fmt(r[4])) or "unanchored" }
      if s.layer then parts[#parts + 1] = "layer=" .. s.layer end
      if s.texture then parts[#parts + 1] = "tex=" .. tostring(s.texture) end
      if s.atlas then parts[#parts + 1] = "atlas=" .. tostring(s.atlas) end
      if s.color then parts[#parts + 1] = "color=" .. rgba(s.color) end
      if s.vertexColor then parts[#parts + 1] = "vc=" .. rgba(s.vertexColor) end
      if s.barColor then parts[#parts + 1] = "bar=" .. rgba(s.barColor) end
      if s.textColor then parts[#parts + 1] = "tc=" .. rgba(s.textColor) end
      if s.backdropColor then parts[#parts + 1] = "bg=" .. rgba(s.backdropColor) end
      if s.backdropBorderColor then parts[#parts + 1] = "border=" .. rgba(s.backdropBorderColor) end
      if s.gradient then parts[#parts + 1] = "grad=" .. tostring(s.gradient[1]) end
      if s.type == "FontString" then
        parts[#parts + 1] = "size=" .. fmt(s.fontSize)
        -- Where the text really sits; see the FontString model in the harness.
        parts[#parts + 1] = "justify=" .. tostring(s.laidOutJustifyH or s.justifyH)
        parts[#parts + 1] = "text=" .. string.format("%q", tostring(s.text))
      end
      if s.value then parts[#parts + 1] = string.format("value=%s/%s..%s", fmt(s.value), fmt(s.min), fmt(s.max)) end
      if s.alpha ~= 1 then parts[#parts + 1] = "alpha=" .. fmt(s.alpha) end
      if s.scale and s.scale ~= 1 then parts[#parts + 1] = "scale=" .. fmt(s.scale) end
      if s.blendMode and s.blendMode ~= "BLEND" then parts[#parts + 1] = "blend=" .. tostring(s.blendMode) end
      lines[#lines + 1] = table.concat(parts, " ")
    end
    for _, region in ipairs(s.regions) do visit(region, label(region, path), alpha) end
    for _, child in ipairs(s.children) do visit(child, label(child, path), alpha) end
  end
  for _, obj in ipairs(W.all) do
    local st = W.state[obj]
    if st and st.kind == "frame" and st.parent == W.UIParent and not st.harnessInternal and st.name ~= "EditModeManagerFrame" then
      if st.blizzard then
        lines[#lines + 1] = "BLIZZARD " .. tostring(st.name) .. " shown=" .. tostring(W.isVisible(obj))
      else
        visit(obj, st.name or (st.type .. "@root"))
      end
    end
  end
  table.sort(lines)
  return lines
end

local function diff(a, b)
  local ca, cb = {}, {}
  for _, l in ipairs(a) do ca[l] = (ca[l] or 0) + 1 end
  for _, l in ipairs(b) do cb[l] = (cb[l] or 0) + 1 end
  local onlyA, onlyB = {}, {}
  for l, n in pairs(ca) do if (cb[l] or 0) < n then onlyA[#onlyA + 1] = l end end
  for l, n in pairs(cb) do if (ca[l] or 0) < n then onlyB[#onlyB + 1] = l end end
  table.sort(onlyA)
  table.sort(onlyB)
  return onlyA, onlyB
end

---------------------------------------------------------------------------
-- Booting with a given profile
---------------------------------------------------------------------------
local function setPath(t, path, value)
  local keys = {}
  for k in path:gmatch("[^%.]+") do keys[#keys + 1] = k end
  for i = 1, #keys - 1 do
    t[keys[i]] = t[keys[i]] or {}
    t = t[keys[i]]
  end
  t[keys[#keys]] = value
  return t
end

local function deepCopy(t)
  if type(t) ~= "table" then return t end
  local r = {}
  for k, v in pairs(t) do r[k] = deepCopy(v) end
  return r
end

local function saved(profiles, active)
  return {
    PerlInfinityDB = { profiles = profiles, newCharacterProfile = "Default" },
    PerlInfinityCharDB = { profile = active or "Default" },
  }
end

local function boot(sv)
  local h = Harness.new({ mode = "open" })
  h.allowProblems = true
  h:loadToc(TOC)
  h:login(sv)
  h:advance(0.5)
  return h
end

-- Boots, sets the scene, optionally does something live, and snapshots.
local function run(scenario, sv, action)
  local h = boot(sv)
  SCENARIOS[scenario](h)
  h:advance(1)
  if action then action(h.env.PerlInfinity) end
  h:advance(1)
  return snapshot(h), h:problems()
end

---------------------------------------------------------------------------
-- Which settings to try, and which values
---------------------------------------------------------------------------
local probe = boot()
local F = probe.env.PerlInfinity

-- Settings the options window offers. Others (like player.power) can't be
-- changed in the game, so they're left out.
local rows, paths = {}, {}
for _, page in ipairs(F.OptionPages.list) do
  for _, row in ipairs(page.rows) do
    if row.path and F.Config:GetDefault(row.path) ~= nil and not rows[row.path] then
      rows[row.path] = row
      paths[#paths + 1] = row.path
    end
  end
end
table.sort(paths)

local function alternatives(path)
  local def = F.Config:GetDefault(path)
  local row = rows[path]
  local out = {}
  if type(def) == "boolean" then
    out[1] = not def
  elseif row.type == "dropdown" then
    local choices = type(row.choices) == "function" and row.choices() or row.choices
    for _, c in ipairs(choices or {}) do
      local v = type(c) == "table" and c.value or c
      if v ~= def then out[#out + 1] = v end
    end
  elseif row.type == "slider" then
    out[1] = def == row.max and row.min or row.max
    local mid = row.min + math.floor(((row.max - row.min) / 2) / row.step) * row.step
    if mid ~= def and mid ~= out[1] then out[2] = mid end
  elseif row.type == "multi" then
    out[1], out[2] = 0, 1
  elseif type(def) == "string" and def:match("^%x%x%x%x%x%x%x%x$") then
    out[1] = "ff336699"
  end
  return out
end

local function baseProfile(base)
  local profile = {}
  if base == "on" then
    for _, path in ipairs(BASE_ON) do setPath(profile, path, true) end
  end
  return profile
end

---------------------------------------------------------------------------
-- Reporting. RELOAD lines are expected (Blizzard frames only); FAIL lines
-- are not. `summary` reads these back.
---------------------------------------------------------------------------
local out = io.stdout
local function emit(line) out:write(line, "\n") end

local function onlyBlizzard(list)
  for _, l in ipairs(list) do
    if not l:match("^BLIZZARD ") then return false end
  end
  return true
end

local function report(tag, what, onlyLive, onlyFresh, problems)
  if #onlyLive + #onlyFresh + #problems == 0 then return false end
  if #problems == 0 and onlyBlizzard(onlyLive) and onlyBlizzard(onlyFresh) then
    emit("RELOAD " .. tag .. " " .. what)
    return false
  end
  emit(string.format("FAIL %s %s: %d only live, %d only after a reload%s", tag, what, #onlyLive, #onlyFresh,
    #problems > 0 and (", " .. #problems .. " Lua problems") or ""))
  local limit = opts.verbose and 60 or 8
  for i = 1, math.min(limit, #problems) do emit("    problem " .. problems[i]) end
  for i = 1, math.min(limit, #onlyLive) do emit("    live   " .. onlyLive[i]) end
  for i = 1, math.min(limit, #onlyFresh) do emit("    reload " .. onlyFresh[i]) end
  return true
end

local scenario = opts.scenario or "solo"
assert(SCENARIOS[scenario], "--scenario must be solo, party or raid")
local base = opts.base or "default"
assert(base == "default" or base == "on", "--base must be default or on")

if opts.out then
  local name = opts.profiles and ("profiles-" .. scenario)
    or string.format("%s-%s-%s", base, scenario, (opts.shard or "all"):gsub("/", "of"))
  out = assert(io.open(opts.out .. "/" .. name .. ".txt", "w"))
end

-- Two identical runs must match, or every comparison below means nothing.
do
  local profiles = { Default = baseProfile(base) }
  local a = run(scenario, saved(deepCopy(profiles)))
  local b = run(scenario, saved(deepCopy(profiles)))
  local x, y = diff(a, b)
  if #x + #y > 0 then
    emit(string.format("NOISE [%s, %s]: identical runs differ in %d lines", scenario, base, #x + #y))
    for i = 1, math.min(8, #x) do emit("    first  " .. x[i]) end
    for i = 1, math.min(8, #y) do emit("    second " .. y[i]) end
  end
end

local failures = 0

if opts.profiles then
  -- Whole profiles: one with every setting changed, one with only the look.
  local everything, look = {}, {}
  for _, path in ipairs(paths) do
    local alt = alternatives(path)[1]
    if alt ~= nil and not path:match("%.enabled$") then
      setPath(everything, path, alt)
      if path:match("^look%.") then setPath(look, path, alt) end
    end
  end
  for _, other in ipairs({ { "everything", everything }, { "look", look } }) do
    local name, settings = other[1], other[2]
    local function profiles() return { Default = {}, Other = deepCopy(settings) } end
    local where = string.format("the %s profile [%s]", name, scenario)
    local live, p = run(scenario, saved(profiles()), function(P) P.Profiles:Use("Other") end)
    local x, y = diff(live, (run(scenario, saved(profiles(), "Other"))))
    if report("switch to", where, x, y, p) then failures = failures + 1 end

    live, p = run(scenario, saved(profiles(), "Other"), function(P) P.Profiles:Use("Default") end)
    x, y = diff(live, (run(scenario, saved(profiles()))))
    if report("switch back from", where, x, y, p) then failures = failures + 1 end

    live, p = run(scenario, saved(profiles(), "Other"), function(P) P.Profiles:Reset("Other") end)
    x, y = diff(live, (run(scenario, saved({ Default = {}, Other = {} }, "Other"))))
    if report("reset", where, x, y, p) then failures = failures + 1 end

    live, p = run(scenario, saved(profiles()), function(P) P.Profiles:Copy("Other", "Default") end)
    x, y = diff(live, (run(scenario, saved(profiles(), "Other"))))
    if report("copy into", where, x, y, p) then failures = failures + 1 end
  end
  emit(string.format("done: profiles [%s], %d failures", scenario, failures))
else
  local list = {}
  for _, path in ipairs(paths) do
    local skip = opts.only and not path:find(opts.only)
    if base == "on" then
      for _, b in ipairs(BASE_ON) do if b == path then skip = true end end
    end
    if not skip then list[#list + 1] = path end
  end
  if opts.shard then
    local i, n = opts.shard:match("^(%d+)/(%d+)$")
    i, n = tonumber(i), tonumber(n)
    local kept = {}
    for index, path in ipairs(list) do
      if (index - 1) % n == i then kept[#kept + 1] = path end
    end
    list = kept
  end
  for _, path in ipairs(list) do
    local def = F.Config:GetDefault(path)
    for _, value in ipairs(alternatives(path)) do
      local where = string.format("%s = %s [%s, %s base]", path, tostring(value), scenario, base)
      -- Change it live, then compare with a login that has it saved.
      local withValue = baseProfile(base)
      setPath(withValue, path, value)
      local live, p = run(scenario, saved({ Default = baseProfile(base) }), function(P) P.Config:Set(path, value) end)
      local x, y = diff(live, (run(scenario, saved({ Default = deepCopy(withValue) }))))
      if report("change", where, x, y, p) then failures = failures + 1 end
      -- And back again, compared with a login on the base profile.
      where = string.format("%s back to %s [%s, %s base]", path, tostring(def), scenario, base)
      live, p = run(scenario, saved({ Default = deepCopy(withValue) }), function(P) P.Config:Set(path, def) end)
      x, y = diff(live, (run(scenario, saved({ Default = baseProfile(base) }))))
      if report("undo", where, x, y, p) then failures = failures + 1 end
    end
  end
  emit(string.format("done: %d settings [%s, %s base], %d failures", #list, scenario, base, failures))
end

if out ~= io.stdout then out:close() end
os.exit(failures > 0 and 1 or 0)
