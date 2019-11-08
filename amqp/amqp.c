/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua RabbitMQ AMQP implementation @file */

#include <amqp.h>
#include <amqp_ssl_socket.h>
#include <amqp_tcp_socket.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <Winsock2.h>
#else
#include <sys/time.h>
#endif

#include "lauxlib.h"
#include "lua.h"

static const char *mt_consumer  = "mozsvc.amqp_consumer";
static const char *module_table = "amqp";


typedef struct consumer {
  amqp_connection_state_t conn;
  amqp_channel_t channel;
  uint64_t delivery_tag;
  int ssl_enabled;
  int manual_ack;
} consumer;


struct rmq_config {
  const char *host;
  const char *vhost;
  const char *user;
  const char *password;
  const char *exchange;
  const char *binding;
  const char *queue_name;
  const char *key;
  const char *cert;
  const char *cacert;
  int port;
  int connection_timeout;
  int manual_ack;
  int verifypeer;
  int verifyhostname;
  int passive;
  int durable;
  int exclusive;
  int auto_delete;
  int prefetch_size;
  int prefetch_count;
};


static int rmq_version(lua_State *lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


static void init_rmq_config(struct rmq_config *cfg)
{
  memset(cfg, 0, sizeof(struct rmq_config));
}


static consumer* check_consumer(lua_State *lua, int args)
{
  consumer *c = luaL_checkudata(lua, 1, mt_consumer);
  int n = lua_gettop(lua);
  luaL_argcheck(lua, args == n, n, "incorrect number of arguments");
  return c;
}


static const char*
read_string(lua_State *lua, int idx, const char *key, bool required)
{
  lua_getfield(lua, idx, key);
  int t = lua_type(lua, -1);
  switch (t) {
  case LUA_TSTRING:
    return lua_tostring(lua, -1);
  case LUA_TNIL:
    break;
  default:
    luaL_error(lua, "configuration error key: %s, type:%s", key,
               lua_typename(lua, t));
    break;
  }
  lua_pop(lua, 1);
  if (required) {
    luaL_error(lua, "configuration error key: %s, missing", key);
  }
  return NULL;
}


static int read_int(lua_State *lua, int idx, const char *key, int dflt)
{
  int i = 0;
  lua_getfield(lua, idx, key);
  int t = lua_type(lua, -1);
  switch (t) {
  case LUA_TNUMBER:
    i = lua_tonumber(lua, -1);
    break;
  case LUA_TNIL:
    i = dflt;
    break;
  default:
    luaL_error(lua, "configuration error key: %s, type:%s", key,
               lua_typename(lua, t));
    break;
  }
  lua_pop(lua, 1);
  return i;
}


static int read_boolean(lua_State *lua, int idx, const char *key)
{
  int i = 0;
  lua_getfield(lua, idx, key);
  int t = lua_type(lua, -1);
  switch (t) {
  case LUA_TBOOLEAN:
    i = lua_toboolean(lua, -1);
    break;
  case LUA_TNIL:
    break;
  default:
    luaL_error(lua, "configuration error key: %s, type:%s", key,
               lua_typename(lua, t));
    break;
  }
  lua_pop(lua, 1);
  return i;
}


static int is_table(lua_State *lua, int idx, const char *key)
{
  int i = 0;
  lua_getfield(lua, idx, key);
  int t = lua_type(lua, -1);
  switch (t) {
  case LUA_TTABLE:
    return 1;
    break;
  case LUA_TNIL:
    break;
  default:
    luaL_error(lua, "configuration error key: %s, type:%s", key,
               lua_typename(lua, t));
    break;
  }
  return i;
}


static void
check_amqp_error(lua_State *lua, amqp_rpc_reply_t x, const char *context)
{
  switch (x.reply_type) {
  case AMQP_RESPONSE_NORMAL:
    return;

  case AMQP_RESPONSE_NONE:
    luaL_error(lua, "%s: missing RPC reply type!\n", context);
    break;

  case AMQP_RESPONSE_LIBRARY_EXCEPTION:
    luaL_error(lua, "%s: %s\n", context, amqp_error_string2(x.library_error));
    break;

  case AMQP_RESPONSE_SERVER_EXCEPTION:
    switch (x.reply.id) {
    case AMQP_CONNECTION_CLOSE_METHOD:
      {
        amqp_connection_close_t *m = (amqp_connection_close_t *)x.reply.decoded;
        lua_pushfstring(lua, "%s: server connection error %d, message: ",
                        context, (int)m->reply_code);
        lua_pushlstring(lua, (char *)m->reply_text.bytes, m->reply_text.len);
        lua_concat(lua, 2);
        lua_error(lua);
        break;
      }
    case AMQP_CHANNEL_CLOSE_METHOD:
      {
        amqp_channel_close_t *m = (amqp_channel_close_t *)x.reply.decoded;
        lua_pushfstring(lua, "%s: server channel error %d, message: ",
                        context, (int)m->reply_code);
        lua_pushlstring(lua, (char *)m->reply_text.bytes, m->reply_text.len);
        lua_concat(lua, 2);
        lua_error(lua);
        break;
      }
    default:
      luaL_error(lua, "%s: unknown server error, method id %p\n",
                 context, x.reply.id);
      break;
    }
    break;
  }
}


static int rmq_consumer(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 1, 0, "incorrect number of arguments");
  luaL_checktype(lua, 1, LUA_TTABLE);

  struct rmq_config cfg;
  init_rmq_config(&cfg);
  // hold the values on the stack to avoid a temporary copy
  if (!lua_checkstack(lua, 12)) {
    luaL_error(lua, "checkstack failed");
  }
  cfg.host                = read_string(lua, 1, "host", true);
  cfg.vhost               = read_string(lua, 1, "vhost", false);
  if (!cfg.vhost) { cfg.vhost = "/";}
  cfg.user                = read_string(lua, 1, "user", true);
  cfg.password            = read_string(lua, 1, "_password", true);
  cfg.exchange            = read_string(lua, 1, "exchange", true);
  cfg.binding             = read_string(lua, 1, "binding", false);
  if (!cfg.binding) { cfg.binding = "#";}
  cfg.queue_name          = read_string(lua, 1, "queue_name", true);
  cfg.port                = read_int(lua, 1, "port", 5672);
  cfg.connection_timeout  = read_int(lua, 1, "connection_timeout", 10);
  cfg.prefetch_size       = read_int(lua, 1, "prefetch_size", 0);
  cfg.prefetch_count      = read_int(lua, 1, "prefetch_count", 1);
  cfg.manual_ack          = read_boolean(lua, 1, "manual_ack");
  cfg.passive             = read_boolean(lua, 1, "passive");
  cfg.durable             = read_boolean(lua, 1, "durable");
  cfg.exclusive           = read_boolean(lua, 1, "exclusive");
  cfg.auto_delete         = read_boolean(lua, 1, "auto_delete");
  int ssl_enabled         = is_table(lua, 1, "ssl");
  if (ssl_enabled) {
    cfg.key             = read_string(lua, -1, "_key", false);
    cfg.cert            = read_string(lua, -1, "cert", false);
    cfg.cacert          = read_string(lua, -1, "cacert", false);
    cfg.verifypeer      = read_boolean(lua, -1, "verifypeer");
    cfg.verifyhostname  = read_boolean(lua, -1, "verifyhostname");
  } else {
    lua_pop(lua, 1);
  }
  consumer *c = lua_newuserdata(lua, sizeof(consumer));
  c->conn = amqp_new_connection();
  c->channel = 0;
  c->delivery_tag = 0;
  c->ssl_enabled = ssl_enabled;
  c->manual_ack = cfg.manual_ack;
  luaL_getmetatable(lua, mt_consumer);
  lua_setmetatable(lua, -2);

  struct timeval tval;
  struct timeval *tv;

  if (cfg.connection_timeout > 0) {
    tv = &tval;
    tv->tv_sec = cfg.connection_timeout;
    tv->tv_usec = 0;
  } else {
    tv = NULL;
  }

  amqp_status_enum status;
  amqp_socket_t *socket;
  if (c->ssl_enabled) {
    socket = amqp_ssl_socket_new(c->conn);
    if (!socket) {
      return luaL_error(lua, "creating SSL/TLS socket");
    }

    if (cfg.cacert) {
      status = amqp_ssl_socket_set_cacert(socket, cfg.cacert);
      if (status != AMQP_STATUS_OK) {
        return luaL_error(lua, "setting CA certificate");
      }
    }

    if (cfg.key && cfg.cert) {
      status = amqp_ssl_socket_set_key(socket, cfg.key, cfg.cert);
      if (status != AMQP_STATUS_OK) {
        return luaL_error(lua, "setting client key");
      }
    }
    amqp_ssl_socket_set_verify_peer(socket, cfg.verifypeer);
    amqp_ssl_socket_set_verify_hostname(socket, cfg.verifyhostname);
  } else {
    socket = amqp_tcp_socket_new(c->conn);
    if (!socket) {
      return luaL_error(lua, "creating tcp socket");
    }
  }

  status = amqp_socket_open_noblock(socket, cfg.host, cfg.port, tv);
  if (status != AMQP_STATUS_OK) {
    luaL_error(lua, "opening connection");
  }

  check_amqp_error(lua, amqp_login(c->conn, cfg.vhost, 0,
                                   AMQP_DEFAULT_FRAME_SIZE, 0,
                                   AMQP_SASL_METHOD_PLAIN, cfg.user,
                                   cfg.password), "login");
  amqp_channel_open(c->conn, 1);
  check_amqp_error(lua, amqp_get_rpc_reply(c->conn), "Opening channel");
  amqp_basic_qos(c->conn, 1, cfg.prefetch_size, cfg.prefetch_count, 0);

  amqp_queue_declare_ok_t *r = NULL;
  amqp_bytes_t queue_name;
  if (!cfg.queue_name) {
    r = amqp_queue_declare(c->conn, 1, amqp_empty_bytes, 0, 0, 0, 1,
                           amqp_empty_table); // auto-delete
    check_amqp_error(lua, amqp_get_rpc_reply(c->conn), "Declaring queue");
    amqp_queue_bind(c->conn, 1, r->queue, amqp_cstring_bytes(cfg.exchange),
                    amqp_cstring_bytes(cfg.binding), amqp_empty_table);
    check_amqp_error(lua, amqp_get_rpc_reply(c->conn), "Binding queue");
  } else {
    r = amqp_queue_declare(c->conn, 1, amqp_cstring_bytes(cfg.queue_name),
                           cfg.passive, cfg.durable, cfg.exclusive,
                           cfg.auto_delete, amqp_empty_table);
    check_amqp_error(lua, amqp_get_rpc_reply(c->conn), "Declaring queue");
    amqp_queue_bind(c->conn, 1, r->queue, amqp_cstring_bytes(cfg.exchange),
                    amqp_cstring_bytes(cfg.binding), amqp_empty_table);
    check_amqp_error(lua, amqp_get_rpc_reply(c->conn), "Binding queue");

  }

  queue_name = amqp_bytes_malloc_dup(r->queue);
  if (queue_name.bytes == NULL) {
    return luaL_error(lua, "Out of memory while copying queue name");
  }
  amqp_basic_consume(c->conn, 1, queue_name, amqp_empty_bytes, 0,
                     !c->manual_ack, cfg.exclusive, amqp_empty_table);
  check_amqp_error(lua, amqp_get_rpc_reply(c->conn), "Consuming");
  amqp_bytes_free(queue_name);
  return 1;
}


