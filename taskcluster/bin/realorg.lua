-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local cjson = require "cjson"

local fh = assert(io.open("realorg.json", "r"))
local j = fh:read("*a")
local j = cjson.decode(j)

local employees = {}
local function get_employee(email, name, mgr)
    local t = employees[email]
    if not t then
        t = {manager = mgr, name = name, email = email}
        employees[email] = t
    end
    if not t.manager and (t ~= mgr) then t.manager = mgr end
    return t
end

for i, user in ipairs(j.employees) do
    local memail = user.manager.dn
    local mname = string.gsub(user.manager.cn, '"', "'")
    if memail then
       memail = string.match(memail, "mail=([^,\"]+)")
    end
    local name = string.gsub(user.cn, '"', "'")
    local mgr = get_employee(memail, mname, nil)
    local emp = get_employee(user.mail, name, mgr)
end


for email, data in pairs(employees) do
    local mgr = data.manager
    if mgr then
        local hier = {}
        repeat
            hier[#hier + 1] = '"' .. mgr.name .. '"'
            --print(email, data.name, mgr.email, mgr.name)
            if mgr.manager then
                mgr = employees[mgr.manager.email]
            else
                --print("no manager", mgr.email)
                mgr = nil
            end
        until not mgr
        print(string.format('{"email":"%s","name":"%s","manager":[%s]}', email, data.name, table.concat(hier, ",")))
    end
end

