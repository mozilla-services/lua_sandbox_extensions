-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"

local msg = {
  Payload = '127.0.0.1 - [10/Feb/2014:08:46:41 -0800] "GET / HTTP/1.1" 304 0 "-" "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:26.0) Gecko/20100101 Firefox/26.0"',
  Fields  = {
      body_bytes_sent = 222,
      request = "GET / HTTP/1.1",
      remote_addr = "127.0.0.1",
      remote_user = "-",
      status = 304,
      http_user_agent = "Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:26.0) Gecko/20100101 Firefox/26.0",
      referer = "-",
      other = "bogus"
  }
}

function process_message()
  inject_message(msg)
  return 0
end
