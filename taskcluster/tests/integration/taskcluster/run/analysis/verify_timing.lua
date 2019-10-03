-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "string"
require "table"
require "math"

local captures = {""}
local results = {
    {component = 'task', subComponent = 'total', level = 0, duration = 240},
    {component = 'vcs', subComponent = 'clone', level = 2, duration = 1.37639},
    {component = 'vcs', subComponent = 'pull', level = 2, duration = 9.56564},
    {component = 'vcs', subComponent = 'update', level = 2, duration = 22.8238},
    {component = 'artifact', subComponent = 'download', level = 3, duration = 0.706, file = 'binutils.tar.xz'},
    {component = 'artifact', subComponent = 'download', level = 3, duration = 2.052, file = 'clang.tar.xz'},
    {component = 'gecko', subComponent = 'startup', level = 3, duration = 10.003},
    {component = 'test', subComponent = 'ref', level = 3, duration = 0.363, file = '/tests/reftest/tests/layout/reftests/css-disabled/fieldset/fieldset-enabled.html'},
    {component = 'test', subComponent = 'general', level = 3, duration = 2.311, file = '/tests/mochitest/orientation/test_bug507902.html'},
    {component = 'test', subComponent = 'gtest', level = 3, duration = 0.00999987, file = 'Variants/JsepSessionTest.TestBalancedBundle/14'},
    {component = 'hazard', subComponent = 'build', level = 3, duration = 72.802},
    {component = 'artifact', subComponent = 'upload', level = 3, duration = 2.56e-07, file = 'target_info.txt'},
    {component = 'artifact', subComponent = 'upload', level = 3, duration = 0.501425, file = 'target.reftest.tests.tar.gz'},
    {component = 'artifact', subComponent = 'upload', level = 3, duration = 5.12e-06, file = 'sccache.log'},
    {component = 'hazard', subComponent = 'heapwrites', level = 3, duration = 0.004},
    {component = 'hazard', subComponent = 'allFunctions', level = 3, duration = 0.171},
    {component = 'build_metrics', subComponent = 'configure', level = 3, duration = 1},
    {component = 'build_metrics', subComponent = 'pre-export', level = 3, duration = 1.1},
    {component = 'build_metrics', subComponent = 'export', level = 3, duration = 1.2},
    {component = 'build_metrics', subComponent = 'compile', level = 3, duration = 1.3},
    {component = 'build_metrics', subComponent = 'misc', level = 3, duration = 1.4},
    {component = 'build_metrics', subComponent = 'libs', level = 3, duration = 1.5},
    {component = 'build_metrics', subComponent = 'tools', level = 3, duration = 1.6},
    {component = 'build_metrics', subComponent = 'package-generated-sources', level = 3, duration = 1.7},
    {component = 'build_metrics', subComponent = 'buildsymbols', level = 3, duration = 1.8},
    {component = 'build_metrics', subComponent = 'package-tests', level = 3, duration = 1.9},
    {component = 'build_metrics', subComponent = 'package', level = 3, duration = 1.1},
    {component = 'build_metrics', subComponent = 'upload', level = 3, duration = 1.11},
    {component = 'build_metrics', subComponent = 'l10n-check', level = 3, duration = 1.12},
    {component = 'package', subComponent = 'tests', level = 3, duration = 2.09, file = 'target.reftest.tests.tar.gz'},
    {component = 'mozharness', subComponent = 'kitchen sink', level = 2, duration = 159.371},
    {component = 'task', subComponent = 'total', level = 0, duration = 251.494},
    {component = 'taskcluster', subComponent = 'setup', level = 1, duration = 14.449},
    {component = 'taskcluster', subComponent = 'task', level = 1, duration = 204.165},
    {component = 'taskcluster', subComponent = 'teardown', level = 1, duration = 32.88}
}

local cnt = 0
function process_message()
    local c = read_message("Fields[component]")
    local s = read_message("Fields[subComponent]")
    local l = read_message("Fields[level]")
    local d = read_message("Fields[duration]")
    local f = read_message("Fields[file]")
    cnt = cnt + 1

    local e = results[cnt].component
    if c ~= e then error(string.format("test: %d component expected: %s received: %s", cnt, tostring(e), tostring(c))) end

    e = results[cnt].subComponent
    if s ~= e then error(string.format("test: %d subComponent expected: %s received: %s", cnt, tostring(e), tostring(s))) end

    e = results[cnt].level
    if l ~= e then error(string.format("test: %d level expected: %d received: %d", cnt, e, l)) end

    e = results[cnt].duration
    if math.abs(d - e) >= 0.001 then error(string.format("test: %d duration expected: %g received: %g", cnt, e, d)) end

    e = results[cnt].file
    if f ~= e then error(string.format("test: %d file expected: %s received: %s", cnt, tostring(e), tostring(f))) end

    if f then
        captures[#captures + 1] = string.format("{component = '%s', subComponent = '%s', level = %d, duration = %g, file = '%s'}", c, s, l, d, f)
    else
        captures[#captures + 1] = string.format("{component = '%s', subComponent = '%s', level = %d, duration = %g}", c, s, l, d)
    end
    return 0
end

function timer_event(ns)
    inject_payload("txt", "captures", table.concat(captures, ",\n"))
    if cnt ~= #results then error(string.format("messages expected: %d received %d", #results, cnt)) end
end
