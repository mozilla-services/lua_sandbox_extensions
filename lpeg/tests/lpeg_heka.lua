-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local cfg ={
    lpeg_heka = {
        user_agent_remove = true,
    }
}

function read_config(k)
    return cfg[k]
end

require "string"
local he = require "lpeg.heka"
local test = require "test_verify_message"

local ua = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:27.0) Gecko/20100101 Firefox/27.0"

local tests = {
    {{Fields = {ua = ua}},
     {Fields = {ua_browser = "Firefox", ua_version = 27, ua_os = "Linux"}}
    },
    {{Fields = {ua = "unknown/1.0"}}, {Fields = {ua = "unknown/1.0"}}},
}

for i,v in ipairs(tests) do
    he.add_normalized_user_agent(v[1], "ua")
    test.verify_msg(v[2], v[1], i, true)
end


cfg.lpeg_heka.user_agent_remove = false
local tests1 = {
    {{Fields = {ua = ua}},
     {Fields = {ua = ua, ua_browser = "Firefox", ua_version = 27, ua_os = "Linux"}}
    },
}

for i,v in ipairs(tests1) do
    he.add_normalized_user_agent(v[1], "ua")
    test.verify_msg(v[2], v[1], i, true)
end


cfg.lpeg_heka.user_agent_remove = false
cfg.lpeg_heka.user_agent_normalized_field_name = "user_agent"
local tests2 = {
    {{Fields = {ua = ua}},
     {Fields = {ua = ua, user_agent_browser = "Firefox", user_agent_version = 27, user_agent_os = "Linux"}}
    },
}

for i,v in ipairs(tests2) do
    he.add_normalized_user_agent(v[1], "ua")
    test.verify_msg(v[2], v[1], i, true)
end


local uuid = "3C945705-A585-447C-94FC-86A8524E94F2"
local set_header_tests = {
    {he.set_uuid, {Fields = {id = uuid}}, "id", {Uuid = uuid, Fields = {}}},
    {he.set_timestamp, {Fields = {ts = 100}}, "ts", {Timestamp = 100, Fields = {}}},
    {he.set_logger, {Fields = {source = "logger"}}, "source", {Logger = "logger", Fields = {}}},
    {he.set_hostname, {Fields = {hn = "hostname"}}, "hn", {Hostname = "hostname", Fields = {}}},
    {he.set_type, {Fields = {item = "type"}}, "item", {Type = "type", Fields = {}}},
    {he.set_envversion, {Fields = {ver = "1.0"}}, "ver", {EnvVersion = "1.0", Fields = {}}},
    {he.set_payload, {Fields = {data = "payload"}}, "data", {Payload = "payload", Fields = {}}},
    {he.set_severity, {Fields = {level = 7}}, "level", {Severity = 7, Fields = {}}},
    {he.set_pid, {Fields = {pid = 1234}}, "pid", {Pid = 1234, Fields = {}}},
    {he.remove_payload, {Timestamp = 1, Payload = "payload"}, "", {Timestamp = 1}},
}

for i,v in ipairs(set_header_tests) do
    v[1](v[2], v[3])
    test.verify_msg(v[2], v[4], i, true)
end
