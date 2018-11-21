/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua GCP Pub/Sub wrapper implementation @file */

extern "C"
{
#include "lauxlib.h"
#include "lua.h"

#ifdef LUA_SANDBOX
#include <luasandbox.h>
#include <luasandbox/heka/sandbox.h>
#include <luasandbox_output.h>
#endif

int luaopen_gcp_pubsub(lua_State *lua);
}

#include <chrono>
#include <exception>
#include <google/protobuf/map.h>
#include <google/pubsub/v1/pubsub.grpc.pb.h>
#include <grpc++/grpc++.h>
#include <iomanip>
#include <memory>
#include <string>
#include <sstream>

#ifdef LUA_SANDBOX
#include "common.h"
#endif

typedef google::protobuf::MapPair<std::string, std::string> MapPairString;

static const char *mt_publisher  = "mozsvc.gcp.pubsub.publisher";
static const char *mt_subscriber = "mozsvc.gcp.pubsub.subscriber";
using google::pubsub::v1::AcknowledgeRequest;
using google::pubsub::v1::GetSubscriptionRequest;
using google::pubsub::v1::GetTopicRequest;
using google::pubsub::v1::Publisher;
using google::pubsub::v1::PublishRequest;
using google::pubsub::v1::PublishResponse;
using google::pubsub::v1::PubsubMessage;
using google::pubsub::v1::PullRequest;
using google::pubsub::v1::PullResponse;
using google::pubsub::v1::ReceivedMessage;
using google::pubsub::v1::Subscriber;
using google::pubsub::v1::Subscription;
using google::pubsub::v1::Topic;
using grpc::ClientContext;

struct async_pub_request {
  void            *sequence_id;
  PublishRequest  *request;
  ClientContext   ctx;
  PublishResponse response;
  grpc::Status    status;
  std::unique_ptr<grpc::ClientAsyncResponseReader<PublishResponse> > rpc;
};

struct async_sub_request {
  ClientContext ctx;
  PullRequest   request;
  PullResponse  response;
  grpc::Status  status;
  std::unique_ptr<grpc::ClientAsyncResponseReader<PullResponse> > rpc;
};

struct async_ack_request {
  ClientContext           ctx;
  AcknowledgeRequest      request;
  google::protobuf::Empty response;
  grpc::Status            status;
  std::unique_ptr<grpc::ClientAsyncResponseReader<google::protobuf::Empty> > rpc;
};

struct publisher {
#ifdef LUA_SANDBOX
  const lsb_logger *logger;
#endif
  PublishRequest                    *request;
  std::unique_ptr<Publisher::Stub>  stub;
  std::string                       topic_name;
  int                               batch_size;
  int                               max_async_requests;
  int                               outstanding_requests;
  grpc::CompletionQueue             cq;
};

typedef struct publisher_wrapper
{
  publisher *p;
} publisher_wrapper;

struct subscriber {
#ifdef LUA_SANDBOX
  const lsb_logger *logger;
#endif
  std::unique_ptr<Subscriber::Stub> stub;
  std::string                       subscription_name;
  grpc::CompletionQueue             cq;
  grpc::CompletionQueue             acq;
  int                               max_async_requests;
  int                               outstanding_requests;
};

typedef struct subscriber_wrapper
{
  subscriber *s;
} subscriber_wrapper;


static int publisher_new(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n >= 2 && n <= 4, n, "incorrect number of arguments");
  const char *channel = luaL_checkstring(lua, 1);
  const char *topic   = luaL_checkstring(lua, 2);
  int max_async       = luaL_optint(lua, 3, 20);
  int batch_size      = luaL_optint(lua, 4, 1000);

  publisher_wrapper *pw = static_cast<publisher_wrapper *>(lua_newuserdata(lua, sizeof*pw));
  pw->p = new struct publisher;
  if (!pw->p) return luaL_error(lua, "memory allocation failed");

  pw->p->topic_name = topic;
  pw->p->max_async_requests = max_async;
  pw->p->batch_size = batch_size;
  pw->p->outstanding_requests = 0;
  pw->p->request = new PublishRequest;
  pw->p->request->set_topic(topic);
