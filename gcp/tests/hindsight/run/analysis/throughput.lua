require "circular_buffer"

inputs = {}

local function get_input(logger)
    local i = inputs[logger]
    if not i then
        i = circular_buffer.new(60, 1, 1)
        i:set_header(1, "messages")
        inputs[logger] = i
    end
    return i
end


function process_message()
    local cb = get_input(read_message("Logger"))
    cb:add(read_message("Timestamp"), 1, 1)
    return 0
end


function timer_event(ns, shutdown)
    for k,v in pairs(inputs) do
        v:add(ns, 1, 0)
        inject_payload("cbuf", k, v)
    end
end

