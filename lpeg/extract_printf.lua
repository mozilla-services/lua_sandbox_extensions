-- export LUA_PATH=/usr/lib/luasandbox/modules/?.lua LUA_CPATH=/usr/lib/luasandbox/modules/?.so
-- find openssh-portable -name "*.c" > files.txt
-- lua extract_printf.lua <file list> [function name]
local l = require "lpeg"
l.locale(l)
local filename = arg[1]
local funcname = arg[2] or "printf"

local function anywhere (p)
  return l.P{ p + 1 * l.V(1) }
end

local notnl  = (l.space^1/" ") + l.P(1)
local func   = l.P(funcname .. "(") * l.Cs((notnl - l.P");")^1)
local printf = l.Ct(anywhere(func)^0)

local parens = lpeg.P{ "(" * ((1 - lpeg.S"()") + lpeg.V(1))^0 * ")" }
local qconcat = (l.P'"' * l.space^0 * l.P'"') / ""
local fmt = l.space^0 * '"' * lpeg.Cs(((1 - l.S'\\"') + (lpeg.P'\\' * l.P(1)) + qconcat)^0) * '"'
local arg = l.space^0 * lpeg.Cs(((1 - lpeg.S'(,\n"')^1 + (l.P'"' / '\\"') + parens)^0)
local record = l.Ct(fmt * (',' * arg)^0)

local dedupe = {}

local function get_record(s)
    local r = record:match(s)
    local len = 0
    if r then
        len = #r
        if len == 1 then return end
        if len == 2 and r[2].specifier == "s" then return end
        if dedupe[r[1]] then return end
        dedupe[r[1]] = true
    end
    return r, len
end


for line in io.lines(filename) do
    local header = true
    local fh = assert(io.open(line))
    local data = fh:read("*a")
    fh:close()

    local t = printf:match(data)
    local len = #t
    if len >= 0 then
        for i,v in ipairs(t) do
            local r, len = get_record(v)
            if r then
               for j=1, len do
                   if j > 1 then
                       if string.match(r[j], "^%([^)]*%).+") then -- remove cast
                           r[j]= string.match(r[j], "%([^)]*%)%s*(.+)$")
                       end

                       if string.match(r[j], "^%*") then -- remove dereference
                           r[j]= string.match(r[j], "^%*(.+)")
                       end

                       if string.match(r[j], "^[%w_]+%(") then -- function name becomes the capture name
                           r[j] = string.match(r[j], "^([%w_]+)")
                       end

                       if string.match(r[j], "%[[%w_]+%]") then -- remove array index
                           r[j]= string.gsub(r[j], "%[[%w_]+%]", "")
                       end

                       if string.match(r[j], "%->[%w_]+$") then -- member name becomes the capture name
                           r[j] = string.match(r[j], "%->([%w_]+)$")
                       end

                       if string.match(r[j], "%.[%w_]+$") then
                           r[j]= string.match(r[j], "%.([%w_]+)$") -- member name becomes the capture name
                       end
                   end
                   r[j] = string.format('"%s"', r[j])
               end
               if header then
                   print(string.format("\n-- %s", line))
                   header = false
               end
               print(string.format("{%s},", table.concat(r, ", ")))
            end
        end
    end
end