#ifdef LUA_SANDBOX
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_THIS_PTR);
  lsb_lua_sandbox *lsb = reinterpret_cast<lsb_lua_sandbox *>(lua_touserdata(lua, -1));
  lua_pop(lua, 1); // remove this ptr
  if (!lsb) {
    return luaL_error(lua, "invalid " LSB_THIS_PTR);
  }
  pw->p->logger = lsb_get_logger(lsb);
#endif
  luaL_getmetatable(lua, mt_publisher);
  lua_setmetatable(lua, -2);

  bool err = false;
  try {
    auto creds = grpc::GoogleDefaultCredentials();
    // see https://github.com/googleapis/google-cloud-node/pull/2007
    // Fix the send/receive size mis-match in
    // https://github.com/grpc/grpc/blob/master/include/grpc/impl/codegen/grpc_types.h#L396
    grpc::ChannelArguments cargs;
    cargs.SetMaxSendMessageSize(-1); // make sure this remains -1 even if the todo is completed
    cargs.SetInt(GRPC_ARG_MIN_RECONNECT_BACKOFF_MS, 5000);
    pw->p->stub = std::make_unique<Publisher::Stub>(grpc::CreateCustomChannel(channel, creds, cargs));

    ClientContext ctx;
    GetTopicRequest request;
    Topic response;
    request.set_topic(topic);
    auto status = pw->p->stub->GetTopic(&ctx, request, &response);
    if (!status.ok() && status.error_code() == grpc::StatusCode::NOT_FOUND) {
      ClientContext ctx1;
      Topic r;
      r.set_name(topic);
      status = pw->p->stub->CreateTopic(&ctx1, r, &response);
    }
    if (!status.ok()) {
      lua_pushstring(lua, status.error_message().c_str());
      err = true;
    }
  } catch (std::exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown exception");
    err = true;
  }
  return err ? lua_error(lua) : 1;
}


static int subscriber_new(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n >= 3 && n <= 4, n, "incorrect number of arguments");
  const char *channel = luaL_checkstring(lua, 1);
  const char *topic   = luaL_checkstring(lua, 2);
  const char *name    = luaL_checkstring(lua, 3);
  int max_async       = luaL_optint(lua, 4, 0);

  subscriber_wrapper *sw = static_cast<subscriber_wrapper *>(lua_newuserdata(lua, sizeof*sw));
  sw->s = new struct subscriber;
  if (!sw->s) return luaL_error(lua, "memory allocation failed");

  sw->s->subscription_name = name;
  sw->s->max_async_requests = max_async;
  sw->s->outstanding_requests = 0;
#ifdef LUA_SANDBOX
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_THIS_PTR);
  lsb_lua_sandbox *lsb = reinterpret_cast<lsb_lua_sandbox *>(lua_touserdata(lua, -1));
  lua_pop(lua, 1); // remove this ptr
  if (!lsb) {
    return luaL_error(lua, "invalid " LSB_THIS_PTR);
  }
  sw->s->logger = lsb_get_logger(lsb);
