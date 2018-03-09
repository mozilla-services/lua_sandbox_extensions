-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Test Utility Function for Message Verification
--]]

-- Imports
local string    = require "string"
local error     = error
local ipairs    = ipairs
local pairs     = pairs
local type      = type
local tostring  = tostring

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

function verify_field(k, expected, received, id)
    local ev = expected
    local rv = received
    if ev.value then
        if ev.representation ~= rv.representation then
            error(string.format(
                "test: %d field: %s representation expected: %s received: %s",
                id, k, tostring(ev.representation), tostring(rv.representation)))
        end
        if ev.value_type ~= rv.value_type then
            error(string.format(
                "test: %d field: %s value_type expected: %s received: %s",
                id, k, tostring(ev.value_type), tostring(rv.value_type)))
        end
        ev = ev.value
        rv = rv.value
    end

    if type(ev) == "table" then
        for i,v in ipairs(ev) do
            if v ~= rv[i] then
                error(string.format(
                    "test: %d field: %s idx: %d expected: %s received: %s",
                    id, k, i, tostring(v), tostring(rv[i])))
            end
        end
    elseif ev ~= rv then
        error(string.format("test: %d field: %s expected: %s received: %s",
                            id, k, tostring(ev), tostring(rv)))
    end
end


function verify_msg_fields(expected, received, id, symmetric)
    if expected == nil and received ~= nil then
        error(string.format("test: %d failed Fields not nil", id))
    end
    if not expected then return end

    for k,e in pairs(expected) do
        local r = received[k]
        local etyp = type(e)
        local rtyp = type(r)
        if etyp ~= rtyp then
            error(string.format(
                "test: %d field: %s type expected: %s received: %s",
                id, k, etyp, rtyp))
        end
        if etyp == "table" then
            verify_field(k, e, r, id)
        elseif e ~= r then
            error(string.format(
                "test: %d field: %s expected: %s received: %s",
                id, k, tostring(e), tostring(r)))
        end
    end
    if symmetric then
        verify_msg_fields(received, expected, -id)
    end
end


function verify_msg_headers(expected, received, id, symmetric)
    for k,v in pairs(expected) do
        if k == "Fields" then
            if not received[k] then
                error(string.format("test: %d header: %s not found", id))
            end
        else
            if v ~= received[k] then
                error(string.format(
                    "test: %d header: %s type expected: %s received: %s",
                    id, k, tostring(v), tostring(received[k])))
            end
        end
    end
    if symmetric then
        verify_msg_headers(received, expected, -id)
    end
end


function verify_msg(expected, received, id, symmetric)
    verify_msg_headers(expected, received, id, symmetric)
    verify_msg_fields(expected.Fields, received.Fields, id, symmetric)
end


function fields_array_to_hash(msg)
    if not msg.Fields or #msg.Fields == 0 then return end
    local fields = {}
    for i,v in ipairs(msg.Fields) do
        if #v.value == 1 then v.value = v.value[1] end
        if v.representation or v.value_type == 1 or v.value_type == 2 then
            fields[v.name] = v
            v.name = nil
        else
            fields[v.name] = v.value
        end
    end
    msg.Fields = fields
end

return M
