/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua GCP Stackdriver wrapper implementation @file */

extern "C"
{
#include "lauxlib.h"
#include "lua.h"

#ifdef LUA_SANDBOX
#include <luasandbox.h>
#include <luasandbox/heka/sandbox.h>
#include <luasandbox_output.h>
#endif

int luaopen_gcp_logging(lua_State *lua);
}

#include <chrono>
#include <exception>
#include <google/logging/v2/logging.grpc.pb.h>
#include <google/protobuf/timestamp.pb.h>
#include <grpc++/grpc++.h>
#include <memory>

#ifdef LUA_SANDBOX
#include "common.h"
#endif

using google::logging::v2::LoggingServiceV2;
using google::logging::v2::WriteLogEntriesRequest;
using google::logging::v2::WriteLogEntriesResponse;
using google::logging::v2::ListLogEntriesRequest;
using google::logging::v2::ListLogEntriesResponse;
using grpc::ClientContext;

static const char *mt_writer = "mozsvc.gcp.logging.writer";

struct async_write_request {
  void                    *sequence_id;
  WriteLogEntriesRequest  *request;
  ClientContext           ctx;
  WriteLogEntriesResponse response;
  grpc::Status            status;
  std::unique_ptr<grpc::ClientAsyncResponseReader<WriteLogEntriesResponse> > rpc;
};

struct writer {
#ifdef LUA_SANDBOX
  const lsb_logger *logger;
#endif
  WriteLogEntriesRequest                  *request;
  std::unique_ptr<LoggingServiceV2::Stub> stub;
  int                                     batch_size;
  int                                     max_async_requests;
  int                                     outstanding_requests;
  grpc::CompletionQueue                   cq;
};

typedef struct writer_wrapper
{
  writer *w;
} writer_wrapper;


static int writer_new(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n >= 1 && n <= 3, n, "incorrect number of arguments");
  const char *channel = luaL_checkstring(lua, 1);
  int max_async       = luaL_optint(lua, 2, 20);
  int batch_size      = luaL_optint(lua, 3, 1000);

  writer_wrapper *ww = static_cast<writer_wrapper *>(lua_newuserdata(lua, sizeof*ww));
  ww->w = new struct writer;
  if (!ww->w) return luaL_error(lua, "memory allocation failed");

  ww->w->max_async_requests = max_async;
  ww->w->batch_size = batch_size;
  ww->w->outstanding_requests = 0;
  ww->w->request = new WriteLogEntriesRequest;
#ifdef LUA_SANDBOX
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_THIS_PTR);
  lsb_lua_sandbox *lsb = reinterpret_cast<lsb_lua_sandbox *>(lua_touserdata(lua, -1));
  lua_pop(lua, 1); // remove this ptr
  if (!lsb) {
    return luaL_error(lua, "invalid " LSB_THIS_PTR);
  }
  ww->w->logger = lsb_get_logger(lsb);
#endif
  luaL_getmetatable(lua, mt_writer);
  lua_setmetatable(lua, -2);

  bool err = false;
  try {
    auto creds = grpc::GoogleDefaultCredentials();
    ww->w->stub = std::make_unique<LoggingServiceV2::Stub>(grpc::CreateChannel(channel, creds));
  } catch (std::exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown exception");
    err = true;
  }
  return err ? lua_error(lua) : 1;
}


static grpc::CompletionQueue::NextStatus
writer_poll_internal(lua_State *lua, int timeout)
{
  writer_wrapper *ww = static_cast<writer_wrapper *>(luaL_checkudata(lua, 1, mt_writer));

  grpc::CompletionQueue::NextStatus status = grpc::CompletionQueue::NextStatus::TIMEOUT;
  if (ww->w->max_async_requests == 0) {
    luaL_error(lua, "async is disabled");
    return status; // never reached
  }

  int failures = 0;
  void *sequence_id = nullptr;
  bool err = false;

  try {
    void *tag;
    bool ok;
    std::chrono::system_clock::time_point now = std::chrono::system_clock::now() + std::chrono::milliseconds(timeout);
    while (grpc::CompletionQueue::NextStatus::GOT_EVENT == (status = ww->w->cq.AsyncNext(&tag, &ok, now))) {
      if (ok) {
        auto awr = static_cast<struct async_write_request *>(tag);
        if (awr->status.ok()) {
          sequence_id = awr->sequence_id;
        } else {
          ++failures;
#ifdef LUA_SANDBOX
          ww->w->logger->cb(ww->w->logger->context, "gcp.logging", 3,
                            "write error\t%d\t%s", (int)awr->status.error_code(),
                            awr->status.error_message().c_str());
#endif
        }
        delete awr->request;
        delete awr;
            --ww->w->outstanding_requests;
      }
    }
  } catch (std::exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown exception");
    err = true;
  }
  if (err) lua_error(lua);

#ifdef LUA_SANDBOX
  if (sequence_id) {
    lua_getfield(lua, LUA_GLOBALSINDEX, LSB_HEKA_UPDATE_CHECKPOINT);
    if (lua_type(lua, -1) == LUA_TFUNCTION) {
      lua_pushlightuserdata(lua, sequence_id);
      lua_pushinteger(lua, failures);
      if (lua_pcall(lua, 2, 0, 0)) {
        lua_error(lua);
      }
    } else {
      luaL_error(lua, LSB_HEKA_UPDATE_CHECKPOINT " was not found");
    }
    lua_pop(lua, 1);
  }
#else
  if (timeout < 0) { // not shutting down
    if (sequence_id) {
      uintptr_t sequence_id = (uintptr_t)sequence_id;
      lua_pushnumber(lua, (lua_Number)sequence_id);
    } else {
      lua_pushnil(lua);
    }
    lua_pushinteger(lua, failures);
  }
}
#endif
  return status;
}


