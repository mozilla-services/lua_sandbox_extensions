require "string"

-- TODO: Recieve more than one message, see `input/new_doctype_monitor.lua`
local results = {
    "test_message_1",
    "test_message_2\ntest_message_3",
    "test_message_5"
}

local cnt = 0
function process_message()
    cnt = cnt + 1
    local payload = read_message("Payload")
    assert(results[cnt] == payload, string.format("expected: %s actual: %s", results[cnt], payload))
    return 0
end


function timer_event()
    assert(cnt == 1, string.format("%d out of 1 tests ran", cnt))
end
