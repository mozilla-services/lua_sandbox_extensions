local fh = assert(io.open("raw_cost.tsv", "r"))
local rh = assert(io.open("releng_cost.tsv", "r"))
local oh = assert(io.open("import_cost.tsv", "w"))

local function get_first_of_month(t)
    local dt = os.date("*t", t)
    dt.day = 1
    dt.hour = 0
    dt.min = 0
    dt.sec = 0
    local t = os.time(dt)
    return os.date("%Y-%m-%d", t), t
end

local function set_default(t)
    t[7] = "1970-01-01"
    oh:write(table.concat(t, "\t"), "\n")
end

local cmonth, cmonth_t = get_first_of_month(t)
local pmonth = get_first_of_month(cmonth_t - 86400)

local first = true
for l in fh:lines() do
    local t = {}
    local cnt = 0
    for str in string.gmatch(l, "([^\t]+)") do
        if cnt < 5 or cnt > 7 then
            if cnt == 2 then
                local p, c = string.match(str, "^([^ ]+) ?(.*)$")
                table.insert(t, p)
                table.insert(t, c)
                str = nil
            elseif cnt == 3 then
                str = string.gsub(str, "[$,]", "")
            elseif cnt == 8 then
                str = str .. "-01"
            elseif cnt == 9 then
                break
            end
            if str then table.insert(t, str) end
        end
        cnt = cnt + 1
    end
    if not first then
        oh:write(table.concat(t, "\t"), "\n")
        if pmonth == t[7] then set_default(t) end
    else
        first = false
    end
end

for l in rh:lines() do
    local t = {}
    local cnt = 0
    for str in string.gmatch(l, "([^\t]*)\t?") do -- lua 5.1 matcher bug needs special handling
        cnt = cnt + 1
        if cnt < 8 then table.insert(t, str) end
    end
    oh:write(table.concat(t, "\t"), "\n")
    set_default(t)
end
