--[[
# IP / CIDR Utility Module

iputils can be used for verifying if an IP address is part of a specific set
of CIDR / subnets.

This module is based on lua-resty-iputils, which can be found at
https://github.com/hamishforbes/lua-resty-iputils/.

## Functions

### parse_cidr

Parse an array of CIDR subnet specifications where each entry is a string.
Returns a list of the subnets in binary form for later use in ip_in_cidrs.

If a subnet mask is not specified with a subnet entry, it will default to 32.

```lua
local ipu = require("iputils")

local subnets = ipu.parse_cidrs({ "10.0.0.0/24", "192.168.1.0/24" })
```

*Arguments*
- cidrs (table) - Array of subnets to parse, each in string format

*Return*
- bincidrs (table) - Parsed subnets in binary format

### ip_in_cidrs

Returns true if an IP address is in a list of binary CIDR representations
as returned by parse_cidrs. Returns false if not present, or nil if an
error occurs.

```lua
local ipu = require("iputils")

local subnets = ipu.parse_cidrs({ "10.0.0.0/24", "192.168.1.0/24" })
inlist = ipu.ip_in_cidrs("10.0.0.1", subnets)
```

*Arguments*
- ip (string) - IP address to verify
- bincidrs (table) - Parsed subnets returned from parse_cidrs

*Returns*
- flag (boolean) - True if in subnets, false if not, nil if error

--]]

local ipairs    = ipairs
local tonumber  = tonumber
local tostring  = tostring
local type      = type

local ipa       = require("lpeg.ip_address")
local bit       = require("bit")
local string    = require("string")

local M = {}
setfenv(1, M)


-- Precompute binary subnet masks
local bin_masks = {}
for i=0,32 do
    bin_masks[tostring(i)] = bit.lshift((2^i)-1, 32-i)
end


-- Precompute inverted binary subnet masks
local bin_inverted_masks = {}
for i=0,32 do
    local i = tostring(i)
    bin_inverted_masks[i] = bit.bxor(bin_masks[i], bin_masks["32"])
end


local function split_octets(input)
    return ipa.v4_octets:match(input)
end


local function unsign(bin)
    if bin < 0 then
        return 4294967296 + bin
    end
    return bin
end


local function ip2bin(ip)
    if type(ip) ~= "string" then
        return nil
    end

    local octets = split_octets(ip)
    if not octets or #octets ~= 4 then
        return nil
    end

    -- Return the binary representation of an IP and a table of binary octets
    local bin_ip = 0

    for i,octet in ipairs(octets) do
        bin_ip = bit.bor(bit.lshift(octet, 8*(4-i) ), bin_ip)
    end

    return unsign(bin_ip), octets
end


local function split_cidr(input)
    local pos = string.find(input, "/", 0, true)
    if not pos then
        return { input }
    end
    return { string.sub(input, 1, pos-1), string.sub(input, pos+1, -1) }
end


local function parse_cidr(cidr)
    local mask_split = split_cidr(cidr, '/')
    local net        = mask_split[1]
    local mask       = mask_split[2] or "32"
    local mask_num   = tonumber(mask)

    if not mask_num or (mask_num > 32 or mask_num < 0) then
        return nil
    end

    local bin_net = ip2bin(net) -- Convert IP to binary
    if not bin_net then
        return nil
    end
    local bin_mask     = bin_masks[mask] -- Get masks
    local bin_inv_mask = bin_inverted_masks[mask]

    local lower = bit.band(bin_net, bin_mask) -- Network address
    local upper = bit.bor(lower, bin_inv_mask) -- Broadcast address
    return unsign(lower), unsign(upper)
end


function parse_cidrs(cidrs)
    local out = {}
    local i = 1
    for _,cidr in ipairs(cidrs) do
        local lower, upper = parse_cidr(cidr)
        if not lower or not upper then
            return nil
        else
            out[i] = { lower, upper }
            i = i + 1
        end
    end
    return out
end


function ip_in_cidrs(ip, cidrs)
    local bin_ip, bin_octets = ip2bin(ip)
    if not bin_ip then
        return nil, bin_octets
    end

    for _,cidr in ipairs(cidrs) do
        if bin_ip >= cidr[1] and bin_ip <= cidr[2] then
            return true
        end
    end
    return false
end


return M
