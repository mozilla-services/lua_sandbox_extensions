/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua gzip File Access Function @file */

#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#include "lauxlib.h"
#include "lua.h"

static const char *module_name  = "mozsvc.gzfile";
static const char *module_table = "gzfile";

typedef struct gzfile
{
  gzFile      fh;
  luaL_Buffer *pbuf;
  luaL_Buffer buf;
} gzfile;


static gzfile* check_gzfile(lua_State *lua, int args)
{
  gzfile *gzf = luaL_checkudata(lua, 1, module_name);
  luaL_argcheck(lua, lua_gettop(lua) <= args, 0,
                "incorrect number of arguments");
  return gzf;
}


static int gzfile_open(lua_State *lua)
{
  luaL_argcheck(lua, lua_gettop(lua) <= 3, 0, "incorrect number of arguments");
  const char *fn    = luaL_checkstring(lua, 1);
  const char *mode  = luaL_optstring(lua, 2, "rb");
  int bsize         = luaL_optint(lua, 3, 8 * 1024);
  luaL_argcheck(lua, bsize > 0, 3, "buffer_size must be > 0");

  gzfile *gzf = lua_newuserdata(lua, sizeof(gzfile));
  gzf->fh     = NULL;
  gzf->pbuf   = NULL;
  luaL_getmetatable(lua, module_name);
  lua_setmetatable(lua, -2);

  gzf->fh = gzopen(fn, mode);
  if (gzf->fh) {
    gzbuffer(gzf->fh, bsize);
  } else {
    lua_pushnil(lua);
    lua_pushstring(lua, "open failed");
    return 2;
  }
  return 1;
}


static int gzfile_close(lua_State *lua)
{
  gzfile *gzf = check_gzfile(lua, 1);
  if (gzf->fh) {
    gzclose(gzf->fh);
    gzf->fh = NULL;
  }
  return 0;
}


static int readline(lua_State *lua)
{
  gzfile *gzf = lua_touserdata(lua, lua_upvalueindex(1));
  if (!gzf->fh) {return 0;}
  int max_bytes = lua_tointeger(lua, lua_upvalueindex(2));

  char *s         = NULL;
  size_t bytes    = 0;
  if (!gzf->pbuf) {
    gzf->pbuf = &gzf->buf;
    luaL_buffinit(lua, gzf->pbuf);
  }
  char *buf = luaL_prepbuffer(&gzf->buf);
  while ((s = gzgets(gzf->fh, buf, LUAL_BUFFERSIZE))) {
    size_t len = strlen(s);
    int eos = (s[len - 1] == '\n');
    size_t remaining = max_bytes - bytes;
    size_t add = len > remaining ? remaining : len;
    luaL_addsize(gzf->pbuf, add);
    bytes += add;
    if (eos) {
      luaL_pushresult(gzf->pbuf);
      gzf->pbuf = NULL;
      return 1;
    }
    buf = luaL_prepbuffer(&gzf->buf);
  }
  luaL_addsize(gzf->pbuf, 0);
  luaL_pushresult(gzf->pbuf);
  gzf->pbuf = NULL;
  return bytes ? 1 : 0;
}


static int gzfile_lines(lua_State *lua)
{
  check_gzfile(lua, 2);
  int max_bytes = luaL_optint(lua, 2, 1024 * 1024);
  luaL_argcheck(lua, max_bytes > 0, 2, "max_bytes must be > 0");
  lua_pushvalue(lua, 1);
  lua_pushinteger(lua, max_bytes);
  lua_pushcclosure(lua, readline, 2);
  return 1;
}


static int gzfile_string(lua_State *lua)
{
  luaL_argcheck(lua, lua_gettop(lua) <= 4, 0, "incorrect number of arguments");
  const char *fn    = luaL_checkstring(lua, 1);
  const char *mode  = luaL_optstring(lua, 2, "rb");
  int bsize         = luaL_optint(lua, 3, 8 * 1024);
  int max_bytes     = luaL_optint(lua, 4, 1024 * 1024);
  luaL_argcheck(lua, bsize > 0, 3, "buffer_size must be > 0");
  luaL_argcheck(lua, max_bytes > 0, 4, "max_bytes must be > 0");

  gzfile gzf;
  gzf.fh = gzopen(fn, mode);
  if (gzf.fh) {
    gzbuffer(gzf.fh, bsize);
  } else {
    return luaL_error(lua, "open failed");
  }

  int l        = 0;
  size_t bytes = 0;
  int err      = 0;
  luaL_buffinit(lua, &gzf.buf);
  char *buf = luaL_prepbuffer(&gzf.buf);
  while ((l = gzread(gzf.fh, buf, LUAL_BUFFERSIZE)) > 0) {
    luaL_addsize(&gzf.buf, l);
    bytes += l;
    if (bytes > (size_t)max_bytes) {
      luaL_pushresult(&gzf.buf);
      err = 1;
      lua_pushstring(lua, "max_bytes exceeded");
      break;
    }
    if (l < LUAL_BUFFERSIZE) { // eof
      luaL_pushresult(&gzf.buf);
      break;
    }
    buf = luaL_prepbuffer(&gzf.buf);
  }
  if (!err && l < 0) {
    if (!gzeof(gzf.fh)) {
      int en;
      err = 1;
      lua_pushstring(lua, gzerror(gzf.fh, &en));
    }
  }
  l = gzclose(gzf.fh);
  if (l && !err) {
    err = 1;
    lua_pushstring(lua, "close failed");
  }
  if (err) {
    return lua_error(lua);
  }
  if (bytes == 0) {
    luaL_addsize(&gzf.buf, 0);
    luaL_pushresult(&gzf.buf);
  }
  return 1;
}

static int gzfile_version(lua_State *lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


static const struct luaL_reg gzfilelib_f[] = {
  { "open", gzfile_open},
  { "string", gzfile_string },
  { "version", gzfile_version },
  { NULL, NULL }
};


static const struct luaL_reg gzfilelib_m[] = {
  { "close", gzfile_close },
  { "lines", gzfile_lines },
  { "__gc", gzfile_close },
  { NULL, NULL }
};


int luaopen_gzfile(lua_State *lua)
{
  luaL_newmetatable(lua, module_name);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, gzfilelib_m);
  luaL_register(lua, module_table, gzfilelib_f);
  return 1;
}
