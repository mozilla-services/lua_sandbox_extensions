# Lua CJSON Module

[CJSON](http://www.kyne.com.au/~mark/software/lua-cjson-manual.html) parser with the following modifications:
- Loads the cjson module in a global cjson table
- The encode buffer is limited to the sandbox output_limit.
- The decode buffer will be roughly limited to one half of the sandbox memory_limit.
- The NULL value is not decoded to cjson.null it is simply discarded.
  If the original behavior is desired use cjson.decode_null(true) to enable NULL decoding.
- The new() function has been disabled so only a single cjson parser can be created.
- The encode_keep_buffer() function has been disabled (the buffer is always reused).
