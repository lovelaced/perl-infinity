-- tests/run.lua
-- luajit tests/run.lua [pattern] [--mode=strict|field|open] [--fuzz=N] [--verbose]
--
-- Discovers tests/spec/*_spec.lua. Specs use describe/it/expect (below). A test fails
-- on an assertion, a Lua error in the test, any Lua error inside addon code, any
-- ADDON_ACTION_BLOCKED/FORBIDDEN, or a secret/function/userdata in SavedVariables of
-- any harness it created (unless it called h:clearProblems() / set h.allowProblems).

local root = (arg[0]:match("^(.*)/tests/run%.lua$")) or "."
package.path = root .. "/tests/harness/?.lua;" .. root .. "/tests/harness/stubs/?.lua;" .. package.path
local Harness = dofile(root .. "/tests/harness/init.lua")
local Secret = Harness.Secret
local SV = require("savedvars")

local opts = { mode = "strict", fuzz = 0, verbose = false, pattern = nil }
for _, a in ipairs(arg) do
  local k, v = a:match("^%-%-(%w+)=?(.*)$")
  if k == "mode" then opts.mode = v
  elseif k == "fuzz" then opts.fuzz = tonumber(v) or 0
  elseif k == "verbose" then opts.verbose = true
  elseif not k then opts.pattern = a end
end
assert(opts.mode == "strict" or opts.mode == "field" or opts.mode == "open", "--mode must be strict, field or open")

---------------------------------------------------------------------------
-- Harness tracking: default mode from the command line, problems checked per test
---------------------------------------------------------------------------
local live = {}
local realNew = Harness.new
Harness.new = function(o)
  o = o or {}
  if o.mode == nil then o.mode = opts.mode end
  if o.verbose == nil then o.verbose = opts.verbose end
  local h = realNew(o)
  live[#live + 1] = h
  return h
end

local function harnessProblems()
  local r = {}
  for _, h in ipairs(live) do
    if not h.allowProblems then
      for _, p in ipairs(h:problems()) do r[#r + 1] = p end
      if h.addon then
        local names = {}
        for _, n in ipairs(h.addon.savedVariables) do names[#names + 1] = n end
        for _, n in ipairs(h.addon.savedVariablesPerCharacter) do names[#names + 1] = n end
        local _, sv = SV.serialize(h.env, names)
        for _, p in ipairs(sv) do r[#r + 1] = "SavedVariables: " .. p end
      end
    end
  end
  return r
end

---------------------------------------------------------------------------
-- Assertions
---------------------------------------------------------------------------
local function show(v)
  if Secret.is(v) then return "<secret " .. tostring(Secret.raw(v)) .. ">" end
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

local function deepEqual(a, b, seen)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] == b then return true end
  seen[a] = b
  for k, v in pairs(a) do if not deepEqual(v, b[k], seen) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function fail(msg) error({ assertion = msg }, 3) end

local function expect(v)
  local e = {}
  function e.toBe(x) if v ~= x then fail("expected " .. show(x) .. ", got " .. show(v)) end return e end
  function e.notToBe(x) if v == x then fail("expected not " .. show(x)) end return e end
  function e.toEqual(x) if not deepEqual(v, x) then fail("tables/values differ: got " .. show(v)) end return e end
  function e.toBeTruthy() if not v then fail("expected truthy, got " .. show(v)) end return e end
  function e.toBeFalsy() if v then fail("expected falsy, got " .. show(v)) end return e end
  function e.toBeNil() if v ~= nil then fail("expected nil, got " .. show(v)) end return e end
  function e.notToBeNil() if v == nil then fail("expected a value, got nil") end return e end
  function e.toBeSecret() if not Secret.is(v) then fail("expected a secret, got " .. show(v)) end return e end
  function e.notToBeSecret() if Secret.is(v) then fail("expected a plain value, got " .. show(v)) end return e end
  function e.toBeRaw(x)
    if not Secret.is(v) then fail("expected a secret wrapping " .. show(x) .. ", got " .. show(v)) end
    if Secret.raw(v) ~= x then fail("secret holds " .. show(Secret.raw(v)) .. ", expected " .. show(x)) end
    return e
  end
  function e.toMatch(p) if type(v) ~= "string" or not v:find(p) then fail("expected " .. show(v) .. " to match " .. p) end return e end
  function e.toContain(x)
    if type(v) == "string" then if not v:find(x, 1, true) then fail(show(v) .. " does not contain " .. show(x)) end
    else
      local found = false
      for _, y in pairs(v) do if y == x or (type(x) == "string" and type(y) == "string" and y:find(x, 1, true)) then found = true end end
      if not found then fail("collection does not contain " .. show(x)) end
    end
    return e
  end
  function e.toHaveLength(n) if #v ~= n then fail("expected length " .. n .. ", got " .. #v) end return e end
  function e.toBeGreaterThan(n) if not (v > n) then fail("expected > " .. show(n) .. ", got " .. show(v)) end return e end
  function e.toBeLessThan(n) if not (v < n) then fail("expected < " .. show(n) .. ", got " .. show(v)) end return e end
  function e.toBeCloseTo(n, eps) if math.abs(v - n) > (eps or 1e-6) then fail("expected ~" .. n .. ", got " .. show(v)) end return e end
  function e.toThrow(pattern)
    local ok, err = pcall(v)
    if ok then fail("expected an error" .. (pattern and (" matching " .. pattern) or "")) end
    local msg = type(err) == "table" and (err.assertion or err.msg) or tostring(err)
    if pattern and not tostring(msg):find(pattern) then fail("error " .. show(msg) .. " does not match " .. pattern) end
    return e
  end
  function e.notToThrow()
    local ok, err = pcall(v)
    if not ok then fail("unexpected error: " .. tostring(type(err) == "table" and err.assertion or err)) end
    return e
  end
  return e
end

---------------------------------------------------------------------------
-- describe / it
---------------------------------------------------------------------------
local results = { passed = 0, failed = 0, skipped = 0, failures = {} }
local currentFile
local stackNames = {}

local function matchesPattern(name)
  if not opts.pattern then return true end
  return name:find(opts.pattern, 1, true) ~= nil or (currentFile and currentFile:find(opts.pattern, 1, true) ~= nil)
end

local function runTest(name, fn)
  local full = table.concat(stackNames, " > ") .. (#stackNames > 0 and " > " or "") .. name
  if not matchesPattern(full) then return end
  live = {}
  local ok, err = xpcall(fn, function(e)
    if type(e) == "table" and e.assertion then return e end
    return { msg = tostring(e), stack = debug.traceback("", 2) }
  end)
  local problems = harnessProblems()
  if ok and #problems == 0 then
    results.passed = results.passed + 1
    if opts.verbose then io.write("  ok   ", full, "\n") end
  else
    results.failed = results.failed + 1
    local detail = {}
    if not ok then
      if err.assertion then detail[#detail + 1] = "assertion: " .. err.assertion
      else detail[#detail + 1] = "error: " .. err.msg .. (opts.verbose and err.stack or "") end
    end
    for i, p in ipairs(problems) do if i <= 12 then detail[#detail + 1] = p end end
    if #problems > 12 then detail[#detail + 1] = "... " .. (#problems - 12) .. " more problems" end
    results.failures[#results.failures + 1] = { file = currentFile, name = full, detail = detail }
    io.write("  FAIL ", full, "\n")
  end
end

local function describe(name, fn)
  table.insert(stackNames, name)
  fn()
  table.remove(stackNames)
end

local function pending(name, reason)
  results.skipped = results.skipped + 1
  io.write("  skip ", table.concat(stackNames, " > "), " > ", name, reason and (" (" .. reason .. ")") or "", "\n")
end

---------------------------------------------------------------------------
-- Discover and run specs
---------------------------------------------------------------------------
local specs = {}
local p = io.popen('ls "' .. root .. '/tests/spec" 2>/dev/null')
for f in p:lines() do if f:match("_spec%.lua$") then specs[#specs + 1] = f end end
p:close()
table.sort(specs)

io.write(string.format("Perl Infinity harness  mode=%s  fuzz=%d\n", opts.mode, opts.fuzz))
local t0 = os.clock()
for _, file in ipairs(specs) do
  currentFile = file
  local chunk, err = loadfile(root .. "/tests/spec/" .. file)
  if not chunk then
    results.failed = results.failed + 1
    results.failures[#results.failures + 1] = { file = file, name = "(load)", detail = { err } }
  else
    local env = setmetatable({
      describe = describe, it = runTest, pending = pending, expect = expect, Harness = Harness, Secret = Secret,
      MODE = opts.mode, FUZZ = opts.fuzz, ROOT = root, VERBOSE = opts.verbose,
    }, { __index = _G })
    setfenv(chunk, env)
    io.write(file, "\n")
    local ok, e = xpcall(chunk, debug.traceback)
    if not ok then
      results.failed = results.failed + 1
      results.failures[#results.failures + 1] = { file = file, name = "(top level)", detail = { e } }
    end
  end
end

io.write("\n")
for _, f in ipairs(results.failures) do
  io.write("FAIL ", f.file, " :: ", f.name, "\n")
  for _, d in ipairs(f.detail) do io.write("     ", (tostring(d):gsub("\n", "\n     ")), "\n") end
end
io.write(string.format("\n%d passed, %d failed, %d skipped (%.2fs)\n", results.passed, results.failed, results.skipped, os.clock() - t0))
os.exit(results.failed == 0 and 0 or 1)
