-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "kafka"
require "string"

local ok, err
ok, err = pcall(kafka.producer)
assert(err == "bad argument #0 to '?' (incorrect number of arguments)", err)

ok, err = pcall(kafka.producer, "")
assert(err == "invalid broker list", err)

ok, err = pcall(kafka.producer, "brokerlist", true)
assert(err == "bad argument #2 to '?' (table expected, got boolean)", err)

ok, err = pcall(kafka.producer, "local host", {["message.max.bytes"] = "foo"})
assert(err:match("^Failed to set message.max.bytes = foo"), err)

ok, err = pcall(kafka.producer, "local host", {["message.max.bytes"] = 1})
assert(err ==  'Failed to set message.max.bytes = 1 : Configuration property "message.max.bytes" value 1 is outside allowed range 1000..1000000000\n', err)

ok, err = pcall(kafka.producer, "local host", {["message.max.bytes"] = true})
assert(err:match("^Failed to set message.max.bytes = true"), err)

ok, err = pcall(kafka.producer, "brokerlist", {[assert] = true})
assert(err == "invalid config key type: function", err)

ok, err = pcall(kafka.producer, "brokerlist", {foo = assert})
assert(err == "invalid config value type: function", err)

ok, err = pcall(kafka.consumer)
assert(err == "bad argument #0 to '?' (incorrect number of arguments)", err)

ok, err = pcall(kafka.consumer, true, nil, nil)
assert(err == "bad argument #1 to '?' (string expected, got boolean)", err)

ok, err = pcall(kafka.consumer, "test", true, nil)
assert(err == "bad argument #2 to '?' (table expected, got boolean)", err)

ok, err = pcall(kafka.consumer, "test", {}, nil)
assert(err == "bad argument #2 to '?' (the topics array is empty)", err)

ok, err = pcall(kafka.consumer, "test", {"test"}, {})
assert(err == "group.id must be set", err)

ok, err = pcall(kafka.consumer, "", {"test"}, {["group.id"] = "foo"})
assert(err == "invalid broker list", err)

ok, err = pcall(kafka.consumer, "test", {"test"}, {["group.id"] = "foo"}, {["auto.offset.reset"] = "foobar"})
assert(err == 'Failed to set auto.offset.reset = foobar : Invalid value for configuration property "auto.offset.reset"', err)

ok, err = pcall(kafka.consumer, "test", {"test"}, {["group.id"] = "foo"}, {["auto.offset.reset"] = 0})
assert(err == 'Failed to set auto.offset.reset = 0 : Invalid value for configuration property "auto.offset.reset"', err)

ok, err = pcall(kafka.consumer, "test", {"test"}, {["group.id"] = "foo"}, {["auto.offset.reset"] = true})
assert(err == 'Failed to set auto.offset.reset = true : Invalid value for configuration property "auto.offset.reset"', err)

ok, err = pcall(kafka.consumer, "test", {"test"}, {["group.id"] = "foo"}, {["auto.offset.reset"] = assert})
assert(err == "invalid config value type: function", err)

ok, err = pcall(kafka.consumer, "test", {"test"}, {["group.id"] = "foo"}, {[assert] = true})
assert(err == "invalid config key type: function", err)

ok, err = pcall(kafka.consumer, "test", {"test:9000000000"}, {["group.id"] = "foo"})
assert(err == "invalid topic partition > INT32_MAX", err)

ok, err = pcall(kafka.consumer, "test", {"test:-1"}, {["group.id"] = "foo"})
assert(err == "invalid topic partition < 0", err)

ok, err = pcall(kafka.consumer, "test", {true}, {["group.id"] = "foo"})
assert(err == "topics must be an array of strings", err)

ok, err = pcall(kafka.consumer, "test", {"one", item = "test"}, {["group.id"] = "foo"})
assert(err == "topics must be an array of strings", err)

ok, err = pcall(kafka.consumer, "test", {"test"}, {["group.id"] = "foo", ["message.max.bytes"] = true})
assert(err:match("^Failed to set message.max.bytes = true"), err)
