

local fh = assert(io.open("raw_cost.tsv", "r"))
local oh = assert(io.open("import_cost.tsv", "w"))

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
            end
            if str then table.insert(t, str) end
        end
        cnt = cnt + 1
    end
    if not first then
        oh:write(table.concat(t, "\t"), "\n")
    else
        first = false
    end
end