void write_async(writer_wrapper *ww, void *sequence_id)
{
  auto awr = new struct async_write_request;
  awr->request = ww->w->request;
  ww->w->request = new WriteLogEntriesRequest;
  awr->sequence_id = sequence_id;
  awr->rpc = ww->w->stub->AsyncWriteLogEntries(&awr->ctx, *awr->request, &ww->w->cq);
  awr->rpc->Finish(&awr->response, &awr->status, (void *)awr);
  ++ww->w->outstanding_requests;
}


bool write_sync(lua_State *lua, writer_wrapper *ww)
{
  bool err = false;
  ClientContext ctx;
  WriteLogEntriesResponse response;
  auto status = ww->w->stub->WriteLogEntries(&ctx, *ww->w->request, &response);
  if (!status.ok()) {
    lua_pushstring(lua, status.error_message().c_str());
    err = true;
  }
  ww->w->request->Clear();
  return err;
}


static void* get_sequence_id(lua_State *lua, int idx)
{
#ifdef LUA_SANDBOX
  luaL_checktype(lua, idx, LUA_TLIGHTUSERDATA);
  return lua_touserdata(lua, idx);
#else
  lua_Number sid = lua_tonumber(lua, idx);
  if (sid < 0 || sid > UINTPTR_MAX) {
    luaL_error(lua, "sequence_id out of range");
  }
  return (uintptr_t)sid;
#endif
}


static google::logging::type::LogSeverity get_severity(int syslog_severity)
{
  switch (syslog_severity) {
  case 0:
    return google::logging::type::EMERGENCY;
  case 1:
    return google::logging::type::ALERT;
  case 2:
    return google::logging::type::CRITICAL;
  case 3:
    return google::logging::type::ERROR;
  case 4:
    return google::logging::type::WARNING;
  case 5:
    return google::logging::type::NOTICE;
  case 6:
    return google::logging::type::INFO;
  case 7:
    return google::logging::type::DEBUG;
  }
  return google::logging::type::DEFAULT;
}


static bool add_labels(lua_State *lua, int idx, MapString *labels)
{
  lua_pushnil(lua);
  while (lua_next(lua, idx) != 0) {
    if (lua_type(lua, -2) != LUA_TSTRING) {
      lua_pushinteger(lua, -1);
      lua_pushstring(lua, "label key must be a string");
      return false;
    }
    labels->insert(MapPairString(lua_tostring(lua, -2), lua_tostring(lua, -1)));
    lua_pop(lua, 1);
  }
  return true;
}


