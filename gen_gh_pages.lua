-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "os"
require "io"
require "string"
require "table"

local output_dir
local gh_pages = "gh-pages"

local function get_path(s)
    return s:match("(.+)/[^/]-$")
end


local function get_filename(s)
    return s:match("/([^/]-)$")
end


local function strip_ext(s)
    return s:sub(1, #s - 4)
end


local function sort_entries(t)
  local a = {}
  for n in pairs(t) do table.insert(a, n) end
  table.sort(a)
  local i = 0      -- iterator variable
  local iter = function ()   -- iterator function
    i = i + 1
    if a[i] == nil then
        return nil
    else
        return a[i], t[a[i]]
    end
  end
  return iter
end


local function create_index(path, dir)
    if not dir then return end
    local fh = assert(io.open(string.format("%s/%s/README.md", output_dir, path), "w"))
    fh:write(string.format("# %s\n", path))

    for k,v in sort_entries(dir.entries) do
        if k:match(".lua$") then
            fh:write(string.format("* [%s](%s.md) - %s\n", k, strip_ext(k), v.title))
        else
            fh:write(string.format("* [%s](%s/README.md)\n", k, k))
        end
    end
    fh:close()
end


local function get_version(path)
    local version = ""
    local fh = io.open(string.format("%s/CMakeLists.txt.%s", path, path))
    if not fh then fh = io.open(string.format("%s/CMakeLists.txt", path)) end
    if fh then
        local v
        for line in fh:lines() do
            v = line:match("^project%(%s*[^ ]+%s+VERSION%s+(%d+%.%d+%.%d+)")
            if v then
                version = string.format(" (%s)", v)
                break
            end
        end
        fh:close()
    end
    return version
end


local function output_tree(fh, list, key, dir, nesting)
    list[#list + 1] = key
    local path = table.concat(list, "/")
    local th = io.open(string.format("%s/index.md", path))
    if th then
        local ih = assert(io.open(string.format("%s/%s/README.md", output_dir, path), "w"))
        ih:write(th:read("*a"))
        ih:close()
        th:close()
    else
        if not dir then return end
        create_index(path, dir)
    end

    local list_size = #list
    local version = ""
    if list_size == 1 then
        version = get_version(path)
    end
    fh:write(string.format("%s* [%s%s](%s/README.md)\n", nesting, key, version, path))

    nesting = nesting .. "    "
    if dir then
        for k, v in sort_entries(dir.entries) do
            if k:match(".lua$") then
                fh:write(string.format("%s* [%s](%s.md)\n", nesting, strip_ext(k), strip_ext(v.line)))
            else
                output_tree(fh, list, k, v, nesting)
            end
        end
    end
    table.remove(list)
end


local function handle_path(paths, in_path, out_path)
    local list = {}
    local d = paths
    for dir in string.gmatch(out_path, "[^/]+") do
        list[#list + 1] = dir
        if dir ~= gh_pages then
            local full_path = table.concat(list, "/")
            local cd = d.entries[dir]
            if not cd then
                os.execute(string.format("mkdir -p %s/%s", output_dir, full_path))
                local nd = {path = in_path, entries = {}}
                d.entries[dir] = nd
                d = nd
            else
                d = cd
            end
        end
    end
    return d
end


local function extract_lua_docs(path, paths)
    local fh = assert(io.popen(string.format("find %s/sandboxes %s/modules %s/io_modules -name \\*.lua", path, path, path)))
    for line in fh:lines() do
        local sfh = assert(io.open(line))
        local lua = sfh:read("*a")
        sfh:close()

        local doc = lua:match("%-%-%[%[%s*(.-)%-%-%]%]")
        local title = lua:match("#%s(.-)\n")
        if not title then error("doc error, no title: " .. line) end

        local outfn = string.gsub(string.format("%s", line), "lua$", "md")
        local p = handle_path(paths, get_path(line), get_path(outfn))
        local ofh = assert(io.open(string.format("%s/%s", output_dir, outfn), "w"))
        p.entries[get_filename(line)] = {line = line, title = title}
        ofh:write(doc)
        ofh:write(string.format("\n\nsource code: [%s](https://github.com/mozilla-services/lua_sandbox_extensions/blob/master/%s)\n", get_filename(line), line))
        ofh:close()
    end
    fh:close()
end


local function output_extensions(fh)
    local ph = assert(io.popen("ls -1d */"))
    for dir in ph:lines() do
        local path =  dir:sub(1, #dir -1)
        if path ~= gh_pages then
            os.execute(string.format("mkdir -p %s/%s", output_dir, path))
            local paths = {entries = {}}
            extract_lua_docs(path, paths)
            output_tree(fh, {}, path, paths.entries[path], "")
        end
    end
    ph:close()
end


local function output_third_party(fh)
    local t = {}
    local tp = assert(io.popen("curl -L https://github.com/mozilla-services/lua_sandbox_extensions/wiki/Third-Party-Sandbox-Extensions.md"))
    fh:write("\n\n### Third Party Extensions\n\n")
    for mod in tp:lines() do
        local name, url = mod:match("^%*%s*%[([^]]+)%]%(([^)]+)")
        if name then
            t[#t + 1] = string.format("* [%s](%s)", name, url)
        end
    end
    table.sort(t)
    fh:write(table.concat(t, "\n"))
    tp:close()
end


local args = {...}
local function main()
    output_dir = string.format("%s/gb-source", arg[2])
    os.execute(string.format("mkdir -p %s", output_dir))
    os.execute(string.format("cp README.md %s/.", output_dir))
    local fh = assert(io.open(string.format("%s/book.json", output_dir), "w"))
    fh:write([[{"plugins" : ["collapsible-menu", "navigator"]}]])
    fh:close()

    fh = assert(io.open(string.format("%s/SUMMARY.md", output_dir), "w"))
    fh:write("* [Lua Sandbox Extensions](README.md)\n\n")
    output_extensions(fh)
    output_third_party(fh)
    fh:close()
    os.execute(string.format("cd %s;gitbook install", output_dir))
    os.execute(string.format("gitbook build %s", output_dir))
    local rv = os.execute(string.format("rsync -rav %s/_book/ %s/", output_dir, gh_pages))
    if rv ~= 0 then error"rsync publish" end
end

main()
