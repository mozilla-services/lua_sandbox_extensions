# AWS Lua Module

## Overview
Lua wrapper for the aws-cpp-sdk library.

## Module

### Example Usage

```lua
require "aws.kinesis"

local reader = aws.kinesis.simple_consumer(streamName)
while true do
    local records, cp = reader:receive()
    for i, data in ipairs(records) do
      -- process data
    end
end
```

### Functions

#### simple_consumer

Creates a simple Kinesis consumer. This client will consume all shards and
properly handle splits/merges. However, since it is not distributed it is
limited to streams with up to ~50 shards on a 1Gb network interface.

```lua
local reader = aws.kinesis.simple_consumer(streamName, iteratorType, checkpoints, clientConfig, credentialProvider)
```

*Arguments*
* streamName (string) Kinesis stream name
* iteratorType (string/number/nil)
    * "TRIM_HORIZON" (default)
    * "LATEST"
    * number (time_t timestamp) converts to AT_TIMESTAMP iterator
* checkpoints (string/nil) Value returned by receive()
* clientConfig (table/nil) https://sdk.amazonaws.com/cpp/api/LATEST/struct_aws_1_1_client_1_1_client_configuration.html
* credentialProvider (enum/nil)
    * CHAIN
    * INSTANCE (default)

*Return*
* reader (userdata) or an error is thrown

#### simple_producer

Creates a simple Kinesis producer.

```lua
local writer = aws.kinesis.simple_producer(streamName, clientConfig, credentialProvider)
```

*Arguments*
* clientConfig (table/nil) - https://sdk.amazonaws.com/cpp/api/LATEST/struct_aws_1_1_client_1_1_client_configuration.html
* credentialProvider (enum/nil)
    * CHAIN
    * INSTANCE (default)

*Return*
* writer (userdata) or an error is thrown

### simple_consumer Methods

#### receive

Reads a set of records from the Kinesis stream.

```lua
local records, checkpoints = reader:receive()
```

*Arguments*
* none

*Returns*
* records (array) Zero or more data records (throws on a non recoverable error)
* checkpoints (string/nil) TSV of shardId, sequenceId items (one per line)

### simple_producer Methods

#### send

Writes a single record at a time to the Kinesis stream. Low volume, limited to
1000 records per second.

```lua
local err = writer:send(streamName, data, key)
```

*Arguments*
* streamName (string) Kinesis stream name
* data (string) Data to send
* key (string) Key for shard partitioning

*Return*
* err (string/nil) nil on success
