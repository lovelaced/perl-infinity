-- tests/spec/readsv_spec.lua
-- tools/readsv.lua must read any SavedVariables shape without crashing and produce a
-- report; fixtures live in tests/fixtures/sv/.

local TOOL = ROOT .. "/tools/readsv.lua"
local DIR = ROOT .. "/tests/fixtures/sv/"

local function exists(path)
  local f = io.open(path, "r")
  if f then f:close() return true end
  return false
end

if not exists(TOOL) then
  describe("readsv", function() pending("reports on SavedVariables", "tools/readsv.lua not built yet") end)
  return
end

-- arg[0] is tests/run.lua here, so the tool loads as a module rather than the CLI
local ok, R = pcall(dofile, TOOL)

describe("readsv", function()
  it("loads as a module", function()
    expect(ok).toBe(true)
    expect(type(R)).toBe("table")
    expect(type(R.load)).toBe("function")
    expect(type(R.report)).toBe("function")
  end)

  local p = io.popen('ls "' .. DIR .. '" 2>/dev/null')
  for file in p:lines() do
    if file:match("%.lua$") then
      it("reports on " .. file .. " without errors", function()
        local data, err = R.load(DIR .. file)
        expect(err).toBeNil()
        local text = R.report(data, {})
        expect(type(text)).toBe("string")
        expect(#text).toBeGreaterThan(0)
      end)
    end
  end
  p:close()

  it("returns an error for a missing file instead of crashing", function()
    local data, err = R.load(DIR .. "does-not-exist.lua")
    expect(data).toBeNil()
    expect(err).notToBeNil()
  end)
end)
