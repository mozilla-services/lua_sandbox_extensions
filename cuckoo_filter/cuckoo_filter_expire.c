/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua cuckoo_filter_expire implementation @file */

#include <limits.h>
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "common.h"
#include "lauxlib.h"
#include "lua.h"
#include "../common/xxhash.h"

#ifdef LUA_SANDBOX
#include "luasandbox_output.h"
#include "luasandbox_serialize.h"
#endif

#define MAX_INTERVALS 256

static const char *module_name  = "mozsvc.cuckoo_filter_expire";
static const char *module_table = "cuckoo_filter_expire";

typedef struct cuckoo_bucket
{
  uint32_t  entries[BUCKET_SIZE];
  uint8_t   interval[BUCKET_SIZE];
} cuckoo_bucket;

typedef struct cuckoo_filter
{
  size_t  items;
  size_t  bytes;
  size_t  num_buckets;
  size_t  cnt;
  time_t  timet;
  int     nlz;
  int     interval;
  int     interval_size;
  int     lru_interval;
  cuckoo_bucket buckets[];
} cuckoo_filter;


static void clear(cuckoo_filter *cf)
{
  cf->interval      = MAX_INTERVALS - 1;
  cf->lru_interval  = -1;
  cf->cnt           = 0;
  cf->timet         = (MAX_INTERVALS - 1) * cf->interval_size;
  memset(cf->buckets, 0, cf->bytes);
}


static int index_r2v(cuckoo_filter *cf, int idx)
{
  idx = idx - ((cf->interval + 1) % MAX_INTERVALS);
  if (idx < 0) {
    idx += MAX_INTERVALS;
  }
  return idx;
}


static unsigned index_v2r(cuckoo_filter *cf, int idx)
{
  return (idx + ((cf->interval + 1) % MAX_INTERVALS)) % MAX_INTERVALS;
}


static int cf_new(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 2, 0, "incorrect number of arguments");
  int items = luaL_checkint(lua, 1);
  luaL_argcheck(lua, items > MAX_INTERVALS, 1, "items must be > 256");
  int mins = luaL_optint(lua, 2, 1);
  luaL_argcheck(lua, mins > 0 && mins <= 1440, 2, "0 < interval size <= 1440");

  unsigned buckets  = clp2((unsigned)ceil(items / BUCKET_SIZE));
  size_t bytes      = sizeof(cuckoo_bucket) * buckets;
  size_t nbytes     = sizeof(cuckoo_filter) + bytes;
  cuckoo_filter *cf = lua_newuserdata(lua, nbytes);
  cf->items         = buckets * BUCKET_SIZE;
  cf->num_buckets   = buckets;
  cf->bytes         = bytes;
  cf->nlz           = nlz(buckets) + 1;
  cf->interval_size = 60 * mins;
  clear(cf);
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


static bool bucket_lookup(lua_State *lua, cuckoo_bucket *b, uint32_t fp)
{
  for (int i = 0; i < BUCKET_SIZE; ++i) {
    if (b->entries[i] == fp) {
      lua_pushboolean(lua, true);
      lua_pushinteger(lua, b->interval[i]);
      return true;
    }
  }
  return false;
}


static bool bucket_insert_lookup(lua_State *lua, cuckoo_filter *cf,
                                 unsigned idx, uint32_t fp, uint8_t interval)
{
  cuckoo_bucket *b = &cf->buckets[idx];
  for (int i = 0; i < BUCKET_SIZE; ++i) {
    if (b->entries[i] == fp) {
      lua_pushboolean(lua, false);
      int cidx = index_r2v(cf, interval);
      int pidx = index_r2v(cf, b->interval[i]);
      int delta;
      if (cidx > pidx) {
        b->interval[i] = interval;
        delta = cidx - pidx;
      } else {
        delta = pidx - cidx;
      }
      lua_pushinteger(lua, delta);
      return true;
    }
  }
  return false;
}


static bool bucket_delete(cuckoo_bucket *b, uint32_t fp)
{
  for (int i = 0; i < BUCKET_SIZE; ++i) {
    if (b->entries[i] == fp) {
      b->entries[i] = 0;
      b->interval[i] = 0;
      return true;
    }
  }
  return false;
}


static bool bucket_add(cuckoo_bucket *b, uint32_t fp, uint8_t interval)
{
  for (int i = 0; i < BUCKET_SIZE; ++i) {
    if (b->entries[i] == 0) {
      b->entries[i] = fp;
      b->interval[i] = interval;
      return true;
    }
  }
  return false;
}


static bool bucket_insert(lua_State *lua, cuckoo_filter *cf, unsigned i1,
                          unsigned i2, uint32_t fp, uint8_t interval)
{
  // since we must handle duplicates we consider any collision within the bucket
  // to be a duplicate. The 32 bit fingerprint makes the false postive rate very
  // low 0.0000000019
  if (bucket_insert_lookup(lua, cf, i1, fp, interval)) return false;
  if (bucket_insert_lookup(lua, cf, i2, fp, interval)) return false;

  if (!bucket_add(&cf->buckets[i1], fp, interval)) {
    if (!bucket_add(&cf->buckets[i2], fp, interval)) {
      unsigned ri;
      if (rand() % 2) {
        ri = i1;
      } else {
        ri = i2;
      }
      for (int i = 0; i < 512; ++i) {
        int entry = rand() % BUCKET_SIZE;
        unsigned tmp = cf->buckets[ri].entries[entry];
        uint8_t tinterval = cf->buckets[ri].interval[entry];
        cf->buckets[ri].entries[entry] = fp;
        cf->buckets[ri].interval[entry] = interval;
        fp = tmp;
        interval = tinterval;
        ri = ri ^ (XXH64(&fp, sizeof(uint32_t), 1) >> (cf->nlz + 32));
        if (bucket_insert_lookup(lua, cf, ri, fp, interval)) return false;
        if (bucket_add(&cf->buckets[ri], fp, interval)) return true;
      }
      luaL_error(lua, "the cuckoo filter is full");
    }
  }
  return true;
}


