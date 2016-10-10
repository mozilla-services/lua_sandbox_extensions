# Lua Kafka Module

## Overview
A Kafka producer/consumer library for Lua

## Module

### Example Usage
```lua
require "kafka"
local consumer = kafka.consumer("localhost:9092",
                                {"test"},
                                {["group.id"] = "example"},
                                {["auto.offset.reset"] = "smallest"}
                               )
msg, topic, partition, key = consumer:receive()
if msg then
    -- consume msg
end
```

### Functions

#### producer

Creates a Kafka producer.

```lua
local brokerlist    = "localhost:9092"
local producer_conf = {
    ["queue.buffering.max.messages"] = 20000,
    ["batch.num.messages"] = 200,
    ["message.max.bytes"] = 1024 * 1024,
    ["queue.buffering.max.ms"] = 10,
    ["topic.metadata.refresh.interval.ms"] = -1,
}
local producer = kafka.producer(brokerlist, producer_conf)

```

*Arguments*
* brokerlist (string) - [librdkafka broker string](https://github.com/edenhill/librdkafka/blob/master/src/rdkafka.h#L2205)
* producer_conf (table) - [librdkafka producer configuration](https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md#global-configuration-properties)

*Return*
* producer (userdata) - Kafka producer or an error is thrown

#### consumer

Creates a Kafka consumer.

```lua
local brokerlist    = "localhost:9092"
local topics        = {"test"}
local consumer_conf = {["group.id"] = "test_g1"})
local topic_conf    = nil
local consumer   = kafka.consumer(brokerlist, topics, consumer_conf, topic_conf)

```

*Arguments*
* brokerlist (string) - [librdkafka broker string](https://github.com/edenhill/librdkafka/blob/master/src/rdkafka.h#L2205)
* topics (array of 'topic[:partition]' strings) - Balanced consumer group mode a
  consumer can only subscribe on topics, not topics:partitions. The partition 
  syntax is only used for manual assignments (without balanced consumer groups).
* consumer_conf (table) - must contain 'group.id' see: [librdkafka consumer configuration](https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md#global-configuration-properties)
* topic_conf (table, optional) - [librdkafka topic configuration](https://github.com/edenhill/librdkafka/blob/master/CONFIGURATION.md#topic-configuration-properties)

*Return*
* consumer (userdata) - Kafka consumer or an error is thrown

#### version
```lua
require "kafka"
local v = kafka.version()
-- v == "1.0.0"
```

Returns a string with the running version of Kafka module.

*Arguments*
- none

*Return*
- Semantic version string

### Producer Methods

#### create_topic

Creates a topic to be used by a producer, no-op if the topic already exists.

```lua
producer:create_topic(topic) -- creates the topic if it does not exist

```

*Arguments*
* topic (string) - Name of the topic

*Return*
* none


#### has_topic

Tests if a producer is managing a topic.

```lua
local b = producer:has_topic(topic)

```

*Arguments*
* topic (string) - Name of the topic

*Return*
* bool - True if the producer is managing a topic with the specificed name


#### destroy_topic

Removes a topic from the producer.

```lua
producer:destroy_topic(topic)

```

*Arguments*
* topic (string) - Name of the topic

*Return*
* none - no-op on non-existent topic


#### send

Sends a message using the specified topic.

```lua
local ret = producer:send(topic, -1, sequence_id, message)

```

*Arguments*
* topic (string) - Name of the topic
* partition (number) - Topic partition number (-1 for automatic assignment)
* sequence_id 
    * lua_sandbox (lightuserdata/nil/none) - Opaque pointer for checkpointing
    * Lua 5.1 (number/nil/none) - range: zero to UINTPTR_MAX
* message
    * heka_sandbox (string/table)
        * string - message to send
        * table - zero copy specifier (table of read_message arguments)
    * Lua 5.1 (string) - Message to send 


*Return*
* ret (number) - 0 on success or errno
  - ENOBUFS (105) maximum number of outstanding messages has been reached
  - EMSGSIZE (90) message is larger than configured max size
  - ESRCH (2) requested partition is unknown in the Kafka cluster
  - ENOENT (3) topic is unknown in the Kafka cluster

#### poll

Polls the provided Kafka producer for events and invokes callback.  This should
be called after every send.

```lua
local failures, sequence_id = producer:poll()

```

*Arguments*
    * Lua 5.1
        * timeout (number/nil/none) - timeout in ms (default 0 non-blocking).
          Use -1 to wait indefinitely.
    * heka_sandbox
        * none

*Return*
    * Lua 5.1
        * sequence_id (number/nil) - Sequence number of the last message
          processed
        * failures (number) - number of messages that failed
    * heka_sandbox
        * none - the checkpoint and error counts are automatically updated

### Consumer Methods

#### receive

Receives a message from the specified Kafka topic(s).

```lua
local msg, topic, partition, key = consumer:receive()

```

*Arguments*
* none

*Return*
* msg (string) - Kafka message payload
* topic (string) - Topic name the message was received from
* partition (number) - Topic partition the message was received from
* key (string) - Message key (if available)