#endif
  luaL_getmetatable(lua, mt_subscriber);
  lua_setmetatable(lua, -2);

  bool err = false;
  try {
    auto creds = grpc::GoogleDefaultCredentials();
    // see https://github.com/googleapis/google-cloud-node/pull/2007
    // Fix the send/receive size mis-match in
    // https://github.com/grpc/grpc/blob/master/include/grpc/impl/codegen/grpc_types.h#L396
    grpc::ChannelArguments cargs;
    cargs.SetMaxReceiveMessageSize(-1);
    cargs.SetInt(GRPC_ARG_MIN_RECONNECT_BACKOFF_MS, 5000);
    sw->s->stub = std::make_unique<Subscriber::Stub>(grpc::CreateCustomChannel(channel, creds, cargs));

    ClientContext ctx;
    GetSubscriptionRequest request;
    Subscription response;
    request.set_subscription(name);
    auto status = sw->s->stub->GetSubscription(&ctx, request, &response);
    if (!status.ok() && status.error_code() == grpc::StatusCode::NOT_FOUND) {
      ClientContext ctx1;
      Subscription r;
      r.set_name(name);
      r.set_topic(topic);
      status = sw->s->stub->CreateSubscription(&ctx1, r, &response);
    }
    if (status.ok()) {
      if (response.topic() != topic) {
        lua_pushstring(lua, "specified topic does not match subscription topic");
        err = true;
      }
    } else {
      lua_pushstring(lua, status.error_message().c_str());
      err = true;
    }
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
publisher_poll_internal(lua_State *lua, int timeout)
{
  publisher_wrapper *pw = static_cast<publisher_wrapper *>(luaL_checkudata(lua, 1, mt_publisher));

  grpc::CompletionQueue::NextStatus status = grpc::CompletionQueue::NextStatus::TIMEOUT;
  if (pw->p->max_async_requests == 0) {
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
    while (grpc::CompletionQueue::NextStatus::GOT_EVENT == (status = pw->p->cq.AsyncNext(&tag, &ok, now))) {
      if (ok) {
        auto apr = static_cast<struct async_pub_request *>(tag);
        if (apr->status.ok()) {
          sequence_id = apr->sequence_id;
        } else {
          ++failures;
#ifdef LUA_SANDBOX
          pw->p->logger->cb(pw->p->logger->context, pw->p->topic_name.c_str(), 3,
                            "publish error\t%d\t%s", (int)apr->status.error_code(),
                            apr->status.error_message().c_str());
#endif
        }
        delete apr->request;
        delete apr;
        --pw->p->outstanding_requests;
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


static int publisher_poll(lua_State *lua)
{
  publisher_poll_internal(lua, -1000);
#ifdef LUA_SANDBOX
  return 0;
#else
  return 2;
#endif
}


static int publisher_gc(lua_State *lua)
{
  publisher_wrapper *pw = static_cast<publisher_wrapper *>(luaL_checkudata(lua, 1, mt_publisher));
  if (pw->p->max_async_requests != 0) {
    pw->p->cq.Shutdown();
    while (publisher_poll_internal(lua, 1000) != grpc::CompletionQueue::NextStatus::SHUTDOWN);
  }
  delete pw->p->request;
  delete pw->p;
  pw->p = nullptr;
  return 0;
}


static grpc::CompletionQueue::NextStatus
subscriber_discard(subscriber_wrapper *sw)
{
  grpc::CompletionQueue::NextStatus status = grpc::CompletionQueue::NextStatus::TIMEOUT;
  try {
    void *tag;
    bool ok;
    std::chrono::system_clock::time_point now = std::chrono::system_clock::now() + std::chrono::milliseconds(1000);
    while (grpc::CompletionQueue::NextStatus::GOT_EVENT == (status = sw->s->cq.AsyncNext(&tag, &ok, now))) {
      if (ok) {
        auto asr = static_cast<struct async_sub_request *>(tag);
        delete asr;
        --sw->s->outstanding_requests;
      }
    }
  } catch (...) {}
  return status;
}


static grpc::CompletionQueue::NextStatus
ack_poll(subscriber_wrapper *sw, int timeout)
{
  grpc::CompletionQueue::NextStatus status = grpc::CompletionQueue::NextStatus::TIMEOUT;
  try {
    void *tag;
    bool ok;
    std::chrono::system_clock::time_point now = std::chrono::system_clock::now() + std::chrono::milliseconds(timeout);
    while (grpc::CompletionQueue::NextStatus::GOT_EVENT == (status = sw->s->acq.AsyncNext(&tag, &ok, now))) {
      if (ok) {
        auto aar = static_cast<struct async_ack_request *>(tag);
        if (!aar->status.ok()) {
#ifdef LUA_SANDBOX
          sw->s->logger->cb(sw->s->logger->context, sw->s->subscription_name.c_str(), 3,
                            "ack error\t%d\t%s", (int)aar->status.error_code(),
                            aar->status.error_message().c_str());
#endif
        }
        delete aar;
      }
    }
  } catch (...) {}
  return status;
}


static int subscriber_gc(lua_State *lua)
{
  subscriber_wrapper *sw = static_cast<subscriber_wrapper *>(luaL_checkudata(lua, 1, mt_subscriber));
  sw->s->cq.Shutdown();
  sw->s->acq.Shutdown();
  while (subscriber_discard(sw) != grpc::CompletionQueue::NextStatus::SHUTDOWN);
  while (ack_poll(sw, 1000) != grpc::CompletionQueue::NextStatus::SHUTDOWN);
  delete sw->s;
  sw->s = nullptr;
  return 0;
}


void publish_async(publisher_wrapper *pw, void *sequence_id)
{
  auto apr = new struct async_pub_request;
  apr->request = pw->p->request;
  pw->p->request = new PublishRequest;
  pw->p->request->set_topic(pw->p->topic_name);
  apr->sequence_id = sequence_id;
  apr->rpc = pw->p->stub->AsyncPublish(&apr->ctx, *apr->request, &pw->p->cq);
  apr->rpc->Finish(&apr->response, &apr->status, (void *)apr);
  ++pw->p->outstanding_requests;
}


bool publish_sync(lua_State *lua, publisher_wrapper *pw)
{
  bool err = false;
  ClientContext ctx;
  PublishResponse response;
  google::protobuf::Empty empty;
  auto status = pw->p->stub->Publish(&ctx, *pw->p->request, &response);
  if (!status.ok()) {
    lua_pushstring(lua, status.error_message().c_str());
    err = true;
  }
  pw->p->request->Clear();
  pw->p->request->set_topic(pw->p->topic_name);
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


static int publish(lua_State *lua, bool async_api)
{
  publisher_wrapper *pw = static_cast<publisher_wrapper *>(luaL_checkudata(lua, 1, mt_publisher));
  void *sequence_id = nullptr;
  int msg_idx = 2;
  if (async_api) {
    if (pw->p->max_async_requests == 0) return luaL_error(lua, "async is disabled");
    if (pw->p->outstanding_requests >= pw->p->max_async_requests) {
      lua_pushinteger(lua, 1);
      return 1;
    }
    sequence_id = get_sequence_id(lua, 2);
    msg_idx = 3;
  }

  bool free_data = false;
  size_t len = 0;
  const char *data = NULL;
  switch (lua_type(lua, msg_idx)) {
  case LUA_TSTRING:
    data = lua_tolstring(lua, msg_idx, &len);
    break;
#ifdef LUA_SANDBOX
  case LUA_TNIL:
    break;
  case LUA_TUSERDATA:
    {
      lua_CFunction fp = lsb_get_zero_copy_function(lua, msg_idx);
      if (!fp) {
        return luaL_argerror(lua, msg_idx, "no zero copy support");
      }
      int results = fp(lua);
      int start = msg_idx + 1;
      int end = start + results;
      int segments = 0;
      size_t total_len = 0;

      for (int i = start; i < end; ++i) {
        switch (lua_type(lua, i)) {
        case LUA_TSTRING:
          data = lua_tolstring(lua, i, &len);
          break;
        case LUA_TLIGHTUSERDATA:
          data = (const char *)lua_touserdata(lua, i++);
          len = (size_t)lua_tointeger(lua, i);
          break;
        default:
          return luaL_error(lua, "invalid zero copy return");
        }
        total_len += len;
        ++segments;
      }

      if (segments == 0 || total_len == 0) {
        return 0;
      }

      if (segments > 1) {
        char *buf = static_cast<char *>(malloc(total_len));
        if (!buf) {
          return luaL_error(lua, "malloc failed");
        }

        size_t pos = 0;
        for (int i = start; i < end; ++i) {
          switch (lua_type(lua, i)) {
          case LUA_TSTRING:
            data = lua_tolstring(lua, i, &len);
            break;
          case LUA_TLIGHTUSERDATA:
            data = (const char *)lua_touserdata(lua, i++);
            len = (size_t)lua_tointeger(lua, i);
            break;
          }
          if (data && len > 0) {
            memcpy(buf + pos, data, len);
            pos += len;
          }
        }
        data = buf;
        free_data = true;
        len = total_len;
      }
    }
    break;
#endif
  default:
    return luaL_typerror(lua, msg_idx, "string or userdata (heka sandbox only)");
    break;
  }

  ++msg_idx;
  bool err = false;
  try {
    if (pw->p->request->messages_size() < pw->p->batch_size) {
      auto msg = pw->p->request->add_messages();
#ifdef LUA_SANDBOX
      if (data) {
        msg->set_data(data, len);
      } else {
        lua_getfield(lua, LUA_REGISTRYINDEX, LSB_HEKA_THIS_PTR);
        lsb_heka_sandbox *hsb = static_cast<lsb_heka_sandbox *>(lua_touserdata(lua, -1));
        lua_pop(lua, 1); // remove this ptr
        if (!hsb) {
          throw std::runtime_error("invalid lsb_heka_this_ptr");
        }
        const lsb_heka_message *hm = lsb_heka_get_message(hsb);
        if (!hm || !hm->raw.s) {
          throw std::runtime_error("parse_message() no active message");
        }
        if (hm->payload.s) {
          msg->set_data(hm->payload.s, hm->payload.len);
        } else {
          msg->set_data("");
        }
        auto attrs = msg->mutable_attributes();
        gcp_fields_to_map(hm, attrs);
        gcp_headers_to_map(hm, attrs); // headers will overwrite on name collision
      }
#else
      msg->set_data((void *)data, len);
      switch (lua_type(lua, msg_idx)) {
      case LUA_TNIL:
        break;
      case LUA_TTABLE:
        {
          auto attrs = msg->mutable_attributes();
          lua_pushnil(lua);
          while (lua_next(lua, msg_idx) != 0) {
            if (lua_type(lua, -2) != LUA_TSTRING) {
              throw std::runtime_error("attribute key must be a string");
            }
            attrs->insert(MapPairString(lua_tostring(lua, -2), lua_tostring(lua, -1)));
            lua_pop(lua, 1);
          }
        }
        break;
      default:
        throw std::runtime_error("attributes must be a table");
      }
#endif
    }

    if (pw->p->request->messages_size() == pw->p->batch_size) {
      if (async_api) {
        publish_async(pw, sequence_id);
      } else {
        err = publish_sync(lua, pw);
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
  if (free_data) {
    free((void *)data);
  }
  if (err) return lua_error(lua);
  return 1;
}


static int publisher_flush(lua_State *lua)
{
  publisher_wrapper *pw = static_cast<publisher_wrapper *>(luaL_checkudata(lua, 1, mt_publisher));
  if (pw->p->request->messages_size() > 0) {
    if (pw->p->max_async_requests == 0) {
      if (publish_sync(lua, pw)) {
        return lua_error(lua);
      }
    } else {
      publish_async(pw, get_sequence_id(lua, 2));
    }
  }
  return 0;
}


static int publisher_publish_sync(lua_State *lua)
{
  return publish(lua, false);
}


static int publisher_publish_async(lua_State *lua)
{
  return publish(lua, true);
}


static int subscriber_poll(lua_State *lua, subscriber_wrapper *sw)
{
  int cnt = 0;
  bool err = false;
  try {
    void *tag;
    bool ok;
    std::chrono::system_clock::time_point now = std::chrono::system_clock::now() + std::chrono::milliseconds(1000);
    while (cnt == 0 && grpc::CompletionQueue::NextStatus::GOT_EVENT == sw->s->cq.AsyncNext(&tag, &ok, now)) {
      if (ok) {
        auto asr = static_cast<struct async_sub_request *>(tag);
        if (asr->status.ok()) {
          if (asr->response.received_messages_size() > 0) {
            lua_newtable(lua);
            auto aar = new struct async_ack_request;
            aar->request.set_subscription(sw->s->subscription_name);
            const auto msgs = asr->response.received_messages();
            for (auto it = msgs.pointer_begin(); it != msgs.pointer_end(); ++it) {
              auto msg = (*it);
              if (msg->has_message()) {
                lua_newtable(lua);
                auto data = msg->message().data();
                lua_pushlstring(lua, data.c_str(), data.size());
                lua_rawseti(lua, -2, 1);
                if (msg->message().attributes_size() == 0) {
                  lua_pushnil(lua);
                } else {
                  lua_newtable(lua);
                  for (auto& kv : msg->message().attributes()) {
                    lua_pushlstring(lua, kv.second.c_str(), kv.second.size());
                    lua_setfield(lua, -2, kv.first.c_str());
                  }
                }
                lua_rawseti(lua, -2, 2);
                lua_rawseti(lua, -2, ++cnt);
                aar->request.add_ack_ids(msg->ack_id());
              }
            }
            aar->rpc = sw->s->stub->AsyncAcknowledge(&aar->ctx, aar->request, &sw->s->acq);
            aar->rpc->Finish(&aar->response, &aar->status, (void *)aar);
          }
        } else {
#ifdef LUA_SANDBOX
          sw->s->logger->cb(sw->s->logger->context, sw->s->subscription_name.c_str(), 3,
                            "pull error\t%d\t%s", (int)asr->status.error_code(),
                            asr->status.error_message().c_str());
#endif
        }
        delete asr;
        --sw->s->outstanding_requests;
      }
    }
    ack_poll(sw, -1000);
  } catch (std::exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown exception");
    err = true;
  }
  if (err) lua_error(lua);
  if (cnt == 0) {
    lua_pushnil(lua);
  }
  lua_pushinteger(lua, cnt);
  return cnt;
}


static int subscriber_pull_async(lua_State *lua)
{
  subscriber_wrapper *sw = static_cast<subscriber_wrapper *>(luaL_checkudata(lua, 1, mt_subscriber));
  if (sw->s->max_async_requests == 0) return luaL_error(lua, "async is disabled");

  int cnt = subscriber_poll(lua, sw);
  if ((cnt == 0 && sw->s->outstanding_requests != 0)
      || sw->s->outstanding_requests >= sw->s->max_async_requests) {
    return 2;
  }

  int batch_size = luaL_optint(lua, 2, 1);
  bool err = false;
  try {
    int create = cnt > 0 ? 2 : 1;
    for (int i = 0; i < create && sw->s->outstanding_requests < sw->s->max_async_requests; ++i) {
      auto asr = new struct async_sub_request;
      asr->request.set_max_messages(batch_size);
      asr->request.set_subscription(sw->s->subscription_name);
      //asr->request.set_return_immediately(true);
      asr->rpc = sw->s->stub->AsyncPull(&asr->ctx, asr->request, &sw->s->cq);
      asr->rpc->Finish(&asr->response, &asr->status, (void *)asr);
      ++sw->s->outstanding_requests;
    }
  } catch (std::exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown exception");
    err = true;
  }
  return err ? lua_error(lua) : 2;
}


static int subscriber_pull_sync(lua_State *lua)
{
  subscriber_wrapper *sw = static_cast<subscriber_wrapper *>(luaL_checkudata(lua, 1, mt_subscriber));
  int batch_size = luaL_optint(lua, 2, 1);

  bool err = false;
  int cnt = 0;
  try {
    ClientContext ctx;
    PullRequest request;
    PullResponse response;
    request.set_max_messages(batch_size);
    request.set_subscription(sw->s->subscription_name);
    request.set_return_immediately(true);

    auto status = sw->s->stub->Pull(&ctx, request, &response);
    if (status.ok()) {
      if (response.received_messages_size() == 0) {
        lua_pushnil(lua);
        lua_pushinteger(lua, 0);
        return 2;
      }
      lua_newtable(lua);
      AcknowledgeRequest ack;
      ack.set_subscription(sw->s->subscription_name);
      const auto msgs = response.received_messages();
      for (auto it = msgs.pointer_begin(); it != msgs.pointer_end(); ++it) {
        auto msg = (*it);
        if (msg->has_message()) {
          auto data = msg->message().data();
          lua_pushlstring(lua, data.c_str(), data.size());
          lua_rawseti(lua, -2, ++cnt);
          ack.add_ack_ids(msg->ack_id());
        }
      }
      ClientContext actx;
      google::protobuf::Empty empty;
      sw->s->stub->Acknowledge(&actx, ack, &empty);
    } else {
      lua_pushstring(lua, status.error_message().c_str());
      err = true;
    }
  } catch (std::exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown exception");
    err = true;
  }
  if (err) return lua_error(lua);
  lua_pushinteger(lua, cnt);
  return 2;
}


static const struct luaL_reg lib_f[] = {
  { "publisher", publisher_new },
  { "subscriber", subscriber_new },
  { NULL, NULL }
};

static const struct luaL_reg publisher_lib_m[] = {
  { "poll", publisher_poll },
  { "publish", publisher_publish_async },
  { "publish_sync", publisher_publish_sync },
  { "flush", publisher_flush },
  { "__gc", publisher_gc },
  { NULL, NULL }
};

static const struct luaL_reg subscriber_lib_m[] = {
  { "pull", subscriber_pull_async },
  { "pull_sync", subscriber_pull_sync },
  { "__gc", subscriber_gc },
  { NULL, NULL }
};


int luaopen_gcp_pubsub(lua_State *lua)
{
  luaL_newmetatable(lua, mt_publisher);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, publisher_lib_m);
  lua_pop(lua, 1);

  luaL_newmetatable(lua, mt_subscriber);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, subscriber_lib_m);
  lua_pop(lua, 1);

  luaL_register(lua, "gcp.pubsub", lib_f);

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
