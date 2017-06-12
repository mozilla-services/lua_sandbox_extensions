/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief cjose wrapper implementation @file */

#include <string.h>
#include <cjose/cjose.h>

#include "lauxlib.h"
#include "lua.h"

#ifdef LUA_SANDBOX
#include <luasandbox_output.h>
#include <luasandbox/heka/sandbox.h>
#endif

#ifdef HAVE_ZLIB
#include <zlib.h>

typedef struct zlib_buffer
{
  unsigned char *buf;
  size_t         len;
  size_t         capacity;
} zlib_buffer;


static bool
bounded_inflate(const char *s, size_t s_len, size_t max_len, zlib_buffer *b)
{
  if (!s || (max_len && s_len > max_len)) {
    return false;
  }

  size_t len = s_len * 2;
  if (max_len && len > max_len) {
    len = max_len;
  }
  b->len = 0;
  if (b->capacity < len) {
    unsigned char *tmp = realloc(b->buf, len);
    if (tmp) {
      b->buf = tmp;
      b->capacity = len;
    } else {
      return false;
    }
  }

  z_stream strm;
  strm.zalloc     = Z_NULL;
  strm.zfree      = Z_NULL;
  strm.opaque     = Z_NULL;
  strm.avail_in   = s_len;
  strm.next_in    = (unsigned char *)s;
  strm.avail_out  = b->capacity;
  strm.next_out   = b->buf;

  int ret = inflateInit(&strm);
  if (ret != Z_OK) {
    return false;
  }

  do {
    if (ret == Z_BUF_ERROR) {
      if (max_len && b->capacity == max_len) {
        ret = Z_MEM_ERROR;
        break;
      }
      len = b->capacity * 2;
      if (max_len && len > max_len) {
        len = max_len;
      }
      unsigned char *tmp = realloc(b->buf, len);
      if (tmp) {
        b->buf = tmp;
        b->capacity = len;
        strm.avail_out = b->capacity - strm.total_out;
        strm.next_out = b->buf + strm.total_out;
      } else {
        ret = Z_MEM_ERROR;
        break;
      }
    }
    ret = inflate(&strm, Z_FINISH);
  } while (ret == Z_BUF_ERROR && strm.avail_in > 0);

  inflateEnd(&strm);
  if (ret != Z_STREAM_END) {
    return false;
  }
  b->len = strm.total_out;
  return true;
}
#endif

static const char *g_hdr_mt = "mozsvc.jose.hdr";
static const char *g_jwk_mt = "mozsvc.jose.jwk";
static const char *g_jws_mt = "mozsvc.jose.jws";
static const char *g_jwe_mt = "mozsvc.jose.jwe";


typedef struct hdr
{
  cjose_header_t *p;
} hdr;

typedef struct jwk
{
  cjose_jwk_t *p;
} jwk;

typedef struct jws
{
  cjose_jws_t *p;
} jws;

typedef struct jwe
{
  cjose_jwe_t *p;
} jwe;


static hdr* check_hdr(lua_State *lua, int args)
{
  hdr *ud = luaL_checkudata(lua, 1, g_hdr_mt);
  luaL_argcheck(lua, args == lua_gettop(lua), 0,
                "incorrect number of arguments");
  return ud;
}


static jwk* check_jwk(lua_State *lua, int args)
{
  jwk *ud = luaL_checkudata(lua, 1, g_jwk_mt);
  luaL_argcheck(lua, args == lua_gettop(lua), 0,
                "incorrect number of arguments");
  return ud;
}


static jws* check_jws(lua_State *lua, int args)
{
  jws *ud = luaL_checkudata(lua, 1, g_jws_mt);
  luaL_argcheck(lua, args == lua_gettop(lua), 0,
                "incorrect number of arguments");
  return ud;
}


static jwe* check_jwe(lua_State *lua, int args)
{
  jwe *ud = luaL_checkudata(lua, 1, g_jwe_mt);
  luaL_argcheck(lua, args == lua_gettop(lua), 0,
                "incorrect number of arguments");
  return ud;
}


