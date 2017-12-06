/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua hyperloglog implementation @file */

#include <math.h>
#include <string.h>

#include "lauxlib.h"
#include "lua.h"
#include "redis_hyperloglog.h"

#ifdef LUA_SANDBOX
#include "luasandbox_output.h"
#include "luasandbox_serialize.h"
#endif

/* The cached cardinality MSB is used to signal validity of the cached value. */
#define HLL_INVALIDATE_CACHE(hll) (hll)->card[7] |= (1<<7)
#define HLL_VALID_CACHE(hll) (((hll)->card[7] & (1<<7)) == 0)

static const char *mozsvc_hyperloglog = "mozsvc.hyperloglog";

static const char *hll_magic = "HYLL";


static hyperloglog* check_hll(lua_State *lua, int args)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, args == n, n, "incorrect number of arguments");
  hyperloglog *hll = luaL_checkudata(lua, 1, mozsvc_hyperloglog);
  return hll;
}


static int hll_new(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 0, n, "incorrect number of arguments");

  size_t nbytes = sizeof(hyperloglog);
  hyperloglog *hll = lua_newuserdata(lua, nbytes);
  memcpy(hll->magic, hll_magic, sizeof(hll->magic));
  hll->encoding = HLL_DENSE;
  memset(hll->card, 0, sizeof(hll->card));
  HLL_INVALIDATE_CACHE(hll);
  memset(hll->notused, 0, sizeof(hll->notused));
  memset(hll->registers, 0, HLL_REGISTERS_SIZE);

  luaL_getmetatable(lua, mozsvc_hyperloglog);
  lua_setmetatable(lua, -2);

  return 1;
}


static int hll_set_count(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n > 1, n, "incorrect number of arguments");

  uint8_t max[HLL_HDR_SIZE + HLL_REGISTERS], *registers;
  memset(max, 0, sizeof max);
  hyperloglog *raw = (hyperloglog *)max;
  raw->encoding = HLL_RAW;
  registers = max + HLL_HDR_SIZE;

  for (int idx = 1; idx <= n; ++idx) {
    hyperloglog *hll = luaL_checkudata(lua, idx, mozsvc_hyperloglog);
    uint8_t val;
    for (int i = 0; i < HLL_REGISTERS; i++) {
      HLL_DENSE_GET_REGISTER(val, hll->registers, i);
      if (val > registers[i]) registers[i] = val;
    }
  }

  uint64_t card = hllCount(raw);
  lua_pushnumber(lua, (double)card);
  return 1;
}


static int hll_add(lua_State *lua)
{
  hyperloglog *hll = check_hll(lua, 2);
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

  int altered = 0;
  if (1 == hllDenseAdd(hll->registers, (unsigned char *)key, len)) {
    HLL_INVALIDATE_CACHE(hll);
    altered = 1;
  }

  lua_pushboolean(lua, altered);
  return 1;
}


static int hll_merge(lua_State *lua)
{
  hyperloglog *dest = check_hll(lua, 2);
  hyperloglog *src = luaL_checkudata(lua, 2, mozsvc_hyperloglog);
  if (dest == src) {
    return 1;
  }

  int i;
  uint8_t sval, dval;
  for (i = 0; i < HLL_REGISTERS; i++) {
    HLL_DENSE_GET_REGISTER(dval, dest->registers, i);
    HLL_DENSE_GET_REGISTER(sval, src->registers, i);
    if (sval > dval) {
      HLL_DENSE_SET_REGISTER(dest->registers, i, sval);
    }
  }
  HLL_INVALIDATE_CACHE(dest);
  lua_pushvalue(lua, 1);
  return 1;
}