static int rmq_consumer_ack(lua_State *lua)
{
  consumer *c = check_consumer(lua, 1);
  if (!c->manual_ack || c->channel == 0) {
    lua_pushinteger(lua, 0);
  } else {
    lua_pushinteger(lua, (lua_Integer)amqp_basic_ack(
                        c->conn, c->channel, c->delivery_tag, 1));
    c->channel = 0;
    c->delivery_tag = 0;
  }
  return 1;
}


static int rmq_consumer_receive(lua_State *lua)
{
  consumer *c = check_consumer(lua, 1);

  struct timeval tval;
  struct timeval *tv;
  tv = &tval;
  tv->tv_sec = 1;
  tv->tv_usec = 0;

  amqp_rpc_reply_t res;
  amqp_envelope_t envelope;
  amqp_maybe_release_buffers(c->conn);
  res = amqp_consume_message(c->conn, &envelope, tv, 0);

  switch (res.reply_type) {
  case AMQP_RESPONSE_NORMAL:
    break;
  case AMQP_RESPONSE_LIBRARY_EXCEPTION:
    switch (res.library_error) {
    case AMQP_STATUS_TIMEOUT:
      return 0;
    case AMQP_STATUS_UNEXPECTED_STATE:
      {
        amqp_frame_t frame;
        int rv = amqp_simple_wait_frame(c->conn, &frame);
        if (AMQP_STATUS_OK != rv) {
          return luaL_error(lua, "amqp_simple_wait_frame rv: %d", rv);
        }

        if (AMQP_FRAME_METHOD == frame.frame_type) {
          switch (frame.payload.method.id) {
          case AMQP_BASIC_RETURN_METHOD:
            {
              amqp_message_t message;
              res = amqp_read_message(c->conn, frame.channel, &message, 0);
              check_amqp_error(lua, res, "amqp_read_message");
              amqp_destroy_message(&message);
            }
            return 0;
          case AMQP_BASIC_ACK_METHOD:
            return 0;
          default:
            break;
          }
        }
      }
    }
    /* FALLTHRU */
  default:
    check_amqp_error(lua, res, "amqp_consume_message");
    return 0;
  }

  c->channel = envelope.channel;
  c->delivery_tag = envelope.delivery_tag;
  lua_pushlstring(lua, envelope.message.body.bytes, envelope.message.body.len);
  if (envelope.message.properties._flags & AMQP_BASIC_CONTENT_TYPE_FLAG) {
    lua_pushlstring(lua, envelope.message.properties.content_type.bytes,
                    envelope.message.properties.content_type.len);
  } else {
    lua_pushstring(lua, "application/octet-stream");
  }
  lua_pushlstring(lua, envelope.exchange.bytes, envelope.exchange.len);
  lua_pushlstring(lua, envelope.routing_key.bytes, envelope.routing_key.len);
  amqp_destroy_envelope(&envelope);
  return 4;
}


static int rmq_consumer_gc(lua_State *lua)
{
  consumer *c = check_consumer(lua, 1);
  amqp_channel_close(c->conn, 1, AMQP_REPLY_SUCCESS);
  amqp_connection_close(c->conn, AMQP_REPLY_SUCCESS);
  amqp_destroy_connection(c->conn);
// librabbitmq > v0.8
//  if (c->ssl_enabled) {
//      amqp_uninitialize_ssl_library();
//  }
  return 0;
}


static const struct luaL_reg rabbitmqlib_f[] =
{
  { "consumer", rmq_consumer },
  { "version", rmq_version },
  { NULL, NULL }
};


static const struct luaL_reg consumerlib_m[] =
{
  { "ack", rmq_consumer_ack },
  { "receive", rmq_consumer_receive },
  { "__gc", rmq_consumer_gc },
  { NULL, NULL }
};


int luaopen_amqp(lua_State *lua)
{
  luaL_newmetatable(lua, mt_consumer);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, consumerlib_m);
  lua_pop(lua, 1);

  luaL_register(lua, module_table, rabbitmqlib_f);
  return 1;
}
