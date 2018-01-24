-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Syslog Decoder Module

## Decoder Configuration Table
```lua
decoders_syslog = {
  -- template (string) - The 'template' configuration string from rsyslog.conf
  -- see http://rsyslog-5-8-6-doc.neocities.org/rsyslog_conf_templates.html
  -- Default:
  -- template = "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%", -- RSYSLOG_TraditionalForwardFormat

  printf_messages = {
   -- array (string and/or array) the order specified here is the load and evaluation order.
     -- string: name of a module containing a `printf_messages` array to import
     -- array: creates an on the fly grammar using a printf format specifications.
       -- see: https://mozilla-services.github.io/lua_sandbox_extensions/lpeg/modules/lpeg/printf.html

   {"%s:%lu: invalid line", "path", "linenum"},
   "lpeg.openssh_portable", -- must export a `printf_messages` array
  },

  sub_decoders = {
  -- programname_ (string/array)
    -- string: decoder or grammar module name
    -- array: (string and/or array) list of specific messages to parse
      -- string: Sample message used to locate the correct grammar
         -- If no grammar matches the sample message then an error is thrown
         -- and another grammar or module must be added to the printf_messages
         -- configuration. If multiple grammars match the message, the first
         -- grammar with the most specific match is selected.
         -- Note: a special token of `<<DROP>>` and `<<FAIL>>` are reserved for
         -- the last entry in the array to handle the no match case; <<DROP>>
         -- silently discards the message and <<FAIL>> reports an error. If
         -- neither is specified the default no match behavior is to inject the
         -- original message produced by the syslog decoder.
      -- array:
         -- column 1: (string/array)
            -- string: Sample message (see above)
            -- array: printf.build_grammar format specification
         -- column 2: (table/nil)
            -- Transformation table with Heka message field name keys and a
            -- value of the fully qualified transformation function name. The
            -- function returns no values but can error; it receives two
            -- arguments: the Heka message table and the field name to act on.
            -- The function can modify the message in any way.

    nginx  = "decoders.nginx.access", -- decoder module name
    kernel = "lpeg.linux.kernel",     -- grammar module name, must export an lpeg grammar named 'syslog_grammar'
    sshd = {
      -- openssh_portable auth message, imported in printf_messages
      {"Accepted publickey for foobar from 10.11.12.13 port 4242 ssh2", {remote_addr = "geoip.heka.add_geoip"}},
    },
    foo = {
      "/tmp/input.tsv:23: invalid line", -- custom log defined in printf_messages
      {{"Status: %s", "status"}, nil},   -- inline printf spec, no transformation
    },
  },
}
```

## Functions

### decode

Decode and inject the resulting message

*Arguments*
- data (string) - syslog message
- default_headers (optional table) - Heka message table containing the default
  header values to use, if they are not populated by the decoder. If 'Fields'
  is specified it should be in the hashed based format see:
  http://mozilla-services.github.io/lua_sandbox/heka/message.html

*Return*
- (nil, string) or throws an error on invalid data or an inject message failure
    - nil - if the decode was successful
    - string - error message if the decode failed (e.g. no match)
--]]

-- Imports

local module_name   = ...
local module_cfg    = require "string".gsub(module_name, "%.", "_")
local string        = string
local syslog        = require "lpeg.syslog"
local printf        = require "lpeg.printf"

local cfg = read_config(module_cfg) or {}
assert(type(cfg) == "table", module_cfg .. " must be a table")
local template      = cfg.template or "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag:1:32%%msg:::sp-if-no-1st-sp%%msg%"
local grammar       = syslog.build_rsyslog_grammar(template)

local sub_decoders  = {}
local grammars      = nil
if cfg.printf_messages then
    grammars = printf.load_messages(cfg.printf_messages)
end

if not (cfg.payload_keep ~= nil and type(cfg.payload_keep) == "boolean") then
    cfg.payload_keep = true
end


local function grammar_decode_fn(g)
    return function(data, dh) -- dh will contain the original parsed syslog message
        local fields = g:match(data)
        if not fields then return "parse failed" end
        for k,v in pairs(fields) do
            dh.Fields[k] = v
        end
        inject_message(dh)
    end
end


local FAIL_TOKEN = "<<FAIL>>"
local DROP_TOKEN = "<<DROP>>"
local function grammar_pick_fn(sd, nomatch_action)
    return function(data, dh) -- dh will contain the original parsed syslog message
        local fields
        for _,cpg in ipairs(sd) do  -- individually check each grammar
            fields = cpg[1]:match(data)
            if fields then
                for k,v in pairs(fields) do
                    dh.Fields[k] = v
                end
                if cpg[2] then -- apply user defined transformation functions
                    for k,f in pairs(cpg[2]) do
                        f(dh, k)
                    end
                end
                break
            end
        end
        if not fields and nomatch_action then
            if nomatch_action == DROP_TOKEN then
                return
            elseif nomatch_action == FAIL_TOKEN then
                return "parse failed"
            end
        end
        inject_message(dh)
    end
