-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Mozilla TLS Reports Decoder Module
Extract clock skew, issuer info and Subject / SAN match status from tls error
reports.

## decoder_cfg Table
```lua
-- Boolean used to determine whether to inject the raw message in addition to the decoded one.
inject_raw = false -- optional, if not specified the raw message is not injected
```

## Functions

### transform_message

Transform and inject the message using the provided stream reader

*Arguments*
- hsr (hsr) - stream reader with the message to process

*Return*
- none, injects an error message on decode failure

### decode

Decode and inject the message given as argument, using a module-internal stream reader

*Arguments*
- msg (string) - binary message to decode

*Return*
- none, injects an error message on decode failure

--]]

-- Imports
local string = require "string"
local cjson = require "cjson"
local os = require "os"

local assert = assert
local ipairs = ipairs
local type = type
local next = next
local pcall = pcall

local read_config = read_config
local inject_message = inject_message
local create_stream_reader = create_stream_reader

local openssl = require "openssl"
local name = openssl.x509.name
local asn1 = openssl.asn1

local certPrefix = "-----BEGIN CERTIFICATE-----\n"
local certSuffix = "-----END CERTIFICATE-----\n"

local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

local function load_decoder_cfg()
  local cfg = read_config("decoder_cfg")
  if not cfg then cfg = {} end
  assert(type(cfg) == "table", "decoder_cfg must be a table")
  if not cfg.inject_raw then cfg.inject_raw = false end
  assert(type(cfg.inject_raw) == "boolean", "inject_raw must be a boolean")
  return cfg
end

local cfg = load_decoder_cfg()

local msg = {
  Type = "tls_report",
  Logger = "sslreports",
  Fields = {}
}

local emsg = {
    Logger = "sslreports",
    Type = "tls_report.error",
    Fields = {
        DecodeErrorType = "",
        DecodeError     = "",
    }
}

local hsr = create_stream_reader("extract_tls_info")

-- create PEM data from base64 encoded DER
local function make_pem(data)
  local pem = certPrefix
  local offset = 1
  while offset <= data:len() do
    local stop = offset + 63
    if stop > data:len() then
      stop = data:len()
    end
    pem = pem .. data:sub(offset, stop) .. "\n"
    offset = stop + 1
  end
  return pem .. certSuffix
end

-- read and parse a certificate
local function read_cert(data)
  local pem = make_pem(data)
  return pcall(openssl.x509.read, pem)
end

local function parse_cert(cert)
  return pcall(cert.parse, cert)
end

function transform_message(hsr)
    if cfg.inject_raw then
      -- duplicate the raw message
      pcall(inject_message, hsr)
    end
    msg.Fields["submissionDate"] = os.date("%Y%m%d", hsr:read_message("Timestamp") / 1e9)
    local payload = hsr:read_message("Fields[content]")
    local ok, report = pcall(cjson.decode, payload)
    if not ok then return -1, report end

    -- copy over the expected fields
    local expected = {
      "hostname",
      "port",
      "timestamp",
      "errorCode",
      "failedCertChain",
      "userAgent",
      "version",
      "build",
      "product",
      "channel"
    }

    for i, fieldname in ipairs(expected) do
      local field = report[fieldname]
      -- ensure the field is not empty (and does not contain an empty table)
      if not ("table" == type(field) and next(field) == nil) then
        msg.Fields[fieldname] = field
      end
    end

    -- calculate the clock skew - in seconds, since os.time() returns those
    local reportTime = report["timestamp"]
    if "number" == type(reportTime) then
      -- skew will be positive if the remote timestamp is in the future
      local skew = reportTime - os.time()

      msg.Fields["skew"] = skew
    end

    -- extract the rootmost and end entity certificates
    local failedCertChain = report["failedCertChain"]
    local ee = nil
    local rootMost = nil
    if "table" == type(failedCertChain) then
      for i, cert in ipairs(failedCertChain) do
        if not ee then
          ee = cert
        end
        rootMost = cert
      end
    end

    -- get the issuer name from the root-most certificate
    if rootMost then
      local parsed = nil
      local ok, cert = read_cert(rootMost);
      if ok and cert then
        ok, parsed = parse_cert(cert)
      end
      if ok and parsed then
        local issuer = parsed["issuer"]
        if issuer then
          msg.Fields["rootIssuer"] = issuer:get_text("CN")
        end
      end
    end

    -- determine if the end entity subject or SAN matches the hostname
    local hostname = report["hostname"]
    if ee and hostname then
      local ok, cert = read_cert(ee);
      if ok and cert then
        local ok, matches = pcall(cert.check_host, cert, hostname)
        if ok and matches then
          msg.Fields["hostnameMatch"] = matches
        end
      end
    end

    local ok, err = pcall(inject_message, msg)
    if not ok then
        emsg.Fields.DecodeErrorType = "inject_message"
        emsg.Fields.DecodeError = err
        pcall(inject_message, emsg)
    end
    return 0
end

function decode(msg)
    hsr:decode_message(msg)
    transform_message(hsr)
end

return M
