-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local bit32 = require "bit32"
local fcntl = require "posix.fcntl"
local libgen = require "posix.libgen"
local unistd = require "posix.unistd"
require "os"

--[[
#  Output in syslog-like format

Append a line in RSYSLOG_TraditionalFileFormat.

Note: The output file is opened on first received message, and closed on
timer event.

## syslog.cfg
```lua
filename        = "syslog_file.lua"
ticker_interval = 10 * 60 -- for log rotation

message_matcher = 'Logger == "input.syslog" || Logger == "input.klog"'

files = {
    ["/var/log/auth.log"] = { mm = "Fields[syslogfacility] == 10 || Fields[syslogfacility] == 16" },
    ["/var/log/syslog"]   = { mm = "Fields[syslogfacility] != 10 && Fields[syslogfacility] != 16", sync = false },
}
-- owner = "root"
-- group = "adm"
-- mode = 0640
```
--]]

local files  = read_config("files") or error("files must be set")
local owner  = read_config("owner") or "root"
local group  = read_config("group") or "adm"
local mode  = read_config("mode") or 0640

-- same key as files,
-- value is a table: [message_matcher, filehandle, dirhandle]
local states = {}

for path, opts in pairs(files) do
    local ok, mm = pcall(create_message_matcher, opts.mm)
    if not ok then
        error("bad message matcher '" .. opts.mm .. "' for file '" .. path .. "'")
    end
    states[path] = {mm, nil, nil}
end

function format_message()
    local ts = read_message("Timestamp") / 1e9
    local hn = read_message("Hostname")
    local pn = read_message("Fields[programname]")
    local pid = read_message("Pid")
    local pl = read_message("Payload")
    local syslogtag = ""
    if pn and pid then
        syslogtag = " " .. pn .. "[" .. pid .. "]:"
    elseif pn then
        syslogtag = " " .. pn .. ":"
    end
    -- "%TIMESTAMP% %HOSTNAME% %syslogtag%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n"
    -- FIXME local timezone
    return os.date("%b %d %H:%M:%S", ts) .. " " .. hn .. syslogtag .. " " .. pl .. "\n"
end

function process_message()
    local line = format_message()
    for path, state in pairs(states) do
        if state[1]:eval() then
            if not state[2] then
                local err = nil
                local oflags = bit32.bor(fcntl.O_CREAT, fcntl.O_WRONLY, fcntl.O_APPEND, fcntl.O_NOCTTY, fcntl.O_CLOEXEC)
                state[2], err = fcntl.open (path, oflags, tonumber(mode, 8))
                if err then return -1, err end
                _, err = unistd.chown(path, owner, group)
                if err then return -1, err end
                if files[path].sync ~= false then
                    local parent = libgen.dirname(path)
                    state[3], err = fcntl.open(parent, bit32.bor(fcntl.O_RDONLY, fcntl.O_CLOEXEC, fcntl.O_NOCTTY))
                    if err then return -1, err end
                end
            end
            unistd.write(state[2], line)
            if files[path].sync ~= false then
                -- sync both file and parent directory
                unistd.fsync(state[2])
                unistd.fsync(state[3])
            end
        end
    end
    return 0
end

function timer_event(ns)
    for path, state in pairs(states) do
        if state[2] then
            unistd.close(state[2])
            state[2] = nil
        end
        if state[3] then
            unistd.close(state[3])
            state[3] = nil
        end
    end
end