static int prune_range(cuckoo_filter *cf, int start, int end)
{
  int lru_vidx = MAX_INTERVALS - 1;
  for (size_t i = 0; i < cf->num_buckets; ++i) {
    for (int j = 0; j < BUCKET_SIZE; ++j) {
      if (cf->buckets[i].entries[j] != 0) {
        int interval = cf->buckets[i].interval[j];
        if ((end >= start && (interval >= start && interval <= end))
            || (end < start && (interval >= start || interval <= end))) {
          cf->buckets[i].entries[j] = 0;
          cf->buckets[i].interval[j] = 0;
          --cf->cnt;
        }
        int vidx = index_r2v(cf, interval);
        if (vidx < lru_vidx) {lru_vidx = vidx;}
      }
    }
  }
  return index_v2r(cf, lru_vidx);
}


static int cf_add(lua_State *lua)
{
  cuckoo_filter *cf = check_cuckoo_filter(lua, 3);
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
  time_t timet = (time_t)(luaL_checknumber(lua, 3) / 1e9);
  int interval = 0;
  timet = timet - (timet % cf->interval_size);
  if (timet < cf->timet - cf->interval_size * (MAX_INTERVALS - 1)) {
    lua_pushboolean(lua, 0);
    return 1;
  }
  interval = timet / cf->interval_size % MAX_INTERVALS;

  if (cf->interval != interval && timet > cf->timet) { // expire due to time
    int oldest = (cf->interval + 1) % MAX_INTERVALS;
    if (cf->cnt > 0) {
      cf->lru_interval = prune_range(cf, oldest, interval);
    }
    cf->interval = interval;
    cf->timet = timet;
  }

  if ((double)cf->cnt / cf->items >= 0.8) { // expire due to capacity
    if (cf->lru_interval == -1) {
      cf->lru_interval = (cf->interval + 1) % MAX_INTERVALS;
    }
    cf->lru_interval = prune_range(cf, cf->lru_interval, cf->lru_interval);
  }

  uint64_t h = XXH64(key, (int)len, 1);
  uint32_t fp = fingerprint32(h);
  unsigned i1 = h % cf->num_buckets;
  unsigned i2 = i1 ^ (XXH64(&fp, sizeof(uint32_t), 1) >> (cf->nlz + 32));
  bool success = bucket_insert(lua, cf, i1, i2, fp, interval);
  if (success) {
    ++cf->cnt;
    lua_pushboolean(lua, success);
    lua_pushinteger(lua, 0);
  }
  return 2;
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
  uint32_t fp = fingerprint32(h);
  unsigned i1 = h % cf->num_buckets;
  bool found = bucket_lookup(lua, &cf->buckets[i1], fp);
  if (!found) {
    unsigned i2 = i1 ^ (XXH64(&fp, sizeof(uint32_t), 1) >> (cf->nlz + 32));
    found = bucket_lookup(lua, &cf->buckets[i2], fp);
  }
  if (found) return 2;

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
  uint32_t fp = fingerprint32(h);
  unsigned i1 = h % cf->num_buckets;
  bool deleted = bucket_delete(&cf->buckets[i1], fp);
  if (!deleted) {
    unsigned i2 = i1 ^ (XXH64(&fp, sizeof(uint32_t), 1) >> (cf->nlz + 32));
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
  clear(cf);
  return 0;
}


static int cf_version(lua_State *lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


static int cf_current_interval(lua_State *lua)
{
  cuckoo_filter *cf = check_cuckoo_filter(lua, 1);
  lua_pushnumber(lua, cf->timet * 1e9);
  lua_pushinteger(lua, cf->interval);
  return 2;
}


#ifdef LUA_SANDBOX
static int cf_fromstring(lua_State *lua)
{
  if (lua_gettop(lua) == 4) {
    lua_remove(lua, 3); // interval_size was removed from the API
  }
  cuckoo_filter *cf = check_cuckoo_filter(lua, 3);
  cf->cnt = (size_t)luaL_checknumber(lua, 2);
  size_t len = 0;
  const char *values = luaL_checklstring(lua, 3, &len);
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
                  "if %s == nil then %s = %s.new(%u, %d) end\n",
                  key,
                  key,
                  module_table,
                  (unsigned)cf->items,
                  cf->interval_size / 60
                 )) {

    return 1;
  }

  if (lsb_outputf(ob, "%s:fromstring(%u, \"", key, (unsigned)cf->cnt)) {
    return 1;
  }
  if (lsb_serialize_binary(ob, cf->buckets, cf->bytes)) return 1;
  if (lsb_outputs(ob, "\")\n", 3)) {
    return 1;
  }
  return 0;
}
#endif


static const struct luaL_reg cuckoo_filterlib_f[] = {
  { "new", cf_new },
  { "version", cf_version },
  { NULL, NULL }
};


static const struct luaL_reg cuckoo_filterlib_m[] = {
  { "add", cf_add },
  { "query", cf_query },
  { "delete", cf_delete },
  { "count", cf_count },
  { "clear", cf_clear },
  { "current_interval", cf_current_interval },
#ifdef LUA_SANDBOX
  { "fromstring", cf_fromstring }, // used for data restoration
#endif
  { NULL, NULL }
};


int luaopen_cuckoo_filter_expire(lua_State *lua)
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
  luaL_register(lua, module_table, cuckoo_filterlib_f);
  return 1;
}