static void cjose_error(lua_State *lua, cjose_err *err)
{
  luaL_error(lua, "file: %s line: %d function: %s message: %s", err->file,
             (int)err->line, err->function, err->message);
}


static int hdr_new(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 1, 0, "incorrect number of arguments");
  luaL_checktype(lua, 1, LUA_TTABLE);

  hdr *ud = lua_newuserdata(lua, sizeof(hdr));
  cjose_err err;
  ud->p = cjose_header_new(&err);
  if (!ud->p) cjose_error(lua, &err);
  luaL_getmetatable(lua, g_hdr_mt);
  lua_setmetatable(lua, -2);

  lua_pushnil(lua);
  while (lua_next(lua, 1) != 0) {
    if (lua_type(lua, -2) != LUA_TSTRING) {
      luaL_error(lua, "header key must be a string");
    }
    if (lua_type(lua, -1) != LUA_TSTRING) {
      luaL_error(lua, "header value must be a string");
    }
    const char *k = lua_tostring(lua, -2);
    const char *v = lua_tostring(lua, -1);
    if (!cjose_header_set(ud->p, k, v, &err)) {
      cjose_error(lua, &err);
    }
    lua_pop(lua, 1);
  }
  return 1;
}


static int jwk_import(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 1, 0, "incorrect number of arguments");
  size_t len = 0;
  const char *json = luaL_checklstring(lua, 1, &len);

  jwk *ud = lua_newuserdata(lua, sizeof(jwk));
  cjose_err err;
  ud->p = cjose_jwk_import(json, len, &err);
  if (!ud->p) cjose_error(lua, &err);
  luaL_getmetatable(lua, g_jwk_mt);
  lua_setmetatable(lua, -2);
  return 1;
}


static int jws_import(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 1, 0, "incorrect number of arguments");
  size_t len = 0;
  const char *txt = luaL_checklstring(lua, 1, &len);

  jws *ud = lua_newuserdata(lua, sizeof(jws));
  cjose_err err;
  ud->p = cjose_jws_import(txt, len, &err);
  if (!ud->p) cjose_error(lua, &err);
  luaL_getmetatable(lua, g_jws_mt);
  lua_setmetatable(lua, -2);
  return 1;
}


static int jws_sign(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 3, 0, "incorrect number of arguments");
  jwk *key = luaL_checkudata(lua, 1, g_jwk_mt);
  size_t len = 0;
  const char *txt = luaL_checklstring(lua, 2, &len);
  hdr *h = luaL_checkudata(lua, 3, g_hdr_mt);

  jws *ud = lua_newuserdata(lua, sizeof(jws));
  cjose_err err;
  ud->p = cjose_jws_sign(key->p, h->p, (const uint8_t *)txt, len, &err);
  if (!ud->p) cjose_error(lua, &err);
  luaL_getmetatable(lua, g_jws_mt);
  lua_setmetatable(lua, -2);
  return 1;
}


static int jws_export(lua_State *lua)
{
  jws *ud = check_jws(lua, 1);

  const char *ser;
  cjose_err err;
  bool rv = cjose_jws_export(ud->p, &ser, &err);
  if (!rv) cjose_error(lua, &err);
  lua_pushstring(lua, ser);
  return 1;
}


static int jws_verify(lua_State *lua)
{
  jws *ud  = check_jws(lua, 2);
  jwk *key = luaL_checkudata(lua, 2, g_jwk_mt);

  cjose_err err;
  bool rv = cjose_jws_verify(ud->p, key->p, &err);
  if (!rv) cjose_error(lua, &err);
  lua_pushboolean(lua, rv);
  return 1;
}


static int jws_plaintext(lua_State *lua)
{
  jws *ud = check_jws(lua, 1);

  uint8_t *txt;
  size_t len;
  cjose_err err;
  bool rv = cjose_jws_get_plaintext(ud->p, &txt, &len, &err);
  if (!rv) cjose_error(lua, &err);
  lua_pushlstring(lua, (const char *)txt, len);
  return 1;
}