static int send(lua_State *lua, bool async_api)
{
  writer_wrapper *ww = static_cast<writer_wrapper *>(luaL_checkudata(lua, 1, mt_writer));

  bool err = false;
  void *sequence_id = nullptr;
  int msg_idx = 2;
  if (async_api) {
    if (ww->w->max_async_requests == 0) {
      return luaL_error(lua, "async is disabled");
    }
    if (ww->w->outstanding_requests >= ww->w->max_async_requests) {
      lua_pushinteger(lua, -3);
      lua_pushstring(lua, "max_async_requests");
      return 2;
    }
    sequence_id = get_sequence_id(lua, msg_idx++);
  }
  luaL_checktype(lua, msg_idx, LUA_TTABLE);

  try {
    if (ww->w->request->entries_size() < ww->w->batch_size) {
      auto msg = ww->w->request->add_entries();

      lua_getfield(lua, msg_idx, "logName");
      if (lua_type(lua, -1) != LUA_TSTRING) {
        lua_pushinteger(lua, -1);
        lua_pushstring(lua, "missing logName");
        return 2;
      }
      msg->set_log_name(lua_tostring(lua, -1));
      lua_pop(lua, 1);

      lua_getfield(lua, msg_idx, "resource");
      if (lua_type(lua, -1) != LUA_TTABLE) {
        lua_pushinteger(lua, -1);
        lua_pushstring(lua, "missing resource");
        msg->Clear();
        return 2;
      }

      lua_getfield(lua, -1, "type");
      if (lua_type(lua, -1) != LUA_TSTRING) {
        lua_pushinteger(lua, -1);
        lua_pushstring(lua, "missing resource type");
        msg->Clear();
        return 2;
      }

      lua_getfield(lua, -2, "labels");
      if (lua_type(lua, -1) != LUA_TTABLE) {
        lua_pushinteger(lua, -1);
        lua_pushstring(lua, "missing resource labels");
        msg->Clear();
        return 2;
      }

      auto mr = new google::api::MonitoredResource;
      mr->set_type(lua_tostring(lua, -2));
      auto labels = mr->mutable_labels();
      if (!add_labels(lua, msg_idx + 3, labels)) return 2;
      msg->set_allocated_resource(mr);
      lua_pop(lua, 3);

      lua_getfield(lua, msg_idx, "timestamp");
      if (lua_type(lua, -1) == LUA_TNUMBER) {
        int64_t ns = (int64_t)lua_tonumber(lua, -1);
        auto ts = new google::protobuf::Timestamp;
        ts->set_seconds(ns / 1000000000);
        ts->set_nanos(ns % 1000000000);
        msg->set_allocated_timestamp(ts);
      }
      lua_pop(lua, 1);

      lua_getfield(lua, -1, "severity");
      if (lua_type(lua, -1) == LUA_TNUMBER) {
        msg->set_severity(get_severity(lua_tointeger(lua, -1)));
      }
      lua_pop(lua, 1);

      lua_getfield(lua, msg_idx, "insertId");
      if (lua_type(lua, -1) == LUA_TSTRING) {
        msg->set_insert_id(lua_tostring(lua, -1));
      }
      lua_pop(lua, 1);

      lua_getfield(lua, msg_idx, "httpRequest");
      if (lua_type(lua, -1) == LUA_TTABLE) {
        auto httpr = msg->mutable_http_request();
        const char *s;

        lua_getfield(lua, -1, "requestMethod");
        s = lua_tostring(lua, -1);
        if (s) httpr->set_request_method(s);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "requestUrl");
        s = lua_tostring(lua, -1);
        if (s) httpr->set_request_url(s);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "requestSize");
        if (lua_type(lua, -1) == LUA_TNUMBER) {
          httpr->set_request_size(lua_tonumber(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "status");
        if (lua_type(lua, -1) == LUA_TNUMBER) {
          httpr->set_status(lua_tointeger(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "responseSize");
        if (lua_type(lua, -1) == LUA_TNUMBER) {
          httpr->set_response_size(lua_tonumber(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "userAgent");
        s = lua_tostring(lua, -1);
        if (s) httpr->set_user_agent(s);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "remoteIp");
        s = lua_tostring(lua, -1);
        if (s) httpr->set_remote_ip(s);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "serverIp");
        s = lua_tostring(lua, -1);
        if (s) httpr->set_server_ip(s);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "referer");
        s = lua_tostring(lua, -1);
        if (s) httpr->set_referer(s);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "latency");
        if (lua_type(lua, -1) == LUA_TNUMBER) {
          auto l = httpr->mutable_latency();
          l->set_nanos(lua_tointeger(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "cacheLookup");
        if (lua_type(lua, -1) == LUA_TBOOLEAN) {
          httpr->set_cache_lookup(lua_toboolean(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "cacheHit");
        if (lua_type(lua, -1) == LUA_TBOOLEAN) {
          httpr->set_cache_hit(lua_toboolean(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "cacheValidatedWithOriginServer");
        if (lua_type(lua, -1) == LUA_TBOOLEAN) {
          httpr->set_cache_validated_with_origin_server(lua_toboolean(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "cacheFillBytes");
        if (lua_type(lua, -1) == LUA_TNUMBER) {
          httpr->set_cache_fill_bytes(lua_tonumber(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "protocol");
        s = lua_tostring(lua, -1);
        if (s) httpr->set_protocol(s);
        lua_pop(lua, 1);
      }
      lua_pop(lua, 1);

      lua_getfield(lua, msg_idx, "labels");
      if (lua_type(lua, -1) == LUA_TTABLE) {
        auto labels = msg->mutable_labels();
        if (!add_labels(lua, msg_idx + 1, labels)) return 2;
      }
      lua_pop(lua, 1);

      lua_getfield(lua, msg_idx, "operation");
      if (lua_type(lua, -1) == LUA_TTABLE) {
        auto op = msg->mutable_operation();
        const char *s;

        lua_getfield(lua, -1, "id");
        s = lua_tostring(lua, -1);
        if (s) op->set_id(s);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "producer");
        s = lua_tostring(lua, -1);
        if (s) op->set_producer(s);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "first");
        if (lua_type(lua, -1) == LUA_TBOOLEAN) {
          op->set_first(lua_toboolean(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "last");
        if (lua_type(lua, -1) == LUA_TBOOLEAN) {
          op->set_last(lua_toboolean(lua, -1));
        }
        lua_pop(lua, 1);
      }
      lua_pop(lua, 1);

      lua_getfield(lua, msg_idx, "trace");
      if (lua_type(lua, -1) == LUA_TSTRING) {
        msg->set_trace(lua_tostring(lua, -1));
      }
      lua_pop(lua, 1);

      lua_getfield(lua, msg_idx, "spanId");
      if (lua_type(lua, -1) == LUA_TSTRING) {
        msg->set_span_id(lua_tostring(lua, -1));
      }
      lua_pop(lua, 1);

      lua_getfield(lua, msg_idx, "sourceLocation");
      if (lua_type(lua, -1) == LUA_TTABLE) {
        auto sl = msg->mutable_source_location();
        const char *s;

        lua_getfield(lua, -1, "file");
        s = lua_tostring(lua, -1);
        if (s) sl->set_file(s);
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "line");
        if (lua_type(lua, -1) == LUA_TNUMBER) {
          sl->set_line(lua_tonumber(lua, -1));
        }
        lua_pop(lua, 1);

        lua_getfield(lua, -1, "function");
        s = lua_tostring(lua, -1);
        if (s) sl->set_function(s);
        lua_pop(lua, 1);
      }
      lua_pop(lua, 1);

      lua_getfield(lua, msg_idx, "textPayload");
      if (lua_type(lua, -1) == LUA_TSTRING) {
        msg->set_text_payload(lua_tostring(lua, -1));
      }
      lua_pop(lua, 1);
    }

    if (ww->w->request->entries_size() == ww->w->batch_size) {
      if (async_api) {
        write_async(ww, sequence_id);
      } else {
        err = write_sync(lua, ww);
      }
      if (!err) {
        lua_pushinteger(lua, 0);
      }
    } else {
      if (async_api) {
        lua_pushinteger(lua, -5);
      } else {
        lua_pushinteger(lua, -4);
      }
    }
  } catch (std::exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown exception");
    err = true;
  }
  if (err) return lua_error(lua);
  return 1;
}


static int writer_flush(lua_State *lua)
{
  writer_wrapper *ww = static_cast<writer_wrapper *>(luaL_checkudata(lua, 1, mt_writer));
  if (ww->w->request->entries_size() > 0) {
    if (ww->w->max_async_requests == 0) {
      if (write_sync(lua, ww)) {
        return lua_error(lua);
      }
    } else {
      write_async(ww, get_sequence_id(lua, 2));
    }
  }
  return 0;
}


static int writer_send_sync(lua_State *lua)
{
  return send(lua, false);
}


static int writer_send_async(lua_State *lua)
{
  return send(lua, true);
}


static int writer_poll(lua_State *lua)
{
  writer_poll_internal(lua, -1000);
#ifdef LUA_SANDBOX
  return 0;
#else
  return 2;
#endif
}


static int writer_gc(lua_State *lua)
{
  writer_wrapper *ww = static_cast<writer_wrapper *>(luaL_checkudata(lua, 1, mt_writer));
  if (ww->w->max_async_requests != 0) {
    ww->w->cq.Shutdown();
    while (writer_poll_internal(lua, 1000) != grpc::CompletionQueue::NextStatus::SHUTDOWN);
  }
  delete ww->w->request;
  delete ww->w;
  ww->w = nullptr;
  return 0;
}


static const struct luaL_reg lib_f[] = {
  { "writer", writer_new },
  { NULL, NULL }
};

static const struct luaL_reg writer_lib_m[] = {
  { "poll", writer_poll },
  { "send", writer_send_async },
  { "send_sync", writer_send_sync },
  { "flush", writer_flush },
  { "__gc", writer_gc },
  { NULL, NULL }
};


int luaopen_gcp_logging(lua_State *lua)
{
  luaL_newmetatable(lua, mt_writer);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, writer_lib_m);
  lua_pop(lua, 1);

  luaL_register(lua, "gcp.logging", lib_f);

  // if necessary flag the parent table to prevent preservation
  lua_getglobal(lua, "gcp");
  if (lua_getmetatable(lua, -1) == 0) {
    lua_newtable(lua);
    lua_setmetatable(lua, -2);
  } else {
    lua_pop(lua, 1);
  }
  lua_pop(lua, 1);
  return 1;
}