end


for sdk,sd in pairs(cfg.sub_decoders or {}) do
    local sdt = type(sd)
    if sdt == "string" then
        if sd:match("^decoders%.") then
            local decode = require(sd).decode
            if type(decode) ~= "function"  then
                string.format("sub_decoders, no decode function defined: %s", sdk)
            end
            sub_decoders[sdk] = decode
        else
            local g = require(sd).syslog_grammar
            if type(g) ~= "userdata" then
                string.format("sub_decoders, no grammar defined: %s", sdk)
            end
            sub_decoders[sdk] = grammar_decode_fn(g)
        end
    elseif sdt == "table" then -- cherry pick printf grammars
        local nomatch_action
        for i,cpg in ipairs(sd) do
            if type(cpg) ~= "table" then
                cpg = {cpg}
                sd[i] = cpg
            end

            local g
            local typ = type(cpg[1])
            if typ == "string" then
                if (cpg[1] == DROP_TOKEN or cpg[1] == FAIL_TOKEN) and sd[i + 1] == nil then
                    nomatch_action = cpg[1]
                    sd[i] = nil
                    break
                end
                g = printf.match_sample(grammars, cpg[1])
                if not g then
                    error(string.format("No grammar found for: %s", cpg[1]))
                end
            elseif typ == "table" then
                g = printf.build_grammar(cpg[1])
            else
                error(string.format("sub_decoder: %s invalid entry: %d", sdk, i))
            end
            cpg[1] = g

            if cpg[2] then
                for k,v in pairs(cpg[2]) do
                    local fn
                    local mname, fname = string.match(v, "(.-)%.([^.]+)$")
                    if mname then
                        fn = require(mname)[fname]
                    else
                        fn = _G[cpg[2]]
                    end
                    if type(fn) ~= "function" then
                        error(string.format("Invalid transformation function %s=%s", k, v))
                    end
                    cpg[2][k] = fn
                end
            end
        end
        sub_decoders[sdk] = grammar_pick_fn(sd, nomatch_action)
    else
        error(string.format("subdecoder: %s invalid type: %s", k, sdt))
    end
end
grammars = nil -- free the unused grammars

local pairs = pairs
local type  = type

local inject_message = inject_message

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local msg = {}

function decode(data, dh)
    local fields = grammar:match(data)
    if not fields then return module_name .. " parse failed" end
    local programname = ""

    if fields.pri then
        msg.Severity = fields.pri.severity
        fields.syslogfacility = fields.pri.facility
        fields.pri = nil
    else
        msg.Severity = fields.syslogseverity or fields["syslogseverity-text"]
        or fields.syslogpriority or fields["syslogpriority-text"]

        fields.syslogseverity = nil
        fields["syslogseverity-text"] = nil
        fields.syslogpriority = nil
        fields["syslogpriority-text"] = nil
    end

    if fields.syslogtag then
        programname = fields.syslogtag.programname
        fields.programname = programname
        msg.Pid = fields.syslogtag.pid
        fields.syslogtag = nil
    end

    msg.Timestamp = fields.timestamp
    fields.timestamp = nil

    msg.Hostname = fields.hostname or fields.source
    fields.hostname = nil
    fields.source = nil

    msg.Payload = fields.msg
    fields.msg = nil

    msg.Fields = fields

    if dh then
        msg.Uuid        = dh.Uuid
        msg.Logger      = dh.Logger
        if not msg.Hostname then msg.Hostname = dh.Hostname end
        if not msg.Timestamp then msg.Timestamp = dh.Timestamp end
        msg.Type        = dh.Type
        if not msg.Payload then msg.Payload = dh.Payload end
        msg.EnvVersion  = dh.EnvVersion
        if not msg.Pid then msg.Pid = dh.Pid end
        if not msg.Severity then msg.Severity = dh.Severity end

        if type(dh.Fields) == "table" then
            for k,v in pairs(dh.Fields) do
                if msg.Fields[k] == nil then
                    msg.Fields[k] = v
                end
            end
        end
    end

    local df = sub_decoders[programname]
    if df then
        local payload = msg.Payload
        if not cfg.payload_keep then msg.Payload = nil end
        local err = df(payload, msg)
        if err then
            err = string.format("%s.%s %s", module_name, programname, err)
        end
        return err
    end
    inject_message(msg)
end

return M
