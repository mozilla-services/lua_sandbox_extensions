/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua bloom_filter implementation @file */

#include <limits.h>
#include <math.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"
#include "../common/xxhash.h"

#ifdef LUA_SANDBOX
#include "luasandbox_output.h"
#include "luasandbox_serialize.h"
#endif

static const char* mozsvc_bloom_filter = "mozsvc.bloom_filter";

typedef struct bloom_filter
{
  size_t items;
  size_t bytes;
  size_t bits;
  size_t cnt;
  unsigned int hashes;
  double probability;
  unsigned char data[];
} bloom_filter;


static int bloom_filter_new(lua_State* lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 2, 0, "incorrect number of arguments");
  int items = luaL_checkint(lua, 1);
  luaL_argcheck(lua, 1 < items, 1, "items must be > 1");
  double probability = luaL_checknumber(lua, 2);
  luaL_argcheck(lua, 0 < probability && 1 > probability, 2, "probability must be between 0 and 1");

  size_t bits = (size_t)ceil(items * log(probability) / log(1 / pow(2, log(2))));
  size_t bytes = (size_t)ceil((double)bits / CHAR_BIT);
  unsigned int hashes = (unsigned int)round(log(2) * bits / items);

  size_t nbytes = sizeof(bloom_filter) + bytes;
  bloom_filter* bf = (bloom_filter*)lua_newuserdata(lua, nbytes);
  bf->items = items;
  bf->bits = bits;
  bf->bytes = bytes;
  bf->hashes = hashes;
  bf->probability = probability;
  bf->cnt = 0;
  memset(bf->data, 0, bf->bytes);

  luaL_getmetatable(lua, mozsvc_bloom_filter);
  lua_setmetatable(lua, -2);

  return 1;
}


static bloom_filter* check_bloom_filter(lua_State* lua, int args)
{
  bloom_filter *bf = luaL_checkudata(lua, 1, mozsvc_bloom_filter);
  luaL_argcheck(lua, args == lua_gettop(lua), 0,
                "incorrect number of arguments");
  return bf;
}


static int bloom_filter_add(lua_State* lua)
{
  bloom_filter* bf = check_bloom_filter(lua, 2);
  size_t len = 0;
  double val = 0;
  void* key = NULL;
  switch (lua_type(lua, 2)) {
  case LUA_TSTRING:
    key = (void*)lua_tolstring(lua, 2, &len);
    break;
  case LUA_TNUMBER:
    val = lua_tonumber(lua, 2);
    len = sizeof(double);
    key = &val;
    break;
  default:
    luaL_argerror(lua, 2, "must be a string or number");
    break;
  }
  unsigned int bit = 0;
  int added = 0;

  for (unsigned int i = 0; i < bf->hashes; ++i) {
    bit = XXH32(key, (int)len, i) % bf->bits;
    if (!(bf->data[bit / CHAR_BIT] & 1 << (bit % CHAR_BIT))) {
      bf->data[bit / CHAR_BIT] |= 1 << (bit % CHAR_BIT);
      added = 1;
    }
  }

  if (added) {
    ++bf->cnt;
  }

  lua_pushboolean(lua, added);
  return 1;
}


static int bloom_filter_query(lua_State* lua)
{
  bloom_filter* bf = check_bloom_filter(lua, 2);
  size_t len = 0;
  double val = 0;
  void* key = NULL;
  switch (lua_type(lua, 2)) {
  case LUA_TSTRING:
    key = (void*)lua_tolstring(lua, 2, &len);
    break;
  case LUA_TNUMBER:
    val = lua_tonumber(lua, 2);
    len = sizeof(double);
    key = &val;
    break;
  default:
    luaL_argerror(lua, 2, "must be a string or number");
    break;
  }
  unsigned int bit = 0;
  int found = 1;

  for (unsigned int i = 0; i < bf->hashes && found; ++i) {
    bit = XXH32(key, (int)len, i) % bf->bits;
    found = bf->data[bit / CHAR_BIT] & 1 << (bit % CHAR_BIT);
  }

  lua_pushboolean(lua, found);
  return 1;
}


static int bloom_filter_count(lua_State* lua)
{
  bloom_filter* bf = check_bloom_filter(lua, 1);
  lua_pushnumber(lua, (lua_Number)bf->cnt);
  return 1;
}


static int bloom_filter_clear(lua_State* lua)
{
  bloom_filter* bf = check_bloom_filter(lua, 1);
  memset(bf->data, 0, bf->bytes);
  bf->cnt = 0;
  return 0;
}


static int bloom_filter_version(lua_State* lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


#ifdef LUA_SANDBOX
static int bloom_filter_fromstring(lua_State* lua)
{
  size_t len = 0;
  const char* values = NULL;
  bloom_filter* bf = NULL;

  if (lua_gettop(lua) == 2) { // todo remove conditional check after migration
    bf = check_bloom_filter(lua, 2);
    values = luaL_checklstring(lua, 2, &len);
  } else {
    bf = check_bloom_filter(lua, 3);
    bf->cnt = (size_t)luaL_checknumber(lua, 2);
    values = luaL_checklstring(lua, 3, &len);
  }
  if (len != bf->bytes) {
    luaL_error(lua, "fromstring() bytes found: %d, expected %d", len, bf->bytes);
  }
  memcpy(bf->data, values, len);
  return 0;
}


static int serialize_bloom_filter(lua_State *lua) {
  lsb_output_buffer* ob = lua_touserdata(lua, -1);
  const char *key = lua_touserdata(lua, -2);
  bloom_filter* bf = lua_touserdata(lua, -3);
  if (!(ob && key && bf)) {
    return 1;
  }
  if (lsb_outputf(ob,
                  "if %s == nil then %s = bloom_filter.new(%u, %g) end\n",
                  key,
                  key,
                  (unsigned)bf->items,
                  bf->probability)) {
    return 1;
  }

  if (lsb_outputf(ob, "%s:fromstring(%u, \"", key, (unsigned)bf->cnt)) {
    return 1;
  }
  if (lsb_serialize_binary(ob, bf->data, bf->bytes)) return 1;
  if (lsb_outputs(ob, "\")\n", 3)) {
    return 1;
  }
  return 0;
}
#endif


static const struct luaL_reg bloom_filterlib_f[] =
{
  { "new", bloom_filter_new }
  , { "version", bloom_filter_version }
  , { NULL, NULL }
};


static const struct luaL_reg bloom_filterlib_m[] =
{
  { "add", bloom_filter_add }
  , { "query", bloom_filter_query }
  , { "clear", bloom_filter_clear }
  , { "count", bloom_filter_count }
#ifdef LUA_SANDBOX
  , { "fromstring", bloom_filter_fromstring } // used for data restoration
#endif
  , { NULL, NULL }
};


int luaopen_bloom_filter(lua_State* lua)
{
#ifdef LUA_SANDBOX
  lua_newtable(lua);
  lsb_add_serialize_function(lua, serialize_bloom_filter);
  lua_replace(lua, LUA_ENVIRONINDEX);
#endif
  luaL_newmetatable(lua, mozsvc_bloom_filter);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, bloom_filterlib_m);
  luaL_register(lua, "bloom_filter", bloom_filterlib_f);
  return 1;
}
