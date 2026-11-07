-- tools/readsv.lua
-- Reads Perl Infinity's account SavedVariables (PerlInfinity.lua) and prints a report of PerlInfinityLog:
-- errors, blocked actions, self-test steps, secrecy matrix, CPU, census, manifest,
-- screenshots and a diff against the previous session. Every field is optional.
--
-- usage: luajit tools/readsv.lua [path] [--previous=path] [--all] [--json] [--screenshots=dir]
-- module: local R = dofile("tools/readsv.lua"); local data = R.load(path); print(R.report(data, {}))

local R = {}
R.DEFAULT_PATH = os.getenv("PERLINFINITY_SV") or "PerlInfinity.lua"
R.SCREENSHOT_DIR = "/Applications/World of Warcraft/_classic_beta_/Screenshots"
local MAX_BYTES = 20 * 1024 * 1024
local WIDTH = 120

---------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------
local function istable(v) return type(v) == "table" end
local function count(t) local n = 0; if istable(t) then for _ in pairs(t) do n = n + 1 end end; return n end
local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
    return type(a) < type(b)
  end)
  return keys
end
local function clip(s, n)
  s = tostring(s):gsub("[\r\n\t]", " ")
  if #s > n then return s:sub(1, math.max(n - 3, 1)) .. "..." end
  return s
