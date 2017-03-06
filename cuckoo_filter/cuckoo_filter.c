/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua cuckoo_filter implementation @file */

#include <limits.h>
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "common.h"
#include "lauxlib.h"
#include "lua.h"
#include "../common/xxhash.h"

#ifdef LUA_SANDBOX
#include "luasandbox_output.h"
#include "luasandbox_serialize.h"
#endif

static const char *module_name  = "mozsvc.cuckoo_filter";
static const char *module_table = "cuckoo_filter";
static int binary_version = 1;

typedef struct cuckoo_bucket
{
  uint16_t entries[BUCKET_SIZE];
} cuckoo_bucket;


typedef struct cuckoo_filter
{
  size_t items;
  size_t bytes;
  size_t num_buckets;
  size_t cnt;
  int nlz;
  cuckoo_bucket buckets[];
} cuckoo_filter;


static int cf_new(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 1, 0, "incorrect number of arguments");
  int items = luaL_checkint(lua, 1);
  luaL_argcheck(lua, items > 4, 1, "items must be > 4");

  unsigned buckets  = clp2((unsigned)ceil(items / BUCKET_SIZE));
  size_t bytes      = sizeof(cuckoo_bucket) * buckets;
  size_t nbytes     = sizeof(cuckoo_filter) + bytes;
  cuckoo_filter *cf = (cuckoo_filter *)lua_newuserdata(lua, nbytes);
  cf->items         = buckets * BUCKET_SIZE;
  cf->num_buckets   = buckets;
  cf->bytes         = bytes;
  cf->cnt           = 0;
  cf->nlz           = nlz(buckets) + 1;
  memset(cf->buckets, 0, cf->bytes);
  luaL_getmetatable(lua, module_name);
  lua_setmetatable(lua, -2);
  return 1;
}


static cuckoo_filter* check_cuckoo_filter(lua_State *lua, int args)
{
  cuckoo_filter *cf = luaL_checkudata(lua, 1, module_name);
  luaL_argcheck(lua, args == lua_gettop(lua), 0,
                "incorrect number of arguments");
  return cf;
}


static bool bucket_lookup(cuckoo_bucket *b, uint16_t fp)
{
  for (int i = 0; i < BUCKET_SIZE; ++i) {
    if (b->entries[i] == fp) return true;
  }
  return false;
}


static bool bucket_delete(cuckoo_bucket *b, uint16_t fp)
{
  for (int i = 0; i < BUCKET_SIZE; ++i) {
    if (b->entries[i] == fp) {
      b->entries[i] = 0;
      return true;
    }
  }
  return false;
}


static bool bucket_add(cuckoo_bucket *b, uint16_t fp)
{
  for (int i = 0; i < BUCKET_SIZE; ++i) {
    if (b->entries[i] == 0) {
      b->entries[i] = fp;
      return true;
    }
  }
  return false;
}


static bool bucket_insert(lua_State *lua, cuckoo_filter *cf, unsigned i1,
                          unsigned i2, uint16_t fp)
{
  // since we must handle duplicates we consider any collision within the bucket
  // to be a duplicate. The 16 bit fingerprint makes the false postive rate very
  // low 0.00012
  if (bucket_lookup(&cf->buckets[i1], fp)) return false;
  if (bucket_lookup(&cf->buckets[i2], fp)) return false;

  if (!bucket_add(&cf->buckets[i1], fp)) {
    if (!bucket_add(&cf->buckets[i2], fp)) {
      unsigned ri;
      if (rand() % 2) {
        ri = i1;
      } else {
        ri = i2;
      }
      for (int i = 0; i < 512; ++i) {
        int entry = rand() % BUCKET_SIZE;
        unsigned tmp = cf->buckets[ri].entries[entry];
        cf->buckets[ri].entries[entry] = fp;
        fp = tmp;
        ri = ri ^ (XXH64(&fp, sizeof(uint16_t), 1) >> (cf->nlz + 32));
        if (bucket_lookup(&cf->buckets[ri], fp)) return false;
        if (bucket_add(&cf->buckets[ri], fp)) {
          return true;
        }
      }
      luaL_error(lua, "the cuckoo filter is full");
    }
  }
  return true;
}


