# GCP Pub/Sub Module

## Overview
Lua wrapper for the GCP gRPC Pub/Sub APIs.  The synchronous APIs are included
for test purposes, unless the traffic volume is tiny you would not want to use
them in production.

## Module

### Example Usage

```lua
require "gcp.pubsub"
```

### Functions

#### subscriber

Creates a GCP pub/sub subscriber.

```lua
local sub = gcp.pubsub.subscriber(channel, topic, subscription_name, max_async_requests)
```

*Arguments*
* channel (string) e.g. "pubsub.googleapis.com"
* topic (string) e.g. "projects/MyProject/topics/MyTopic" -- used to validate the subscription topic or create the subscription if necessary
* subscription_name (string) e.g. "MySubscription"
* max_async_requests (integer) Defaults to 20 (0 synchronous only)

*Return*
* subscriber (userdata) or an error is thrown

#### publisher

Creates a GCP pub/sub publisher.

```lua
local publisher = gcp.pubsub.publisher(channel, topic, max_async_requests)
```

*Arguments*
* channel (string) e.g. "pubsub.googleapis.com"
* topic (string) e.g. "projects/MyProject/topics/MyTopic"
* max_async_requests (integer) Defaults to 20 (0 synchronous only)
* batch_size (integer) Defaults to 1000

*Return*
* publisher (userdata) or an error is thrown

### subscriber Methods

#### pull/pull_sync

Reads a set of messages from the pub/sub topic.

```lua
local msgs, cnt = subscriber:pull(batch_size)
```

*Arguments*
* batch_size (integer) Number of items in a single request (1-1000)

*Returns*
* msgs (array/nil) One or more messages (can throw on error)
    The array contains an array for each message, column one is the data
    payload and column two is nil or the attribute table
    `msgs = { {data, attribute_table}, ...}`
* cnt (string/nil) Number of messsages returned

### publisher Methods

#### publish/publish_sync

Writes a message to the pub/sub topic.

```lua
local ret = publisher:publish(sequence_id, msg, attributes)
local ret = publisher:publish_sync(msg, attributes)
```

*Arguments*
* sequence_id Used with publish() only
    * lua_sandbox (lightuserdata) Opaque pointer for checkpointing
    * Lua 5.1 (number) range: zero to UINTPTR_MAX
* msg (string/(userdata/nil lua_sandbox only)) Message to send
    * nil uses msg.Payload as the msg and coverts everything else to string attributes
      (headers overwrite fields if there is a naming conflict)
* attributes (nil/table) Lua 5.1 only, map of string = tostring(val)

*Return*
* status_code (integer) or throws an error
    * sent (0)
    * retry (-3)
    * batched (-4)
    * async (-5)
* err (nil/string) error message

#### flush

Flushes the batched messages over the network.

```lua
publisher.flush()
```

*Arguments*
none

*Return*
* none or throws an error

#### poll

Polls the CompletionQueue to process the asynchronous publish responses. This
should be called after every send.

```lua
producer:poll()
```

*Arguments*
* none

*Return*
* Lua 5.1
    * sequence_id (number/nil) - Sequence number of the last message
      processed
    * failures (number) - number of messages that failed
* lua_sandbox
    * none - the checkpoint and error counts are automatically updated