static int hll_count(lua_State *lua)
{
  hyperloglog *hll = check_hll(lua, 1);
  uint64_t card;
  /* Check if the cached cardinality is valid. */
  if (HLL_VALID_CACHE(hll)) {
    /* Just return the cached value. */
    card =  (uint64_t)hll->card[0];
    card |= (uint64_t)hll->card[1] << 8;
    card |= (uint64_t)hll->card[2] << 16;
    card |= (uint64_t)hll->card[3] << 24;
    card |= (uint64_t)hll->card[4] << 32;
    card |= (uint64_t)hll->card[5] << 40;
    card |= (uint64_t)hll->card[6] << 48;
    card |= (uint64_t)hll->card[7] << 56;
  } else {
    /* Recompute it and update the cached value. */
    card = hllCount(hll);
    hll->card[0] = card & 0xff;
    hll->card[1] = (card >> 8) & 0xff;
    hll->card[2] = (card >> 16) & 0xff;
    hll->card[3] = (card >> 24) & 0xff;
    hll->card[4] = (card >> 32) & 0xff;
    hll->card[5] = (card >> 40) & 0xff;
    hll->card[6] = (card >> 48) & 0xff;
    hll->card[7] = (card >> 56) & 0xff;
  }

  lua_pushnumber(lua, (double)card);
  return 1;
}


static int hll_clear(lua_State *lua)
{
  hyperloglog *hll = check_hll(lua, 1);
  memset(hll->registers, 0, HLL_REGISTERS_SIZE);
  HLL_INVALIDATE_CACHE(hll);
  return 0;
}


static int hll_fromstring(lua_State *lua)
{
  hyperloglog *hll = check_hll(lua, 2);
  size_t len = 0;
  const char *values  = luaL_checklstring(lua, 2, &len);
  if (len != sizeof(hyperloglog) - 1) {
    luaL_error(lua, "fromstring() bytes found: %d, expected %d",
               len, sizeof(hyperloglog) - 1);
  }
  if (memcmp(values, hll_magic, sizeof(hll->magic)) != 0) {
    luaL_error(lua, "fromstring() HYLL header not found");
  }
  if (values[5] != HLL_DENSE) {
    luaL_error(lua, "fromstring() invalid encoding");
  }
  memcpy(hll, values, sizeof(hyperloglog) - 1);
  return 0;
}


static int hll_version(lua_State *lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


#ifdef LUA_SANDBOX
static int serialize_hyperloglog(lua_State *lua)
{
  lsb_output_buffer *ob = lua_touserdata(lua, -1);
  const char *key = lua_touserdata(lua, -2);
  hyperloglog *hll = lua_touserdata(lua, -3);
  if (!(ob && key && hll)) return 1;

  if (lsb_outputf(ob,
                  "if %s == nil then %s = hyperloglog.new() end\n", key, key)) {
    return 1;
  }

  if (lsb_outputf(ob, "%s:fromstring(\"", key)) return 1;
  if (lsb_serialize_binary(ob, hll, sizeof(hyperloglog) - 1)) return 1;
  if (lsb_outputs(ob, "\")\n", 3)) return 1;
  return 0;
}


static int output_hyperloglog(lua_State *lua)
{
  lsb_output_buffer *ob = lua_touserdata(lua, -1);
  hyperloglog *hll = lua_touserdata(lua, -2);
  if (!(ob && hll)) return 1;
  if (lsb_outputs(ob, (const char *)hll, sizeof(hyperloglog) - 1)) return 1;
  return 0;
}
#endif


static int hll_tostring(lua_State *lua)
{
  hyperloglog *hll = check_hll(lua, 1);
  lua_pushlstring(lua, (const char *)hll, sizeof(hyperloglog) - 1);
  return 1;
}


static const struct luaL_reg hyperlogloglib_f[] =
{
  { "new", hll_new },
  { "count", hll_set_count },
  { "version", hll_version },
  { NULL, NULL }
};


static const struct luaL_reg hyperlogloglib_m[] =
{
  { "add", hll_add },
  { "count", hll_count },
  { "clear", hll_clear },
  { "merge", hll_merge },
  { "fromstring", hll_fromstring },
  { "__tostring", hll_tostring },
  { NULL, NULL }
};


int luaopen_hyperloglog(lua_State *lua)
{
#ifdef LUA_SANDBOX
  lua_newtable(lua);
  lsb_add_serialize_function(lua, serialize_hyperloglog);
  lsb_add_output_function(lua, output_hyperloglog);
  lua_replace(lua, LUA_ENVIRONINDEX);
#endif
  luaL_newmetatable(lua, mozsvc_hyperloglog);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, hyperlogloglib_m);
  luaL_register(lua, "hyperloglog", hyperlogloglib_f);

  return 1;
}
