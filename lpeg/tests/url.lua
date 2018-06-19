-- This Source Code Form is subject to the terms of the Mozilla Public
-- License, v. 2.0. If a copy of the MPL was not distributed with this
-- file, You can obtain one at http://mozilla.org/MPL/2.0/.

require "lpeg"
require "string"

local url = require "lpeg.url"

local urlparamtests = {
    {
        "/request/path?arg=one&arg2=two",
        { arg = "one", arg2 = "two" }
    },
    {
        "/request/path",
        nil
    },
    {
        "/request/path?",
        nil
    },
    {
        "/request/path?v=1&&&&&&&&w=2",
        { v = "1", w = "2" }
    },
    {
        "/request/path?v=",
        nil
    },
    {
        "/request/path?v=test%20value&arg=%40%40%40%40%40",
        { v = "test value", arg = "@@@@@" }
    },
    {
        "/request/path?v=test%00test",
        { v = "testtest" }
    },
    {
        "",
        nil
    }
}

local function urlparam()
    for _,test in ipairs(urlparamtests) do
        local v = url.urlparam:match(test[1])

        if test[2] then
            assert(v, string.format("%s: returned no parsed argument", test[1]))
            for argk, argv in pairs(test[2]) do
                assert(v[argk], string.format("%s: argument %s missing", test[1], argk))
                assert(v[argk] == argv, string.format("%s: wanted %s for %s, got %s",
                    test[1], argv, argk, v[argk]))
            end
        else
            -- we should have no arguments being returned
            if v then
                local cnt = 0
                for i,_ in ipairs(v) do cnt = cnt + 1 end
                assert(cnt == 0, string.format("%s: returned arguments", test[1]))
            end
        end
    end
end

local urltests = {
    {
        "http://example.host",
        {
            scheme      = "http",
            hostname    = "example.host"
        }
    },
    {
        "http://example.host/request/path",
        {
            scheme      = "http",
            hostname    = "example.host",
            path        = "/request/path"
        }
    },
    {
        "http://example.host/request/path?arg=one&arg=two",
        {
            scheme      = "http",
            hostname    = "example.host",
            path        = "/request/path?arg=one&arg=two"
        }
    },
    {
        "ftp://example.host:2121/request/path",
        {
            scheme      = "ftp",
            hostname    = "example.host",
            path        = "/request/path",
            port        = "2121"
        }
    },
    {
        "http://example.host:8080/?m=v",
        {
            scheme      = "http",
            hostname    = "example.host",
            path        = "/?m=v",
            port        = "8080"
        }
    },
    {
        "http://username:password@example.host:8080/?m=v",
        {
            scheme      = "http",
            hostname    = "example.host",
            path        = "/?m=v",
            port        = "8080",
            userinfo    = "username:password"
        }
    },
    {
        "http://username:password@example.host",
        {
            scheme      = "http",
            hostname    = "example.host",
            userinfo    = "username:password"
        }
    },
    {
        "http://127.0.0.1/",
        {
            scheme      = "http",
            hostname    = "127.0.0.1",
            path        = "/"
        }
    },
    {
        "http://127.0.0.1:8080",
        {
            scheme      = "http",
            hostname    = "127.0.0.1",
            port        = "8080"
        }
    },
}

local function urltest()
    for _,test in ipairs(urltests) do
        local m = url.url:match(test[1])

        for k,v in pairs(test[2]) do
            assert(m[k], string.format("%s: value %s missing", test[1], k))
            assert(m[k] == v, string.format("%s: wanted %s for %s, got %s", test[1], v, k, m[k]))
        end
    end
end

local reqtests = {
    {
        "GET http://example.host/m?param=value&test=1 HTTP/1.1",
        {
            method      = "GET",
            scheme      = "http",
            hostname    = "example.host",
            path        = "/m?param=value&test=1",
            protocol    = "HTTP/1.1"
        }
    },
    {
        "GET /",
        {
            method      = "GET",
            path        = "/"
        }
    },
    {
        "GET /v?m=a",
        {
            method      = "GET",
            path        = "/v?m=a"
        }
    }
}

local function reqtest()
    for _,test in ipairs(reqtests) do
        local m = url.request:match(test[1])

        for k,v in pairs(test[2]) do
            assert(m[k], string.format("%s: value %s missing", test[1], k))
            assert(m[k] == v, string.format("%s: wanted %s for %s, got %s", test[1], v, k, m[k]))
        end
    end
end

urlparam()
urltest()
reqtest()