static int jws_header(lua_State *lua)
{
  jws *ud = check_jws(lua, 1);

  hdr *h = lua_newuserdata(lua, sizeof(hdr));
  h->p = cjose_header_retain(cjose_jws_get_protected(ud->p));
  luaL_getmetatable(lua, g_hdr_mt);
  lua_setmetatable(lua, -2);
  return 1;
}


static int jwe_import(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 1, 0, "incorrect number of arguments");
  size_t len = 0;
  const char *txt = luaL_checklstring(lua, 1, &len);

  jwe *ud = lua_newuserdata(lua, sizeof(jwe));
  cjose_err err;
  ud->p = cjose_jwe_import(txt, len, &err);
  if (!ud->p) cjose_error(lua, &err);
  luaL_getmetatable(lua, g_jwe_mt);
  lua_setmetatable(lua, -2);
  return 1;
}


static int jwe_encrypt(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 3, 0, "incorrect number of arguments");
  jwk *key = luaL_checkudata(lua, 1, g_jwk_mt);
  size_t len = 0;
  const char *txt = luaL_checklstring(lua, 2, &len);
  hdr *h = luaL_checkudata(lua, 3, g_hdr_mt);

  jwe *ud = lua_newuserdata(lua, sizeof(jwe));
  cjose_err err;
  const char *zip = cjose_header_get(h->p, "zip", NULL);
  if (zip && strncmp("DEF", zip, 3) == 0) {
#ifdef HAVE_ZLIB
    uLong dlen = compressBound(len);
    Bytef *d = malloc(dlen);
    if (compress(d, &dlen, (const Bytef *)txt, (uLong)len) != Z_OK) {
      free(d);
      return luaL_error(lua, "compression failed");
    }
    ud->p = cjose_jwe_encrypt(key->p, h->p, (const uint8_t *)d, dlen, &err);
    free(d);
    if (!ud->p) cjose_error(lua, &err);
#else
    luaL_error(lua, "compression not supported");
#endif
  } else {
    ud->p = cjose_jwe_encrypt(key->p, h->p, (const uint8_t *)txt, len, &err);
    if (!ud->p) cjose_error(lua, &err);
  }
  luaL_getmetatable(lua, g_jwe_mt);
  lua_setmetatable(lua, -2);
  return 1;
}


static int jwe_export(lua_State *lua)
{
  jwe *ud = check_jwe(lua, 1);

  cjose_err err;
  char *cs = cjose_jwe_export(ud->p, &err);
  if (!cs) cjose_error(lua, &err);
  lua_pushstring(lua, cs);
  free(cs);
  return 1;
}


static int jwe_decrypt(lua_State *lua)
{
  jwe *ud = check_jwe(lua, 2);
  jwk *key = luaL_checkudata(lua, 2, g_jwk_mt);

  size_t len;
  cjose_err err;
  uint8_t *txt = cjose_jwe_decrypt(ud->p, key->p, &len, &err);
  if (!txt) cjose_error(lua, &err);
  cjose_header_t *h = cjose_jwe_get_protected(ud->p);
  const char *zip = cjose_header_get(h, "zip", NULL);
  if (zip && strncmp("DEF", zip, 3) == 0) {
#ifdef HAVE_ZLIB
    zlib_buffer b = { NULL, 0, 0 };
#ifdef LUA_SANDBOX
    size_t max_size = (size_t)lua_tointeger(lua, lua_upvalueindex(1));
#else
    size_t max_size = 0;
#endif
    if (!bounded_inflate((const char *)txt, len, max_size, &b)) {
      free(b.buf);
      free(txt);
      return luaL_error(lua, "decompression failed");
    }
    lua_pushlstring(lua, (const char *)b.buf, b.len);
    free(b.buf);
    free(txt);
#else
    free(txt);
    return luaL_error(lua, "decompression not supported");
#endif
  } else {
    lua_pushlstring(lua, (const char *)txt, len);
    free(txt);
  }
  return 1;
}


