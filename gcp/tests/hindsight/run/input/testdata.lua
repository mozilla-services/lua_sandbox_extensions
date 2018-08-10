require "string"

local msg = {
  Payload = '127.0.0.1 - [10/Feb/2014:08:46:41 -0800] "GET / HTTP/1.1" 304 0 "-" "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:26.0) Gecko/20100101 Firefox/26.0',
  Fields  = {
      id  = {value = 0, value_type = 2},
      strs = {value = {"one", "two", "thr\tee"}},
      ints = {value = {1, 2, 3}, value_type = 2},
      dbls = {value = {1.1, 1.2, 1.3}, value_type = 3},
      bools = {value = {true, false, true}, value_type = 4},
      bin = {value = "", value_type = 1}
  }
}

function process_message()
  for i=1, 10000000 do
  --for i=1, 1000000 do
  --for i=1, 1 do
    msg.Fields.id.value = i
    inject_message(msg)
  end
  return 0
end