end
local function pad(s, n) s = clip(s, n); return s .. string.rep(" ", n - #s) end
local function maxLen(list, cap) local m = 0; for _, s in ipairs(list) do m = math.max(m, #tostring(s)) end; return math.min(m, cap) end
local function fmtTime(v)
  if type(v) == "number" then
    if v > 1e9 then return os.date("%Y-%m-%d %H:%M:%S", math.floor(v)) end
    return string.format("t+%.1fs", v)
  end
  return v == nil and "?" or tostring(v)
end
local function fmtNum(v)
  if type(v) ~= "number" then return tostring(v) end
  if v == math.floor(v) and math.abs(v) < 1e12 then return string.format("%d", v) end
  return string.format("%.4g", v)
end
local function flat(v)
  if not istable(v) then return tostring(v) end
  local parts = {}
  for _, k in ipairs(sortedKeys(v)) do
    local x = v[k]
    if not istable(x) then parts[#parts + 1] = (type(k) == "number" and "" or (tostring(k) .. "=")) .. tostring(x) end
  end
  return table.concat(parts, "; ")
end
local function shellQuote(s) return '"' .. tostring(s):gsub('(["\\$`])', "\\%1") .. '"' end

---------------------------------------------------------------------------
-- Loading (empty sandbox, size cap, instruction cap)
---------------------------------------------------------------------------
local function fileInfo(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local size = f:seek("end")
  f:close()
  local mtime
  local p = io.popen("stat -f %m " .. shellQuote(path) .. " 2>/dev/null || stat -c %Y " .. shellQuote(path) .. " 2>/dev/null")
  if p then mtime = tonumber(p:read("*l") or ""); p:close() end
  return size, mtime
end

function R.load(path)
  local size, mtime = fileInfo(path)
  if not size then return nil, "missing" end
  if size > MAX_BYTES then
    return nil, string.format("the file is %.1f MB, more than the 20 MB this tool reads", size / 1048576)
  end
  local fn, err = loadfile(path)
  if not fn then return nil, "the file isn't valid Lua: " .. tostring(err) end
  local box = {}
  setfenv(fn, box)
  local jit = rawget(_G, "jit")
  if jit then jit.off(fn) end
  debug.sethook(function() error("the file ran too long to be saved variables", 2) end, "", 5e7)
  local ok, e = pcall(fn)
  debug.sethook()
  if not ok then return nil, "the file stopped loading partway: " .. tostring(e) end
  return { path = path, size = size, mtime = mtime, rawLog = box.PerlInfinityLog,
    log = istable(box.PerlInfinityLog) and box.PerlInfinityLog or {}, db = box.PerlInfinityDB }
end

local function sessionsOf(log)
  local s = log.sessions
  local list = {}
  if not istable(s) then return list end
  for _, k in ipairs(sortedKeys(s)) do if istable(s[k]) then list[#list + 1] = s[k] end end
  local timed = #list > 0
  for _, x in ipairs(list) do if type(x.time or x.start or x.started) ~= "number" then timed = false end end
  if timed then
    table.sort(list, function(a, b) return (a.time or a.start or a.started) < (b.time or b.start or b.started) end)
  end
  return list
end

---------------------------------------------------------------------------
-- Errors and blocked actions
---------------------------------------------------------------------------
local function firstLine(s) return (tostring(s or ""):match("^[^\n]*")) end
local function trimPath(line)
  line = tostring(line):gsub("\\", "/"):gsub('%[string "@?([^"]*)"%]', "%1"):gsub("^%s+", "")
  local i = line:find("AddOns/", 1, true)
  if i then line = line:sub(i) end
  return line
end
local function stackLines(stack, n)
  local r = {}
  if istable(stack) then stack = table.concat(stack, "\n") end
  if type(stack) ~= "string" then return r end
  for line in stack:gmatch("[^\n]+") do
    line = trimPath(line)
    if line ~= "" and not line:match("^%[C%]") and not line:match("^stack traceback") then r[#r + 1] = line end
    if #r >= n then break end
  end
  return r
end

-- Deduplicate by first message line + first stack line; sorted by count.
local function normEntries(map, isBlocked)
  local out, byKey = {}, {}
  if not istable(map) then return out, byKey end
  for k, e in pairs(map) do
    if type(e) == "string" then e = { msg = e } end
    if istable(e) then
      local msg = e.msg or e.message or e.text or e.fn or e["function"] or (type(k) == "string" and k) or "?"
      local stack = stackLines(e.stack, 3)
      local kind = e.kind or e.category
      local key = (isBlocked and (tostring(kind) .. "|" .. tostring(e.fn or msg)) or firstLine(msg)) .. "|" .. (stack[1] or "")
      local n = tonumber(e.count) or 1
      local first, last = e.first or e.time, e.last or e.time
      local x = byKey[key]
      if x then
        x.count = x.count + n
        if type(first) == "number" and (type(x.first) ~= "number" or first < x.first) then x.first = first end
        if type(last) == "number" and (type(x.last) ~= "number" or last > x.last) then x.last = last end
      else
        x = { key = key, msg = trimPath(firstLine(msg)), fn = e.fn, kind = kind, stack = stack, count = n, first = first, last = last, ctx = e.ctx }
        byKey[key] = x
        out[#out + 1] = x
      end
    end
  end
  table.sort(out, function(a, b) if a.count ~= b.count then return a.count > b.count end return a.msg < b.msg end)
  return out, byKey
end

local function ctxSummary(ctx)
  if not istable(ctx) then return ctx ~= nil and tostring(ctx) or "" end
  local parts = {}
  for _, k in ipairs(sortedKeys(ctx)) do
    local v = ctx[k]
    if istable(v) then
      local items = {}
      for _, kk in ipairs(sortedKeys(v)) do
        local vv = v[kk]
        if vv == true then items[#items + 1] = tostring(kk)
        elseif not istable(vv) and vv ~= false then items[#items + 1] = (type(kk) == "number" and "" or (tostring(kk) .. ":")) .. tostring(vv) end
      end
      v = table.concat(items, ",")
    end
    if v ~= false and v ~= "" and v ~= nil then parts[#parts + 1] = tostring(k) .. "=" .. tostring(v) end
  end
  return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Self-test steps
---------------------------------------------------------------------------
local function stepsOf(st)
  local src = istable(st) and (st.steps or st.results or st.phases) or st
  local out = {}
  if not istable(src) then return out end
  local keys = {}
  if #src > 0 then for i = 1, #src do keys[i] = i end else keys = sortedKeys(src) end
  for _, k in ipairs(keys) do
    local v = src[k]
    local name, status, note
    if istable(v) then
      name = v.name or v.label or v.step or (type(k) == "string" and k) or ("step " .. k)
      if v.ok == true or v.passed == true or v.status == "ok" then status = "ok"
      elseif v.ok == false or v.status == "failed" or v.status == "fail" or v.error or v.err then status = "failed"
      elseif v.skipped then status = "skipped"
      else status = v.status and tostring(v.status) or "done" end
      note = v.notes or v.note or v.error or v.err or v.reason or v.msg
      if istable(note) then note = flat(note) end
    else
      name = type(k) == "string" and k or ("step " .. k)
      status = v == true and "ok" or (v == false and "failed" or tostring(v))
    end
    out[#out + 1] = { name = tostring(name), status = status, note = note }
  end
  return out
end

---------------------------------------------------------------------------
-- Secrecy matrix: accepts [context][unit][api], [probe][context] and [context][probe]
---------------------------------------------------------------------------
local function abbrev(v)
  if v == nil then return "." end
  if type(v) ~= "string" then return "?" end
  local s = v:lower()
  if s == "s" or s:match("^secret") then return "S"
  elseif s == "n" or s == "nil" then return "N"
  elseif s:match("^p") then return "P"
  elseif s:match("^e") then return "E"
  elseif s:match("^skip") then return "-" end
  return "?"
end
local function apiLike(k) k = tostring(k); return k:find("[%.:%(]") ~= nil or k:match("^[A-Z]") ~= nil end

local function normMatrix(m)
  if not istable(m) then return nil end
  local cells, rowSet, colSet = {}, {}, {}
  local function put(row, col, v)
    cells[row] = cells[row] or {}
    cells[row][col] = v
    rowSet[row], colSet[col] = true, true
  end
  local l1, l1api, l2, l2api = 0, 0, 0, 0
  for k1, t in pairs(m) do
    if istable(t) then
      l1 = l1 + 1
      if apiLike(k1) then l1api = l1api + 1 end
      for k2, v in pairs(t) do
        if istable(v) then -- parity shape: [context][unit][api]
          for k3, x in pairs(v) do if not istable(x) then put(tostring(k3) .. "(" .. tostring(k2) .. ")", tostring(k1), x) end end
        else
          l2 = l2 + 1
          if apiLike(k2) then l2api = l2api + 1 end
        end
      end
    end
  end
  local probeFirst = (l1api / math.max(l1, 1)) >= (l2api / math.max(l2, 1))
  for k1, t in pairs(m) do
    if istable(t) then
      for k2, v in pairs(t) do
        if not istable(v) then
          if probeFirst then put(tostring(k1), tostring(k2), v) else put(tostring(k2), tostring(k1), v) end
        end
      end
    end
  end
  local rows, cols = sortedKeys(rowSet), sortedKeys(colSet)
  return rows, cols, cells
end

local function renderMatrix(out, m)
  local rows, cols, cells = normMatrix(m)
  if not rows or #rows == 0 then out[#out + 1] = "  (nothing recorded)"; return end
  local rowW = math.max(maxLen(rows, 36), 6)
  local letters = maxLen(cols, 99) > 10
  local colW = letters and 3 or math.max(maxLen(cols, 10), 3)
  if letters then
    local key = {}
    for i, c in ipairs(cols) do key[#key + 1] = string.char(64 + ((i - 1) % 26) + 1) .. "=" .. c end
    out[#out + 1] = "  columns: " .. table.concat(key, ", ")
  end
  local per = math.max(1, math.floor((WIDTH - rowW - 4) / (colW + 1)))
  local tally, errs = { S = 0, P = 0, N = 0, E = 0 }, {}
  for b = 1, #cols, per do
    local head = "  " .. pad("", rowW) .. "  "
    for i = b, math.min(b + per - 1, #cols) do
      head = head .. pad(letters and string.char(64 + ((i - 1) % 26) + 1) or cols[i], colW) .. " "
    end
    out[#out + 1] = head
    for _, r in ipairs(rows) do
      local line = "  " .. pad(r, rowW) .. "  "
      for i = b, math.min(b + per - 1, #cols) do
        local v = cells[r][cols[i]]
        local a = abbrev(v)
        if tally[a] then tally[a] = tally[a] + 1 end
        if a == "E" then errs[#errs + 1] = r .. " @ " .. cols[i] .. ": " .. tostring(v):gsub("^[Ee][%w]*:?", "") end
        line = line .. pad(a, colW) .. " "
      end
      out[#out + 1] = line
    end
  end
  out[#out + 1] = string.format("  S secret %d, P plain %d, N nil %d, E error %d  (. = not probed, - = skipped)",
    tally.S, tally.P, tally.N, tally.E)
  for i, e in ipairs(errs) do
    if i > 10 then out[#out + 1] = "  ... " .. (#errs - 10) .. " more errors"; break end
    out[#out + 1] = "  error: " .. clip(e, WIDTH - 9)
  end
end

---------------------------------------------------------------------------
-- Perf, manifest, screenshots
---------------------------------------------------------------------------
local function pick(t, ...)
  for i = 1, select("#", ...) do local v = t[select(i, ...)]; if v ~= nil then return v end end
end

local function renderPerf(out, perf)
  if not istable(perf) then out[#out + 1] = "  (nothing recorded)"; return end
  local micro = perf.micro or perf.bench
  if istable(micro) then
    out[#out + 1] = "  " .. pad("hot path", 36) .. pad("ms per call", 14) .. "bytes per call"
    for _, k in ipairs(sortedKeys(micro)) do
      local v = micro[k]
      local ms, bytes
      if istable(v) then ms, bytes = pick(v, "elapsedMilliseconds", "ms", "elapsed"), pick(v, "allocatedBytes", "bytes", "alloc")
      else ms = v end
      out[#out + 1] = "  " .. pad(k, 36) .. pad(ms ~= nil and fmtNum(ms) or "?", 14) .. (bytes ~= nil and fmtNum(bytes) or "?")
    end
  end
  for _, k in ipairs(sortedKeys(perf)) do
    local v = perf[k]
    if not istable(v) then out[#out + 1] = "  " .. pad(k, 36) .. fmtNum(v)
    elseif k ~= "micro" and k ~= "bench" and k ~= "samples" and k ~= "topK" then
      out[#out + 1] = "  " .. pad(k, 36) .. clip(flat(v), WIDTH - 40)
    end
  end
  if istable(perf.samples) and #perf.samples > 0 then
    local vals = {}
    for _, s in ipairs(perf.samples) do
      local v = istable(s) and pick(s, "recentAverageTime", "RecentAverageTime", "recent", "ms", "value") or s
      if type(v) == "number" then vals[#vals + 1] = v end
    end
    table.sort(vals)
    if #vals > 0 then
      out[#out + 1] = string.format("  samples: %d, max %s ms, p95 %s ms", #vals, fmtNum(vals[#vals]),
        fmtNum(vals[math.max(1, math.ceil(#vals * 0.95))]))
    else
      out[#out + 1] = "  samples: " .. #perf.samples
    end
  end
  if istable(perf.topK) then
    local names = {}
    for i, e in ipairs(perf.topK) do
      if i > 5 then break end
      names[#names + 1] = istable(e) and (tostring(pick(e, "name", "addon", 1)) .. " " .. fmtNum(pick(e, "value", "ms", 2) or "")) or tostring(e)
    end
    out[#out + 1] = "  top addons: " .. table.concat(names, ", ")
  end
end

local function renderMissing(out, missing)
  if not istable(missing) or count(missing) == 0 then out[#out + 1] = "  Nothing missing. Every referenced API, event, template and atlas exists."; return end
  if #missing > 0 then
    out[#out + 1] = "  " .. #missing .. " missing: " .. clip(table.concat(missing, ", "), WIDTH - 20)
    return
  end
  for _, k in ipairs(sortedKeys(missing)) do
    local v = missing[k]
    local list = {}
    if istable(v) then
      for _, kk in ipairs(sortedKeys(v)) do list[#list + 1] = type(kk) == "number" and tostring(v[kk]) or tostring(kk) end
    else list[1] = tostring(v) end
    out[#out + 1] = "  " .. pad(k .. " (" .. #list .. ")", 22) .. clip(table.concat(list, ", "), WIDTH - 26)
  end
end

local function listScreenshotFiles(dir)
  local files = {}
  local p = io.popen("ls " .. shellQuote(dir) .. " 2>/dev/null")
  if not p then return files end
  for name in p:lines() do
    local mo, d, y, hh, mi, ss = name:match("^WoWScrnShot_(%d%d)(%d%d)(%d%d)_(%d%d)(%d%d)(%d%d)%.jpg$")
    if mo then
      files[#files + 1] = { path = dir .. "/" .. name, time = os.time({ year = 2000 + tonumber(y), month = tonumber(mo),
        day = tonumber(d), hour = tonumber(hh), min = tonumber(mi), sec = tonumber(ss) }) }
    end
  end
  p:close()
  return files
end

-- Findings in the order they happened, those with a stack first: a stack is
-- the write that caused it, and the rest are usually what spread from there.
local function renderTaintWatch(out, watch)
  out[#out + 1] = "  watch is " .. (watch.on and "on" or "off")
  for _, run in ipairs(watch.runs) do
    local names = {}
    for name in pairs(istable(run.findings) and run.findings or {}) do names[#names + 1] = name end
    table.sort(names, function(a, b)
      local fa, fb = run.findings[a], run.findings[b]
      if (fa.stack ~= nil) ~= (fb.stack ~= nil) then return fa.stack ~= nil end
      if tostring(fa.time) ~= tostring(fb.time) then return tostring(fa.time) < tostring(fb.time) end
      return a < b
    end)
    out[#out + 1] = string.format("  run started %s: %d found, %d dropped", tostring(run.started), #names, tonumber(run.dropped) or 0)
    for _, name in ipairs(names) do
      local f = run.findings[name]
      out[#out + 1] = string.format("    %s  %s  by %s  level %s, %s%s", tostring(f.time), name, tostring(f.by), tostring(f.level), tostring(f.group), f.combat and ", in combat" or "")
      if f.mouse or f.open then out[#out + 1] = string.format("      mouse: %s  open: %s", tostring(f.mouse), tostring(f.open)) end
      if f.stack then
        out[#out + 1] = "      trail: " .. tostring(f.crumbs)
        for line in tostring(f.stack):gmatch("[^\n]+") do out[#out + 1] = "      " .. line end
      end
    end
  end
end

local function renderAuraFrames(out, state)
  out[#out + 1] = string.format("  in combat %s, auras secret %s, layouts waiting %s, builds waiting %s",
    tostring(state.combat), tostring(state.aurasSecret), tostring(state.layoutsWaiting), tostring(state.buildsWaiting))
  for _, f in ipairs(istable(state.frames) and state.frames or {}) do
    local icons = {}
    for key, count in pairs(istable(f.icons) and f.icons or {}) do icons[#icons + 1] = key .. "=" .. tostring(count) end
    table.sort(icons)
    out[#out + 1] = string.format("  %s %s: shown %s, visible %s, needs setup %s, groups wanted %s, waiting for combat %s",
      tostring(f.kind), tostring(f.unit), tostring(f.shown), tostring(f.visible), tostring(f.stale), tostring(f.groupsWanted), tostring(f.waitingForCombat))
    out[#out + 1] = string.format("    game reports buff %s, debuff %s", tostring(f.gameHasBuff), tostring(f.gameHasDebuff))
    out[#out + 1] = string.format("    icons: anchors %s, unit %s, enabled %s, visible %s, counts %s",
      tostring(f.anchors), tostring(f.containerUnit), tostring(f.enabled), tostring(f.containerVisible), table.concat(icons, "; "))
    if istable(f.auras) then
      for _, name in ipairs({ "yourBuffs", "otherBuffs", "debuffs" }) do
        local list = f.auras[name]
        out[#out + 1] = "    " .. name .. ": " .. (istable(list) and (#list > 0 and table.concat(list, "; ") or "none") or tostring(list))
      end
    end
  end
end

local function renderScreenshots(out, shots, dir)
  if not istable(shots) or #shots == 0 then out[#out + 1] = "  (none taken)"; return end
  local files = listScreenshotFiles(dir)
  for _, s in ipairs(shots) do
    local t = istable(s) and (s.time or s[1]) or nil
    local label = istable(s) and (s.label or s[2]) or tostring(s)
    local match
    if type(t) == "number" and t > 1e9 then
      local best
      for _, f in ipairs(files) do
        local d = math.abs(f.time - t)
        if d <= 60 and (not best or d < best) then best, match = d, f.path end
      end
    end
    out[#out + 1] = "  " .. pad(fmtTime(t), 21) .. pad(label, 32) .. (match or (#files > 0 and "no file within 60 s" or ""))
  end
  if #files == 0 then out[#out + 1] = "  (no screenshots found in " .. dir .. ")" end
end

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local function section(out, title) out[#out + 1] = ""; out[#out + 1] = title; out[#out + 1] = string.rep("-", #title) end

local function renderErrors(out, list, emptyText)
  if #list == 0 then out[#out + 1] = "  " .. emptyText; return end
  for i, e in ipairs(list) do
    if i > 25 then out[#out + 1] = "  ... " .. (#list - 25) .. " more"; break end
    out[#out + 1] = string.format("  %4dx  %s", e.count, clip(e.msg, WIDTH - 9))
    local when = "first " .. fmtTime(e.first) .. ", last " .. fmtTime(e.last)
    local ctx = ctxSummary(e.ctx)
    out[#out + 1] = "         " .. clip(when .. (ctx ~= "" and ("  [" .. ctx .. "]") or ""), WIDTH - 9)
    for _, l in ipairs(e.stack) do out[#out + 1] = "           " .. clip(l, WIDTH - 11) end
  end
end

local function sessionLine(i, s)
  local char = istable(s.char) and ((s.char.class or "?") .. " " .. tostring(s.char.level or "?")) or "?"
  return string.format("  #%-3d %-20s build %-14s toc %-6s addon %-12s %-12s errors %d", i, fmtTime(s.time or s.start),
    tostring(s.build or "?"), tostring(s.toc or "?"), tostring(s.addonBuild or s.addon or "?"), char, count(s.errors))
end

local function renderDiff(out, cur, prev, curErrs, prevErrs)
  local _, curMap = normEntries(curErrs)
  local _, prevMap = normEntries(prevErrs)
  local any = false
  for k, e in pairs(curMap) do if not prevMap[k] then out[#out + 1] = "  new error:      " .. clip(e.msg, WIDTH - 20); any = true end end
  for k, e in pairs(prevMap) do if not curMap[k] then out[#out + 1] = "  resolved error: " .. clip(e.msg, WIDTH - 20); any = true end end
  local r1, _, c1 = normMatrix(cur.matrix)
  local _, _, c0 = normMatrix(prev.matrix)
  if r1 and c0 then
    for _, r in ipairs(r1) do
      for col, v in pairs(c1[r]) do
        local before = c0[r] and c0[r][col]
        if before ~= nil and abbrev(before) ~= abbrev(v) then
          out[#out + 1] = string.format("  matrix: %s @ %s: %s -> %s", r, col, abbrev(before), abbrev(v)); any = true
        end
      end
    end
  end
  local m1 = istable(cur.perf) and istable(cur.perf.micro) and cur.perf.micro
  local m0 = istable(prev.perf) and istable(prev.perf.micro) and prev.perf.micro
  if m1 and m0 then
    for _, k in ipairs(sortedKeys(m1)) do
      local a = istable(m1[k]) and pick(m1[k], "elapsedMilliseconds", "ms", "elapsed") or m1[k]
      local b = istable(m0[k]) and pick(m0[k], "elapsedMilliseconds", "ms", "elapsed") or m0[k]
      if type(a) == "number" and type(b) == "number" and a ~= b then
        out[#out + 1] = string.format("  perf: %-30s %s -> %s ms (%+.0f%%)", k, fmtNum(b), fmtNum(a), b ~= 0 and (a - b) / b * 100 or 0)
        any = true
      end
    end
  end
  if not any then out[#out + 1] = "  No changes worth mentioning." end
end

function R.report(data, opts)
  opts = opts or {}
  local out = {}
  local log = data.log or {}
  local sessions = sessionsOf(log)
  local latest = sessions[#sessions] or {}
  local meta = istable(log.meta) and log.meta or {}
  out[#out + 1] = "Perl Infinity saved variables report"
  out[#out + 1] = string.format("File:      %s (%.1f KB%s)", tostring(data.path), (data.size or 0) / 1024,
    data.mtime and (", saved " .. os.date("%Y-%m-%d %H:%M", data.mtime)) or "")
  out[#out + 1] = string.format("Addon:     %s   build %s   toc %s   locale %s", tostring(meta.addon or latest.addonBuild or "?"),
    tostring(meta.build or latest.build or "?"), tostring(meta.toc or latest.toc or "?"), tostring(meta.locale or "?"))
  out[#out + 1] = "Sessions:  " .. #sessions .. (log.dropped and ("   dropped errors: " .. tostring(log.dropped)) or "")
  if istable(data.db) then
    local profiles = istable(data.db.profiles) and sortedKeys(data.db.profiles) or {}
    out[#out + 1] = string.format("PerlInfinityDB:   present, schema %s, %d profile%s%s%s", tostring(data.db.schema or "?"), #profiles,
      #profiles == 1 and "" or "s", #profiles > 0 and (" (" .. clip(table.concat(profiles, ", "), 60) .. ")") or "",
      istable(data.db.positions) and (", positions for " .. count(data.db.positions) .. " layouts") or "")
  else
    out[#out + 1] = "PerlInfinityDB:   not in this file"
  end
  if data.rawLog == nil then
    out[#out + 1] = ""
    out[#out + 1] = "There's no PerlInfinityLog in this file yet. Run /perlinfinity selftest in game, then /reload."
    return table.concat(out, "\n") .. "\n"
  elseif not istable(data.rawLog) then
    out[#out + 1] = ""
    out[#out + 1] = "PerlInfinityLog is in the file but isn't a table, so there's nothing to read."
    return table.concat(out, "\n") .. "\n"
  end

  section(out, "Errors")
  local errSource = count(log.errors) > 0 and log.errors or latest.errors
  renderErrors(out, (normEntries(errSource)), "No Lua errors were captured.")
  section(out, "Blocked and forbidden actions")
  renderErrors(out, (normEntries(count(log.blocked) > 0 and log.blocked or latest.blocked, true)), "Nothing was blocked or forbidden.")

  section(out, "Self-test")
  local st = istable(log.selfTest) and log.selfTest or nil
  local steps = stepsOf(st or latest.phases)
  if #steps == 0 then out[#out + 1] = "  No self-test results yet." end
  for _, s in ipairs(steps) do
    out[#out + 1] = "  " .. pad(s.name, 28) .. pad(s.status, 9) .. (s.note and clip(tostring(s.note), WIDTH - 41) or "")
  end
  if st and (st.ok or st.failed or st.notes) and not istable(st.notes) then
    out[#out + 1] = string.format("  summary: %s ok, %s failed, %s notes", tostring(st.ok or 0), tostring(st.failed or 0), tostring(st.notes or 0))
  end

  section(out, "Secrecy matrix")
  renderMatrix(out, latest.matrix or (st and st.matrix))
  section(out, "CPU")
  -- Per session: Perl Infinity's login setup, its worst single frame (the game's
  -- addon profiler) and its slowest batched update.
  local cpuLines = {}
  for i = math.max(1, #sessions - 5), #sessions do
    local s = sessions[i]
    local parts = {}
    if type(s.loginMs) == "number" then parts[#parts + 1] = string.format("login %.0f ms", s.loginMs) end
    if istable(s.profiler) and type(s.profiler.PeakTime) == "number" then
      parts[#parts + 1] = string.format("worst frame %.0f ms", s.profiler.PeakTime)
    end
    if istable(s.scheduler) and type(s.scheduler.slowest) == "number" then
      parts[#parts + 1] = string.format("slowest update %.1f ms (%d of %d over 5 ms)", s.scheduler.slowest,
        tonumber(s.scheduler.overFive) or 0, tonumber(s.scheduler.flushes) or 0)
    end
    if #parts > 0 then cpuLines[#cpuLines + 1] = string.format("  #%-3d %s", i, table.concat(parts, ", ")) end
  end
  local perf = latest.perf or latest.cpu or (st and st.cpu)
  if perf or #cpuLines == 0 then renderPerf(out, perf) end
  for _, line in ipairs(cpuLines) do out[#out + 1] = line end
  section(out, "Census")
  if istable(log.census) and count(log.census) > 0 then renderMatrix(out, log.census) else out[#out + 1] = "  (nothing recorded)" end
  section(out, "Manifest: missing")
  renderMissing(out, istable(latest.manifest) and latest.manifest.missing or (st and istable(st.manifest) and st.manifest.missing))
  if istable(log.taintWatch) and istable(log.taintWatch.runs) and #log.taintWatch.runs > 0 then
    section(out, "Taint watch")
    renderTaintWatch(out, log.taintWatch)
  end
  if istable(latest.auraFrames) then
    section(out, "Group frame auras at logout")
    renderAuraFrames(out, latest.auraFrames)
  end
  section(out, "Screenshots")
  renderScreenshots(out, latest.screenshots, opts.screenshotDir or R.SCREENSHOT_DIR)

  local prev = sessions[#sessions - 1]
  if opts.previous then
    local ps = sessionsOf(opts.previous.log or {})
    prev = ps[#ps] or {}
    local prevErrs = count(opts.previous.log.errors) > 0 and opts.previous.log.errors or prev.errors
    section(out, "Changes since " .. tostring(opts.previous.path))
    renderDiff(out, latest, prev, errSource, prevErrs)
  elseif prev then
    section(out, "Changes since the previous session")
    renderDiff(out, latest, prev, latest.errors, prev.errors)
  end

  if opts.all then
    section(out, "All sessions")
    for i, s in ipairs(sessions) do out[#out + 1] = sessionLine(i, s) end
  end
  return table.concat(out, "\n") .. "\n"
end

---------------------------------------------------------------------------
-- JSON
---------------------------------------------------------------------------
local function jsonString(s)
  return '"' .. s:gsub('[%c"\\\127]', function(c)
    local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t", ["\b"] = "\\b", ["\f"] = "\\f" }
    return map[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end
function R.json(v, seen)
  local t = type(v)
  if t == "string" then return jsonString(v)
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.17g", v)
  elseif t == "boolean" then return tostring(v)
  elseif t ~= "table" then return t == "nil" and "null" or jsonString(tostring(v)) end
  seen = seen or {}
  if seen[v] then return "null" end
  seen[v] = true
  local n = #v
  local isArray = n > 0 and count(v) == n
  local parts = {}
  if isArray then
    for i = 1, n do parts[i] = R.json(v[i], seen) end
    seen[v] = nil
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for _, k in ipairs(sortedKeys(v)) do parts[#parts + 1] = jsonString(tostring(k)) .. ":" .. R.json(v[k], seen) end
  seen[v] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

---------------------------------------------------------------------------
-- CLI
---------------------------------------------------------------------------
local function main(argv)
  local path, opts = nil, {}
  for _, a in ipairs(argv) do
    local k, v = a:match("^%-%-(%w+)=?(.*)$")
    if k == "previous" then opts.previousPath = v
    elseif k == "all" then opts.all = true
    elseif k == "json" then opts.json = true
    elseif k == "screenshots" then opts.screenshotDir = v
    elseif k == "help" then
      print("usage: luajit tools/readsv.lua [path] [--previous=path] [--all] [--json] [--screenshots=dir]")
      return 0
    elseif k then io.stderr:write("Unknown option --" .. k .. ". Try --help.\n"); return 2
    else path = a end
  end
  path = path or R.DEFAULT_PATH
  local data, err = R.load(path)
  if not data then
    if err == "missing" then
      print("No saved variables at " .. path .. " yet. Play once with Perl Infinity, /reload or log out, then run this again.")
      return 0
    end
    io.stderr:write("Couldn't read " .. path .. ": " .. err .. "\n")
    return 1
  end
  if opts.previousPath then
    local prev, perr = R.load(opts.previousPath)
    if prev then opts.previous = prev
    else io.stderr:write("Skipping the comparison, couldn't read " .. opts.previousPath .. ": " .. perr .. "\n") end
  end
  if opts.json then print(R.json(data.rawLog)); return 0 end
  io.write(R.report(data, opts))
  return 0
end

if arg and arg[0] and arg[0]:match("readsv%.lua$") then os.exit(main(arg)) end
return R