static int cf_add(lua_State *lua)
{
  cuckoo_filter *cf = check_cuckoo_filter(lua, 2);
  size_t len = 0;
  double val = 0;
  void *key = NULL;
  switch (lua_type(lua, 2)) {
  case LUA_TSTRING:
    key = (void *)lua_tolstring(lua, 2, &len);
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
  uint64_t h = XXH64(key, (int)len, 1);
  uint16_t fp = fingerprint16(h);
  unsigned i1 = h % cf->num_buckets;
  unsigned i2 = i1 ^ (XXH64(&fp, sizeof(uint16_t), 1) >> (cf->nlz + 32));
  bool success = bucket_insert(lua, cf, i1, i2, fp);
  if (success) {
    ++cf->cnt;
  }
  lua_pushboolean(lua, success);
  return 1;
}


static int cf_query(lua_State *lua)
{
  cuckoo_filter *cf = check_cuckoo_filter(lua, 2);
  size_t len = 0;
  double val = 0;
  void *key = NULL;
  switch (lua_type(lua, 2)) {
  case LUA_TSTRING:
    key = (void *)lua_tolstring(lua, 2, &len);
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
  uint64_t h = XXH64(key, (int)len, 1);
  uint16_t fp = fingerprint16(h);
  unsigned i1 = h % cf->num_buckets;
  bool found = bucket_lookup(&cf->buckets[i1], fp);
  if (!found) {
    unsigned i2 = i1 ^ (XXH64(&fp, sizeof(uint16_t), 1) >> (cf->nlz + 32));
    found = bucket_lookup(&cf->buckets[i2], fp);
  }
  lua_pushboolean(lua, found);
  return 1;
}


static int cf_delete(lua_State *lua)
{
  cuckoo_filter *cf = check_cuckoo_filter(lua, 2);
  size_t len = 0;
  double val = 0;
  void *key = NULL;
  switch (lua_type(lua, 2)) {
  case LUA_TSTRING:
    key = (void *)lua_tolstring(lua, 2, &len);
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
  uint64_t h = XXH64(key, (int)len, 1);
  uint16_t fp = fingerprint16(h);
  unsigned i1 = h % cf->num_buckets;
  bool deleted = bucket_delete(&cf->buckets[i1], fp);
  if (!deleted) {
    unsigned i2 = i1 ^ (XXH64(&fp, sizeof(uint16_t), 1) >> (cf->nlz + 32));
    deleted = bucket_delete(&cf->buckets[i2], fp);
  }
  if (deleted) {
    --cf->cnt;
  }
  lua_pushboolean(lua, deleted);
  return 1;
}


static int cf_count(lua_State *lua)
{
  cuckoo_filter *cf = check_cuckoo_filter(lua, 1);
  lua_pushnumber(lua, (lua_Number)cf->cnt);
  return 1;
}


static int cf_clear(lua_State *lua)
{
  cuckoo_filter *cf = check_cuckoo_filter(lua, 1);
  memset(cf->buckets, 0, cf->bytes);
  cf->cnt = 0;
  return 0;
}


static int cf_version(lua_State *lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


#ifdef LUA_SANDBOX
static int cf_fromstring(lua_State *lua)
{
  cuckoo_filter *cf = check_cuckoo_filter(lua, 4);
  cf->cnt = (size_t)luaL_checknumber(lua, 2);
  size_t len = 0;
  const char *values = luaL_checklstring(lua, 3, &len);
  if (luaL_optint(lua, 4, 0) != binary_version) {
    return 0;
  }
  if (len != cf->bytes) {
    luaL_error(lua, "fromstring() bytes found: %d, expected %d", len,
               cf->bytes);
  }
  memcpy(cf->buckets, values, len);
  return 0;
}


static int serialize_cuckoo_filter(lua_State *lua)
{
  lsb_output_buffer *ob = lua_touserdata(lua, -1);
  const char *key = lua_touserdata(lua, -2);
  cuckoo_filter *cf = lua_touserdata(lua, -3);
  if (!(ob && key && cf)) {
    return 1;
  }
  if (lsb_outputf(ob,
                  "if %s == nil then %s = %s.new(%u) end\n",
                  key,
                  key,
                  module_table,
                  (unsigned)cf->items)) {
    return 1;
  }

  if (lsb_outputf(ob, "%s:fromstring(%d, \"", key, (unsigned)cf->cnt)) return 1;
  if (lsb_serialize_binary(ob, cf->buckets, cf->bytes)) return 1;
  if (lsb_outputf(ob, "\", %d)\n", binary_version)) return 1;
  return 0;
}
#endif


static const struct luaL_reg cuckoo_filterlib_f[] =
{
  { "new", cf_new },
  { "version", cf_version },
  { NULL, NULL }
};


static const struct luaL_reg cuckoo_filterlib_m[] =
{
  { "add", cf_add },
  { "query", cf_query },
  { "delete", cf_delete },
  { "count", cf_count },
  { "clear", cf_clear },
#ifdef LUA_SANDBOX
  { "fromstring", cf_fromstring }, // used for data restoration
#endif
  { NULL, NULL }
};


int luaopen_cuckoo_filter(lua_State *lua)
{
#ifdef LUA_SANDBOX
  lua_newtable(lua);
  lsb_add_serialize_function(lua, serialize_cuckoo_filter);
  lua_replace(lua, LUA_ENVIRONINDEX);
#endif
  luaL_newmetatable(lua, module_name);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, cuckoo_filterlib_m);
  luaL_register(lua, "cuckoo_filter", cuckoo_filterlib_f);
  return 1;
}
