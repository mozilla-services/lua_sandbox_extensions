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
local reader = aws.kinesis.simple_consumer(streamName, iteratorType, checkpoints, clientConfig, credentialProvider, roleArn)
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
    * INSTANCE (default)
    * CHAIN
    * ROLE
* roleArn (nil/string) Only used when credentialProvider == ROLE

*Return*
* reader (userdata) or an error is thrown

#### simple_producer

Creates a simple Kinesis producer.

```lua
local writer = aws.kinesis.simple_producer(clientConfig, credentialProvider, roleArn)
```

*Arguments*
* clientConfig (table/nil) https://sdk.amazonaws.com/cpp/api/LATEST/struct_aws_1_1_client_1_1_client_configuration.html
* credentialProvider (enum/nil)
    * INSTANCE (default)
    * CHAIN
    * ROLE
* roleArn (nil/string) Only used when credentialProvider == ROLE

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
* records (array) Zero or more data records (throws on error)
* checkpoints (string/nil) TSV of shardId, sequenceId items (one per line)

### simple_producer Methods

#### send

Writes a record to the Kinesis stream.

```lua
local rv, err = writer:send(streamName, data, key)
```

*Arguments*
* streamName (string) Kinesis stream name
* data (string) Data to send
* key (string) Key for shard partitioning

*Return*
* rv  (integer) Return value
    * 0 - success
    * -1 - error
    * -3 - retry
* err (string/nil) nil on success

#### open_shard_count

Returns the open number of shards in the stream.

```lua
local cnt = writer:open_shard_count(streamName)
```

*Arguments*
* streamName (string) Kinesis stream name

*Return*
* cnt (integer/nil) Number of open shards (nil when the request can/should be retried, throws on fatal error)
* err (string/nil) nil on success
