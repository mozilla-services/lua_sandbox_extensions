require "string"
local s = '127.0.0.1 - - [10/Feb/2014:08:46:41 -0800] "GET / HTTP/1.1" 304 0 "-" "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:26.0) Gecko/20100101 Firefox/26.0 %d'

local msg = {
  Payload = ""
}
function process_message()
  for i=1, 10000000 do
  --for i=1, 1000000 do
  --for i=1, 1 do
    msg.Payload = string.format(s, i)
    inject_message(msg)
  end
  return 0
end


