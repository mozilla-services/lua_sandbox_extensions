/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua xxhash wrapper @file */

#include <limits.h>

#include "lauxlib.h"
#include "lua.h"
#include "../common/xxhash.h"


static void
verify_item(lua_State* lua, const void **item, size_t *len, lua_Number *d)
{
  switch (lua_type(lua, 1)) {
  case LUA_TSTRING:
    *item = lua_tolstring(lua, 1, len);
    break;
  case LUA_TNUMBER:
    {
      *d = lua_tonumber(lua, 1);
      *item = d;
      *len = sizeof(lua_Number);
    }
    break;
  default:
    luaL_typerror(lua, 1, "string or number");
    break;
  }
}


static int h32(lua_State* lua)
{
  const void *item = NULL;
  size_t len = 0;
  lua_Number d;
  verify_item(lua, &item, &len, &d);
  lua_Number n = luaL_optnumber(lua, 2, 0);
  luaL_argcheck(lua, n >=0 && n <= UINT_MAX, 2, "seed must be an unsigned int");
  unsigned seed = (unsigned)n;
  lua_pushnumber(lua, XXH32(item, len, seed));
  return 1;
}


static int h64(lua_State* lua)
{
  const void *item = NULL;
  size_t len = 0;
  lua_Number d;
  verify_item(lua, &item, &len, &d);
  lua_Number n = luaL_optnumber(lua, 2, 0);
  luaL_argcheck(lua, n >=0 && n <= ULLONG_MAX, 2,
                "seed must be an unsigned long long");
  unsigned long long seed = (unsigned long long)n;
  lua_pushnumber(lua, XXH64(item, len, seed));
  return 1;
}


static const struct luaL_reg xxhashlib_f[] =
{
  { "h32", h32 }
  , { "h64", h64 }
  , { NULL, NULL }
};


int luaopen_xxhash(lua_State* lua)
{
  luaL_register(lua, "xxhash", xxhashlib_f);
  return 1;
}
