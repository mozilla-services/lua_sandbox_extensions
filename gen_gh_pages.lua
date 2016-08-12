-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "os"
require "io"
require "string"
require "table"

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
    local fh = assert(io.open("gh-pages/" .. path .. "/index.md", "w"))
    fh:write(string.format("# %s\n", path))

    for k,v in sort_entries(dir.entries) do
        if k:match(".lua$") then
            fh:write(string.format("* [%s](%s.html) - %s\n", k, strip_ext(k), v.title))
        else
            fh:write(string.format("* [%s](%s/index.html)\n", k, k))
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


local function output_tree(fh, list, key, dir)
    list[#list + 1] = key
    local path = table.concat(list, "/")
    local th = io.open(string.format("%s/index.md", path))
    if th then
        local ih = assert(io.open("gh-pages/" .. path .. "/index.md", "w"))
        ih:write(th:read("*a"))
        ih:close()
        th:close()
    else
        if not dir then return end
        create_index(path, dir)
    end
    local list_size = #list
    local class = ""
    local version = ""
    if list_size == 1 then
        class = 'class="module"'
        fh:write('<ul class="module-ul">\n')
        version = get_version(path)
    elseif list_size == 2 then
        class = 'class="exttype"'
    end
    fh:write(string.format('<li %s><a href="/lua_sandbox_extensions/%s/index.html">%s%s</a></li>\n', class, path, key, version))

    if dir then
        fh:write("<ul>\n")
        for k, v in sort_entries(dir.entries) do
            if k:match(".lua$") then
                fh:write(string.format('<li><a href="/lua_sandbox_extensions/%s.html">%s</a></li>\n', strip_ext(v.line), strip_ext(k)))
            else
                output_tree(fh, list, k, v)
            end
        end
        fh:write("</ul>\n")
    end

    if list_size == 1 then fh:write("</ul>\n") end
    table.remove(list)
end


local function output_css()
    local fh = assert(io.open("gh-pages/docs.css", "w"))
    fh:write([[
    html {
        height: 100%;
    }

    body {
        font-family:verdana, arial, sans-serif;
        font-size:small;
        width: 90%;
        background:white;
        margin-left: auto;
        margin-right: auto;
        height: 100%;
    }

    h1 {
        border-bottom:1px black solid;
    }

    h2 {
        border-bottom:1px gray solid;
    }

    h3 {
        border-bottom:1px lightgray solid;
    }

    h4 {
        border-bottom:1px black dotted;
    }

    h5 {
        border-bottom:1px gray dotted;
    }

    h6 {
        border-bottom:1px lightgray dotted;
    }

    #title {
        width:100%;
        font-size:large;
        font-weight: bold;
        font-style: normal;
        font-variant: normal;
        text-transform: uppercase;
        letter-spacing: .1em;
     }

    .menu {
        display:table-cell;
        font-size: small;
        font-weight: normal;
        font-style: normal;
        color: #000000;
        height: 100%;
        padding-right: 10px;
        white-space: nowrap;
    }

    .menu ul{
        list-style-type: none;
        margin-left: 5px;
        margin-right: 0px;
        padding-left: 10px;
        padding-right: 0px;
    }

    .module {
        margin-bottom: 0px;
        margin-top: 0px;
        background-color: whitesmoke;
        font-variant:  small-caps;
    }

    .module-ul {
        margin-top: 3px;
        margin-bottom: 2px;
    }

    .exttype {
        text-transform: capitalize;
    }

    .main-content {
        border-left:1px lightgray dotted;
        padding-left:10px;
        display:table-cell;
        width:100%;
    }

    code, pre.code, pre.sourceCode
    {
        background-color: whitesmoke;
    }
    ]])
    fh:close()
end

local function handle_path(paths, in_path, out_path)
    local list = {}
    local d = paths
    for dir in string.gmatch(out_path, "[^/]+") do
        list[#list + 1] = dir
        if dir ~= "gh-pages" then
            local full_path = table.concat(list, "/")
            local cd = d.entries[dir]
            if not cd then
                os.execute(string.format("mkdir -p %s", full_path))
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

        local outfn = string.gsub("gh-pages/" .. line, "lua$", "md")
        local p = handle_path(paths, get_path(line), get_path(outfn))
        local ofh = assert(io.open(outfn, "w"))
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
        if path ~= "gh-pages" then
            os.execute(string.format("mkdir -p gh-pages/%s", path))
            local paths = {entries = {}}
            extract_lua_docs(path, paths)
            output_tree(fh, {}, path, paths.entries[path])
        end
    end
    ph:close()

end


local function output_menu(before, after)
    local fh = assert(io.open(before, "w"))
    fh:write(string.format('<div id="title">Lua Sandbox Extensions<hr/></div>\n'))
    fh:write('<div class="menu">\n<ul>\n<li><a href="/lua_sandbox_extensions/index.html">OVERVIEW</a></li>\n</ul>\n')
    output_extensions(fh)
    fh:write('</div>\n<div class="main-content">\n')
    fh:close()

    fh = assert(io.open(after, "w"))
    fh:write("</div>\n")
    fh:close()
end


local function md_to_html()
    local before = "/tmp/before.html"
    local after = "/tmp/after.html"
    output_menu(before, after)
    os.execute("cp README.md gh-pages/index.md")

    local fh = assert(io.popen("find gh-pages -name \\*.md"))
    for line in fh:lines() do
        local css_path = "/lua_sandbox_extensions/docs.css"
        local cmd = string.format("pandoc --from markdown_github-hard_line_breaks --to html --standalone -B %s -A %s -c %s -o %s.html %s", before, after, css_path, line:sub(1, #line -3), line)
        local rv = os.execute(cmd)
        if rv ~= 0 then error(cmd) end
        os.remove(line)
    end
    fh:close()

    os.remove(before)
    os.remove(after)
end


local args = {...}
local function main()
    output_css()
    md_to_html()
end

main()
