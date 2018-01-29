-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

--[[
# Module to test the printf.load_messages

--]]

-- Imports
local M = {}
setfenv(1, M) -- Remove external access to contain everything in the module

printf_messages = {
    {false, "status", "one", "two", "three"},
}

return M