static int jwe_header(lua_State *lua)
{
  jwe *ud = check_jwe(lua, 1);

  hdr *h = lua_newuserdata(lua, sizeof(hdr));
  h->p = cjose_header_retain(cjose_jwe_get_protected(ud->p));
  luaL_getmetatable(lua, g_hdr_mt);
  lua_setmetatable(lua, -2);
  return 1;
}


static int hdr_get(lua_State *lua)
{
  hdr *ud = check_hdr(lua, 2);
  const char *key = luaL_checkstring(lua, 2);

  const char *v = cjose_header_get(ud->p, key, NULL);
  if (v) {
    lua_pushstring(lua, v);
  } else {
    lua_pushnil(lua);
  }
  return 1;
}


static int hdr_gc(lua_State *lua)
{
  hdr *ud = check_hdr(lua, 1);
  if (ud->p) {
    cjose_header_release(ud->p);
    ud->p = NULL;
  }
  return 0;
}


static int jwk_gc(lua_State *lua)
{
  jwk *ud = check_jwk(lua, 1);
  if (ud->p) {
    cjose_jwk_release(ud->p);
    ud->p = NULL;
  }
  return 0;
}


static int jws_gc(lua_State *lua)
{
  jws *ud = check_jws(lua, 1);
  if (ud->p) {
    cjose_jws_release(ud->p);
    ud->p = NULL;
  }
  return 0;
}


static int jwe_gc(lua_State *lua)
{
  jwe *ud = check_jwe(lua, 1);
  if (ud->p) {
    cjose_jwe_release(ud->p);
    ud->p = NULL;
  }
  return 0;
}


static int version(lua_State *lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


static const struct luaL_reg jose_f[] =
{
  { "version", version },
  { "header", hdr_new },
  { "jwk_import", jwk_import },
  { "jws_import", jws_import },
  { "jwe_import", jwe_import },
  { "jws_sign", jws_sign },
  { "jwe_encrypt", jwe_encrypt },
  { NULL, NULL }
};


static const struct luaL_reg hdr_m[] =
{
  { "get", hdr_get },
  { "__gc", hdr_gc },
  { NULL, NULL }
};


static const struct luaL_reg jwk_m[] =
{
  { "__gc", jwk_gc },
  { NULL, NULL }
};


static const struct luaL_reg jws_m[] =
{
  { "verify", jws_verify },
  { "export", jws_export },
  { "plaintext", jws_plaintext },
  { "header", jws_header },
  { "__gc", jws_gc },
  { NULL, NULL }
};

static const struct luaL_reg jwe_m[] =
{
  { "export", jwe_export },
  { "decrypt", jwe_decrypt },
  { "header", jwe_header },
  { "__gc", jwe_gc },
  { NULL, NULL }
};


int luaopen_jose(lua_State *lua)
{
  luaL_newmetatable(lua, g_hdr_mt);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, hdr_m);
  lua_pop(lua, 1);

  luaL_newmetatable(lua, g_jwk_mt);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, jwk_m);
  lua_pop(lua, 1);

  luaL_newmetatable(lua, g_jws_mt);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, jws_m);
  lua_pop(lua, 1);

  luaL_newmetatable(lua, g_jwe_mt);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, jwe_m);
#ifdef LUA_SANDBOX
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_HEKA_THIS_PTR);
  lsb_heka_sandbox *hsb = lua_touserdata(lua, -1);
  lua_pop(lua, 1); // remove this ptr

  // replace decrypt and give it easy access to the inflation limit
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_CONFIG_TABLE);
  if (lua_type(lua, -1) != LUA_TTABLE) {
    return luaL_error(lua, LSB_CONFIG_TABLE " is missing");
  }
  if (hsb) {
    lua_getfield(lua, -1, LSB_HEKA_MAX_MESSAGE_SIZE);
  } else {
    lua_getfield(lua, -1, LSB_OUTPUT_LIMIT);
  }
  lua_pushcclosure(lua, jwe_decrypt, 1);
  lua_setfield(lua, -3, "decrypt");
  lua_pop(lua, 1); // remove LSB_CONFIG_TABLE
#endif
  lua_pop(lua, 1);

  luaL_register(lua, "jose", jose_f);
  return 1;
}
