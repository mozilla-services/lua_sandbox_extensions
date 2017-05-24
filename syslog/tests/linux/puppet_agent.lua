-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

local grammar = require "lpeg.linux.puppet_agent".syslog_grammar
local log
local fields

log = '(/Stage[main]/Nantes::Profile::Heka_base/Exec[setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/hekad]/returns) executed successfully'
fields = grammar:match(log)
assert(fields.puppet_resource_path == '/Stage[main]/Nantes::Profile::Heka_base/Exec[setcap CAP_NET_BIND_SERVICE=+eip /usr/bin/hekad]', fields.puppet_resource_path)
assert(fields.puppet_parameter == 'returns', fields.puppet_parameter)
assert(fields.puppet_change == 'executed successfully', fields.puppet_change)

log = "(/Stage[main]/Logstash::Service/Logstash::Service::Init[logstash]/Service[logstash]/ensure) ensure changed 'stopped' to 'running'"
fields = grammar:match(log)
assert(fields.puppet_resource_path == '/Stage[main]/Logstash::Service/Logstash::Service::Init[logstash]/Service[logstash]', fields.puppet_resource_path)
assert(fields.puppet_parameter == 'ensure', fields.puppet_parameter)
assert(fields.puppet_old_value == 'stopped', fields.puppet_old_value)
assert(fields.puppet_new_value == 'running', fields.puppet_new_value)

log = '(/Stage[main]/Elasticsearch::Config/File[/var/log/elasticsearch/test.log]/owner) current_value root, should be elasticsearch (noop)'
fields = grammar:match(log)
assert(fields.puppet_resource_path == '/Stage[main]/Elasticsearch::Config/File[/var/log/elasticsearch/test.log]', fields.puppet_resource_path)
assert(fields.puppet_parameter == 'owner', fields.puppet_parameter)
assert(fields.puppet_current_value == 'root', fields.puppet_current_value)
assert(fields.puppet_should_value == 'elasticsearch', fields.puppet_should_value)
assert(fields.puppet_noop == true, fields.puppet_noop)

log = '(/Stage[main]/Nantes::Profile::Heka_base/File[/etc/heka/conf.d/10_local_syslog.toml]/content)'
fields = grammar:match(log)
assert(fields.puppet_resource_path == '/Stage[main]/Nantes::Profile::Heka_base/File[/etc/heka/conf.d/10_local_syslog.toml]', fields.puppet_resource_path)
assert(fields.puppet_parameter == 'content', fields.puppet_parameter)

log = '(/Stage[main]/Nantes::Profile::Heka_base/File[/etc/heka/conf.d/10_net_syslog.toml]) Scheduling refresh of Service[heka]'
fields = grammar:match(log)
assert(fields.puppet_resource_path == '/Stage[main]/Nantes::Profile::Heka_base/File[/etc/heka/conf.d/10_net_syslog.toml]', fields.puppet_resource_path)
assert(fields.puppet_callback == 'refresh', fields.puppet_callback)
assert(fields.puppet_callback_target == 'Service[heka]', fields.puppet_callback_target)

log = "(Class[Logstash::Service]) Would have triggered 'refresh' from 1 events"
fields = grammar:match(log)
assert(fields.puppet_resource_path == 'Class[Logstash::Service]', fields.puppet_resource_path)
assert(fields.puppet_msg == 'Would have triggered', fields.puppet_msg)
assert(fields.puppet_callback == 'refresh', fields.puppet_callback)
assert(fields.puppet_events_count == 1, fields.puppet_events_count)

log = '(/Stage[main]/Nantes::Profile::Heka_base/File[/etc/heka/conf.d/10_net_syslog.toml]) Filebucketed /etc/heka/conf.d/10_net_syslog.toml to main with sum 70358a826b06f61f36bdc6aecaa3db14'
fields = grammar:match(log)
assert(fields.puppet_resource_path == '/Stage[main]/Nantes::Profile::Heka_base/File[/etc/heka/conf.d/10_net_syslog.toml]', fields.puppet_resource_path)
assert(fields.puppet_file_path == '/etc/heka/conf.d/10_net_syslog.toml', fields.puppet_file_path)
assert(fields.puppet_bucket == 'main', fields.puppet_bucket)
assert(fields.puppet_file_sum == '70358a826b06f61f36bdc6aecaa3db14', fields.puppet_file_sum)

log = 'Finished catalog run in 7.11 seconds'
fields = grammar:match(log)
assert(fields.puppet_msg == 'Finished catalog run', fields.puppet_msg)
assert(fields.puppet_benchmark_seconds == 7.11, fields.puppet_benchmark_seconds)
