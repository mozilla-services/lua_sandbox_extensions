-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Verifies the test data for the moz_generic ingestion decoder
--]]

require "string"

local messages = {
    {Type = "moz_generic.error", Fields = {
         DecodeErrorType = "uri",
         DecodeError = "Not enough path components"
    }},
    {Type = "moz_generic.error", Fields = {
         DecodeErrorType = "uri",
         DecodeError = "Invalid path prefix: 'notsubmit' in /notsubmit/generic/test/1/documentid2"
    }},
    {Type = "moz_generic.error", Fields = {
         DecodeErrorType = "uri",
         DecodeError = "dimension spec/path component mismatch"
    }},
    {Type = "moz_generic.error", Fields = {
         DecodeErrorType = "uri",
         DecodeError = "Path too long: 1047 > 1024"
    }},
    {Type = "moz_generic.error", Fields = {
         DecodeErrorType = "schema",
         DecodeError = "missing schema for test version 2"
    }},
    {Type = "moz_generic.error", Fields = {
         DecodeErrorType = "schema",
         DecodeError = "test schema version 1 validation error: SchemaURI: # Keyword: required DocumentURI: #"
    }},
    {Type = "moz_generic.error", Fields = {
         DecodeErrorType = "schema",
         DecodeError = "test schema version 1 validation error: SchemaURI: #/properties/foo Keyword: type DocumentURI: #/foo"
    }},
    {Type = "moz_generic.error", Fields = {
         DecodeErrorType = "json",
         DecodeError = "invalid submission: failed to parse offset:1 Missing a name for object member."
    }},
    {Type = "moz_generic", Fields = {
         docVersion = "1",
         docType = "test",
         submission = '{"foo":"bar"}',
         documentId = "documentid9",
         namespace = "generic"
    }},
    {Type = "moz_generic.duplicate", Fields = {
         documentId = "documentid9",
         docType = "test",
         duplicateDelta = 0,
         namespace = "generic",
         docVersion = "1"
    }}
}
local function verify_fields(idx, fields)
    for k,v in pairs(fields) do
        local name = string.format("Fields[%s]", k)
        local r = read_message(name)
        assert(v == r, string.format("Test %d Fields[%s] = %s", idx, k, tostring(r)))
    end
end

local function verify_message(idx)
    local msg = messages[idx]
    for k,v in pairs(msg) do
        if k == "Fields" then
            verify_fields(idx, v)
        else
            local r = read_message(k)
            assert(v == r, string.format("Test %d %s = %s", idx, k, tostring(r)))
        end
    end
end

local cnt = 0
function process_message()
    cnt = cnt + 1
    verify_message(cnt)
    return 0
end

function timer_event(ns)
    assert(cnt == #messages, tostring(cnt) .. " of " .. tostring(#messages) .. " tests ran")
end
