-- tests/harness/xml.lua
-- Minimal XML parser for WoW UI files: elements, attributes, text, comments, CDATA.
-- Returns a tree of { tag, attrs = {}, children = {}, text = "" } nodes.

local X = {}

local function unescape(s)
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

local function parseAttrs(s)
  local attrs = {}
  for k, q, v in s:gmatch("([%w_:%-%.]+)%s*=%s*([\"'])(.-)%2") do attrs[k] = unescape(v); local _ = q end
  return attrs
end

function X.parse(src, name)
  src = src:gsub("^\239\187\191", "")              -- BOM
  local root = { tag = "#root", attrs = {}, children = {}, text = "" }
  local stack = { root }
  local pos = 1
  local len = #src
  while pos <= len do
    local lt = src:find("<", pos, true)
    local top = stack[#stack]
    if not lt then
      top.text = top.text .. src:sub(pos)
      break
    end
    if lt > pos then top.text = top.text .. src:sub(pos, lt - 1) end
    if src:sub(lt, lt + 3) == "<!--" then
      local e = src:find("-->", lt + 4, true) or error((name or "xml") .. ": unterminated comment")
      pos = e + 3
    elseif src:sub(lt, lt + 8) == "<![CDATA[" then
      local e = src:find("]]>", lt + 9, true) or error((name or "xml") .. ": unterminated CDATA")
      top.text = top.text .. src:sub(lt + 9, e - 1)
      pos = e + 3
    elseif src:sub(lt, lt + 1) == "<?" then
      local e = src:find("?>", lt + 2, true) or error((name or "xml") .. ": unterminated declaration")
      pos = e + 2
    elseif src:sub(lt, lt + 1) == "</" then
      local e = src:find(">", lt, true) or error((name or "xml") .. ": unterminated close tag")
      local tag = src:sub(lt + 2, e - 1):match("^%s*([%w_:]+)")
      if top.tag ~= tag then
        local line = select(2, src:sub(1, lt):gsub("\n", "")) + 1
        error(string.format("%s:%d: mismatched </%s> (open <%s>)", name or "xml", line, tostring(tag), tostring(top.tag)))
      end
      top.text = unescape(top.text)
      table.remove(stack)
      pos = e + 1
    else
      -- find the end of the tag, honouring quoted attribute values
      local i = lt + 1
      local q
      while i <= len do
        local c = src:sub(i, i)
        if q then if c == q then q = nil end
        elseif c == '"' or c == "'" then q = c
        elseif c == ">" then break end
        i = i + 1
      end
      local body = src:sub(lt + 1, i - 1)
      local selfClose = body:sub(-1) == "/"
      if selfClose then body = body:sub(1, -2) end
      local tag, rest = body:match("^([%w_:]+)(.*)$")
      if not tag then error((name or "xml") .. ": malformed tag near " .. src:sub(lt, lt + 30)) end
      local node = { tag = tag, attrs = parseAttrs(rest), children = {}, text = "" }
      table.insert(top.children, node)
      if not selfClose then table.insert(stack, node) end
      pos = i + 1
    end
  end
  if #stack > 1 then error((name or "xml") .. ": unclosed <" .. stack[#stack].tag .. ">") end
  return root
end

function X.child(node, tag)
  for _, c in ipairs(node.children) do if c.tag == tag then return c end end
end

function X.children(node, tag)
  local r = {}
  for _, c in ipairs(node.children) do if not tag or c.tag == tag then r[#r + 1] = c end end
  return r
end

return X
