-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "cjson"
require "io"
require "os"
require "string"

local cnt = 0

local expected = {
    {Type = "error.curl.artifact_list", taskId = "C0PGASalTF6MZNoTg0eLGQ"},
    {Type = "error.curl.task_definition", taskId = "C0PGASalTF6MZNoTg0eLGQ"},
    {Type = "error.curl.log", taskId = "ZYFKUNR5RhmrBAq4Z4KB9g"},
    {Type = "error.curl.resource_monitor", taskId = "USQ8K5YcQJKQgybb28cyXg"},
    {Type = "error.curl.perfherder", taskId = "USQ8K5YcQJKQgybb28cyXg"},
    }

local ecnt = #expected

local a = {}

function process_message()
    cnt = cnt + 1

    local typ = read_message("Type")
    local tid = read_message("Fields[taskId]")
    local dat = read_message("Fields[data]")
    local e = expected[cnt]
    if not e then error(string.format("test # %d not defined %s %s", cnt, tostring(typ),  tostring(tid))) end
    if typ ~= e.Type then error(string.format("received '%s' expected: '%s'", tostring(typ),  e.Type)) end
    if tid ~= e.taskId then error(string.format("received '%s' expected: '%s'", tostring(tid),  e.taskId)) end
    dat = dat:gsub(tid, "BF_" .. tid)
    a[cnt] = { type = typ, taskId = tid, data = dat }
    if cnt == ecnt then
        local fh = assert(io.open("backfill.tmp", "wb"))
        fh:write(cjson.encode(a))
        fh:close()
        os.execute("mv backfill.tmp /var/tmp/input.backfill_query.json")
    end
    return 0
end

function timer_event(ns)
    if ecnt ~= cnt then error(string.format("received %d expected: %d", cnt,  ecnt)) end
end
