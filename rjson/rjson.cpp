/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua RapidJSON wrapper implementation @file */

#include <rapidjson/document.h>
#include <rapidjson/encodings.h>
#include <rapidjson/error/en.h>
#include <rapidjson/memorystream.h>
#include <rapidjson/schema.h>
#include <rapidjson/stringbuffer.h>
#include <rapidjson/writer.h>
#include <set>

extern "C"
{
#include "lauxlib.h"
#include "lua.h"

int luaopen_rjson(lua_State *lua);
}

#ifdef LUA_SANDBOX
#ifdef HAVE_ZLIB
#include <zlib.h>
#endif
#include "luasandbox/heka/sandbox.h"
#include "luasandbox/heka/stream_reader.h"
#include "luasandbox/util/output_buffer.h"
#include "luasandbox_output.h"
#endif

namespace rj = rapidjson;

typedef struct rjson
{
  rapidjson::Document           *doc;
  rapidjson::Value              *val;
  char                          *insitu;
  std::set<rapidjson::Value *>  *refs;
} rjson;

typedef struct rjson_schema
{
  rj::SchemaDocument *doc;
} rjson_schema;

typedef struct rjson_object_iterator
{
  rj::Value::MemberIterator *it;
  rj::Value::MemberIterator *end;
} rjson_object_iterator;

static const char *mozsvc_rjson             = "mozsvc.rjson";
static const char *mozsvc_rjson_schema      = "mozsvc.rjson_schema";
static const char *mozsvc_rjson_object_iter = "mozsvc.rjson_object_iter";


static rj::Value* check_value(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n >= 1 && n <= 2, 0, "invalid number of arguments");
  rjson *j = static_cast<rjson *>
      (luaL_checkudata(lua, 1, mozsvc_rjson));
  rj::Value *v = static_cast<rj::Value *>(lua_touserdata(lua, 2));
  if (!v) {
    int t = lua_type(lua, 2);
    if (t == LUA_TNONE) {
      v = j->doc ? j->doc : j->val;
    } else if (t == LUA_TNIL) {
      v = NULL;
    } else {
      luaL_checktype(lua, 2, LUA_TLIGHTUSERDATA);
    }
  } else if (j->refs->find(v) == j->refs->end()) {
    luaL_error(lua, "invalid value");
  }
  return v;
}

static int schema_gc(lua_State *lua)
{
  rjson_schema *hs = static_cast<rjson_schema *>
      (luaL_checkudata(lua, 1, mozsvc_rjson_schema));
  delete(hs->doc);
  return 0;
}


static int iter_gc(lua_State *lua)
{
  rjson_object_iterator *hoi = static_cast<rjson_object_iterator *>(lua_touserdata(lua, 1));
  delete(hoi->it);
  delete(hoi->end);
  return 0;
}


static int rjson_gc(lua_State *lua)
{
  rjson *j = static_cast<rjson *>
      (luaL_checkudata(lua, 1, mozsvc_rjson));
  delete(j->refs);
  delete(j->doc);
  delete(j->val);
  free(j->insitu);
  return 0;
}


static int rjson_parse_schema(lua_State *lua)
{
  const char *json = luaL_checkstring(lua, 1);
  rjson_schema *hs = static_cast<rjson_schema *>(lua_newuserdata(lua, sizeof*hs));
  hs->doc = NULL;
  luaL_getmetatable(lua, mozsvc_rjson_schema);
  lua_setmetatable(lua, -2);

  { // allows doc to be destroyed before the longjmp
    rj::Document doc;
    if (doc.Parse(json).HasParseError()) {
      lua_pushfstring(lua, "failed to parse offset:%f %s",
                      (lua_Number)doc.GetErrorOffset(),
                      rj::GetParseError_En(doc.GetParseError()));
    } else {
      hs->doc = new rj::SchemaDocument(doc);
      if (!hs->doc) {
        lua_pushstring(lua, "memory allocation failed");
      }
    }
  }
  if (!hs->doc) return lua_error(lua);
  return 1;
}


static int rjson_parse(lua_State *lua)
{
  const char *json = luaL_checkstring(lua, 1);
  bool validate = false;
  int t = lua_type(lua, 2);
  if (t == LUA_TNONE || t == LUA_TNIL || LUA_TBOOLEAN) {
    validate = lua_toboolean(lua, 2);
  } else {
    luaL_typerror(lua, 2, "boolean");
  }
  rjson *j = static_cast<rjson *>(lua_newuserdata(lua, sizeof*j));
  j->doc = new rj::Document;
  j->val = NULL;
  j->insitu = NULL;
  j->refs = new std::set<rj::Value *>;
  luaL_getmetatable(lua, mozsvc_rjson);
  lua_setmetatable(lua, -2);

  if (!j->doc || !j->refs) {
    lua_pushstring(lua, "memory allocation failed");
    return lua_error(lua);
  } else {
    if (validate) {
      if (j->doc->Parse<rj::kParseValidateEncodingFlag>(json).HasParseError()) {
        lua_pushfstring(lua, "failed to parse offset:%f %s",
                        (lua_Number)j->doc->GetErrorOffset(),
                        rj::GetParseError_En(j->doc->GetParseError()));
        return lua_error(lua);
      }
    } else {
      if (j->doc->Parse(json).HasParseError()) {
        lua_pushfstring(lua, "failed to parse offset:%f %s",
                        (lua_Number)j->doc->GetErrorOffset(),
                        rj::GetParseError_En(j->doc->GetParseError()));
        return lua_error(lua);
      }
    }
  }
  j->refs->insert(j->doc);
  return 1;
}


static int rjson_validate(lua_State *lua)
{
  rjson *j = static_cast<rjson *>
      (luaL_checkudata(lua, 1, mozsvc_rjson));
  rjson_schema *hs = static_cast<rjson_schema *>
      (luaL_checkudata(lua, 2, mozsvc_rjson_schema));

  rj::SchemaValidator validator(*hs->doc);
  rj::Value *v = j->doc ? j->doc : j->val;
  if (!v->Accept(validator)) {
    lua_pushboolean(lua, false);
    luaL_Buffer b;
    luaL_buffinit(lua, &b);
    rj::StringBuffer sb;
    validator.GetInvalidSchemaPointer().StringifyUriFragment(sb);
    luaL_addstring(&b, "SchemaURI: ");
    luaL_addstring(&b, sb.GetString());
    luaL_addstring(&b, " Keyword: ");
    luaL_addstring(&b, validator.GetInvalidSchemaKeyword());
    sb.Clear();
    validator.GetInvalidDocumentPointer().StringifyUriFragment(sb);
    luaL_addstring(&b, " DocumentURI: ");
    luaL_addstring(&b, sb.GetString());
    luaL_pushresult(&b);
  }
  return 2; // ok, err
}


static int rjson_find(lua_State *lua)
{
  rjson *j = static_cast<rjson *>
      (luaL_checkudata(lua, 1, mozsvc_rjson));

  int start = 3;
  rj::Value *v = static_cast<rj::Value *>(lua_touserdata(lua, 2));
  if (!v) {
    v = j->doc ? j->doc : j->val;
    start = 2;
  } else if (j->refs->find(v) == j->refs->end()) {
    return luaL_error(lua, "invalid value");
  }

  int n = lua_gettop(lua);
  for (int i = start; i <= n; ++i) {
    switch (lua_type(lua, i)) {
    case LUA_TSTRING:
      {
        if (!v->IsObject()) {
          lua_pushnil(lua);
          return 1;
        }
        rj::Value::MemberIterator itr = v->FindMember(lua_tostring(lua, i));
        if (itr == v->MemberEnd()) {
          lua_pushnil(lua);
          return 1;
        }
        v = &itr->value;
      }
      break;
    case LUA_TNUMBER:
      {
        if (!v->IsArray()) {
          lua_pushnil(lua);
          return 1;
        }
        rj::SizeType idx = static_cast<rj::SizeType>(lua_tonumber(lua, i));
        if (idx >= v->Size()) {
          lua_pushnil(lua);
          return 1;
        }
        v = &(*v)[idx];
      }
      break;
    default:
      lua_pushnil(lua);
      return 1;
    }
  }
  j->refs->insert(v);
  lua_pushlightuserdata(lua, v);
  return 1;
}


static int rjson_type(lua_State *lua)
{
  rj::Value *v = check_value(lua);
  if (!v) {
    lua_pushnil(lua);
    return 1;
  }

  switch (v->GetType()) {
  case rj::kStringType:
    lua_pushstring(lua, "string");
    break;
  case rj::kNumberType:
    lua_pushstring(lua, "number");
    break;
  case rj::kFalseType:
  case rj::kTrueType:
    lua_pushstring(lua, "boolean");
    break;
  case rj::kObjectType:
    lua_pushstring(lua, "object");
    break;
  case rj::kArrayType:
    lua_pushstring(lua, "array");
    break;
  case rj::kNullType:
    lua_pushstring(lua, "null");
    break;
  }
  return 1;
}


static int rjson_size(lua_State *lua)
{
  rj::Value *v = check_value(lua);
  if (!v) {
    lua_pushnil(lua);
    return 1;
  }

  switch (v->GetType()) {
  case rj::kStringType:
    lua_pushnumber(lua, (lua_Number)v->GetStringLength());
    break;
  case rj::kNumberType:
    return luaL_error(lua, "attempt to get length of a number");
  case rj::kFalseType:
  case rj::kTrueType:
    return luaL_error(lua, "attempt to get length of a boolean");
  case rj::kObjectType:
    lua_pushnumber(lua, (lua_Number)v->MemberCount());
    break;
  case rj::kArrayType:
    lua_pushnumber(lua, (lua_Number)v->Size());
    break;
  case rj::kNullType:
    return luaL_error(lua, "attempt to get length of a NULL");
  }
  return 1;
}


static int rjson_object_iter(lua_State *lua)
{
  rjson_object_iterator *hoi = static_cast<rjson_object_iterator *>
      (lua_touserdata(lua, lua_upvalueindex(1)));
  rj::Value *v = (rj::Value *)lua_touserdata(lua, lua_upvalueindex(2));
  rjson *j = (rjson *)lua_touserdata(lua, lua_upvalueindex(3));

  if (j->refs->find(v) == j->refs->end()) {
    return luaL_error(lua, "iterator has been invalidated");
  }

  if (*hoi->it != *hoi->end) {
    rj::Value *next = &(*hoi->it)->value;
    j->refs->insert(next);
    lua_pushlstring(lua, (*hoi->it)->name.GetString(),
                    (size_t)(*hoi->it)->name.GetStringLength());
    lua_pushlightuserdata(lua, next);
    ++*hoi->it;
  } else {
    lua_pushnil(lua);
    lua_pushnil(lua);
  }
  return 2;
}


static int rjson_array_iter(lua_State *lua)
{
  rj::SizeType it = (rj::SizeType)lua_tonumber(lua, lua_upvalueindex(1));
  rj::SizeType end = (rj::SizeType)lua_tonumber(lua, lua_upvalueindex(2));
  rj::Value *v = (rj::Value *)lua_touserdata(lua, lua_upvalueindex(3));
  rjson *j = (rjson *)lua_touserdata(lua, lua_upvalueindex(4));

  if (j->refs->find(v) == j->refs->end()) {
    return luaL_error(lua, "iterator has been invalidated");
  }

  if (it != end) {
    rj::Value *next = &(*v)[it];
    j->refs->insert(next);
    lua_pushnumber(lua, (lua_Number)it);
    lua_pushlightuserdata(lua, next);

    ++it;
    lua_pushnumber(lua, (lua_Number)it);
    lua_replace(lua, lua_upvalueindex(1));
  } else {
    lua_pushnil(lua);
    lua_pushnil(lua);
  }
  return 2;
}


static int rjson_value(lua_State *lua)
{
  rj::Value *v = check_value(lua);
  if (!v) {
    lua_pushnil(lua);
    return 1;
  }

  switch (v->GetType()) {
  case rj::kStringType:
    lua_pushlstring(lua, v->GetString(), (size_t)v->GetStringLength());
    break;
  case rj::kNumberType:
    lua_pushnumber(lua, (lua_Number)v->GetDouble());
    break;
  case rj::kFalseType:
  case rj::kTrueType:
    lua_pushboolean(lua, v->GetBool());
    break;
  case rj::kObjectType:
    return luaL_error(lua, "value() not allowed on an object");
    break;
  case rj::kArrayType:
    return luaL_error(lua, "value() not allowed on an array");
    break;
  default:
    lua_pushnil(lua);
    break;
  }
  return 1;
}


static int rjson_iter(lua_State *lua)
{
  rj::Value *v = check_value(lua);
  if (!v) {
    lua_pushnil(lua);
    return 1;
  }

  switch (v->GetType()) {
  case rj::kObjectType:
    {
      rjson_object_iterator *hoi = static_cast<rjson_object_iterator *>
          (lua_newuserdata(lua, sizeof*hoi));
      hoi->it = new rj::Value::MemberIterator;
      hoi->end = new rj::Value::MemberIterator;
      luaL_getmetatable(lua, mozsvc_rjson_object_iter);
      lua_setmetatable(lua, -2);
      if (!hoi->it || !hoi->end) {
        return luaL_error(lua, "memory allocation failure");
      }
      *hoi->it = v->MemberBegin();
      *hoi->end = v->MemberEnd();
      lua_pushlightuserdata(lua, (void *)v);
      lua_pushvalue(lua, 1);
      lua_pushcclosure(lua, rjson_object_iter, 3);
    }
    break;
  case rj::kArrayType:
    {
      lua_pushnumber(lua, 0);
      lua_pushnumber(lua, (lua_Number)v->Size());
      lua_pushlightuserdata(lua, (void *)v);
      lua_pushvalue(lua, 1);
      lua_pushcclosure(lua, rjson_array_iter, 4);
    }
    break;
  default:
    return luaL_error(lua, "iter() not allowed on a primitive type");
    break;
  }
  return 1;
}


static int rjson_remove(lua_State *lua)
{
  rjson_find(lua);
  rj::Value *v = static_cast<rj::Value *>(lua_touserdata(lua, -1));
  if (!v) {
    lua_pushnil(lua);
    return 1;
  }

  rjson *j = static_cast<rjson *>
      (luaL_checkudata(lua, 1, mozsvc_rjson));

  rjson *nv = static_cast<rjson *>(lua_newuserdata(lua, sizeof*nv));
  nv->doc = NULL;
  nv->val = new rj::Value;
  nv->insitu = NULL;
  nv->refs = new std::set<rj::Value *>;
  luaL_getmetatable(lua, mozsvc_rjson);
  lua_setmetatable(lua, -2);

  if (!nv->val || !nv->refs) {
    lua_pushstring(lua, "memory allocation failed");
    return lua_error(lua);
  }

  *nv->val = *v; // move the value out replacing the original with NULL
  j->refs->erase(v);
  nv->refs->insert(nv->val);
  return 1;
}


#ifdef LUA_SANDBOX
#ifdef HAVE_ZLIB
static char* ungzip(const char *s, size_t s_len, size_t max_len, size_t *r_len)
{
  if (!s || (max_len && s_len > max_len)) {
    return NULL;
  }
  size_t buf_len = 2 * s_len;
  if (max_len && buf_len > max_len) {
    buf_len = max_len;
  }
  unsigned char *buf = static_cast<unsigned char *>(malloc(buf_len));
  if (!buf) {
    return NULL;
  }

  z_stream strm;
  strm.zalloc     = Z_NULL;
  strm.zfree      = Z_NULL;
  strm.opaque     = Z_NULL;
  strm.avail_in   = s_len;
  strm.next_in    = (unsigned char *)s;
  strm.avail_out  = buf_len;
  strm.next_out   = buf;

  int ret = inflateInit2(&strm, 16 + MAX_WBITS);
  if (ret != Z_OK) {
    free(buf);
    return NULL;
  }

  do {
    if (ret == Z_BUF_ERROR) {
      if (max_len && buf_len == max_len) {
        ret = Z_MEM_ERROR;
        break;
      }
      buf_len *= 2;
      if (max_len && buf_len > max_len) {
        buf_len = max_len;
      }
      unsigned char *tmp = static_cast<unsigned char *>(realloc(buf, buf_len));
      if (!tmp) {
        ret = Z_MEM_ERROR;
        break;
      } else {
        buf = tmp;
        strm.avail_out = buf_len - strm.total_out;
        strm.next_out = buf + strm.total_out;
      }
    }
    ret = inflate(&strm, Z_FINISH);
  } while (ret == Z_BUF_ERROR && strm.avail_in > 0);

  inflateEnd(&strm);
  if (ret != Z_STREAM_END) {
    free(buf);
    return NULL;
  }
  if (r_len) *r_len = strm.total_out;
  return (char *)buf;
}
#endif

class OutputBufferWrapper {
public:
  typedef char Ch;
  OutputBufferWrapper(lsb_output_buffer *ob) : ob_(ob), err_(NULL) { }
#if _BullseyeCoverage
#pragma BullseyeCoverage off
#endif
  Ch Peek() const { assert(false);return '\0'; }
  Ch Take() { assert(false);return '\0'; }
  size_t Tell() const { return 0; }
  Ch* PutBegin() { assert(false);return 0; }
  size_t PutEnd(Ch *) { assert(false);return 0; }
#if _BullseyeCoverage
#pragma BullseyeCoverage on
#endif
  void Put(Ch c)
  {
    const char *err = lsb_outputc(ob_, c);
    if (err) err_ = err;
  }
  void Flush() { return; }
  const char* GetError() { return err_; }
private:
  OutputBufferWrapper(const OutputBufferWrapper&);
  OutputBufferWrapper& operator=(const OutputBufferWrapper&);
  lsb_output_buffer *ob_;
  const char *err_;
};

static int rjson_make_field(lua_State *lua)
{
  rj::Value *v = check_value(lua);
  if (!v) {
    lua_pushnil(lua);
    return 1;
  }

  lua_createtable(lua, 0, 2);
  lua_pushlightuserdata(lua, (void *)v);
  lua_setfield(lua, -2, "value");
  lua_pushvalue(lua, 1);
  lua_setfield(lua, -2, "userdata");
  return 1;
}


static int output_rjson(lua_State *lua)
{
  lsb_output_buffer *ob = static_cast<lsb_output_buffer *>
      (lua_touserdata(lua, -1));
  rjson *j = static_cast<rjson *>(lua_touserdata(lua, -2));
  rj::Value *v = static_cast<rj::Value *>(lua_touserdata(lua, -3));
  if (!(ob && j)) {
    return 1;
  }
  if (!v) {
    v = j->doc ? j->doc : j->val;
  } else {
    if (j->refs->find(v) == j->refs->end()) {
      return 1;
    }
  }
  OutputBufferWrapper obw(ob);
  rapidjson::Writer<OutputBufferWrapper> writer(obw);
  v->Accept(writer);
  return obw.GetError() == NULL ? 0 : 1;
}


static lsb_const_string read_message(lua_State *lua, int idx,
                                     const lsb_heka_message *m)
{
  lsb_const_string ret = { NULL, 0 };
  size_t field_len;
  const char *field = luaL_checklstring(lua, idx, &field_len);
  int fi = (int)luaL_optinteger(lua, idx + 1, 0);
  luaL_argcheck(lua, fi >= 0, idx + 1, "field index must be >= 0");
  int ai = (int)luaL_optinteger(lua, idx + 2, 0);
  luaL_argcheck(lua, ai >= 0, idx + 2, "array index must be >= 0");

  if (strcmp(field, LSB_PAYLOAD) == 0) {
    if (m->payload.s) ret = m->payload;
  } else {
    if (field_len >= 8
        && memcmp(field, LSB_FIELDS "[", 7) == 0
        && field[field_len - 1] == ']') {
      lsb_read_value v;
      lsb_const_string f = { field + 7, field_len - 8 };
      lsb_read_heka_field(m, &f, fi, ai, &v);
      if (v.type == LSB_READ_STRING) ret = v.u.s;
    }
  }
  return ret;
}


static int rjson_parse_message(lua_State *lua)
{
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_HEKA_THIS_PTR);
  lsb_heka_sandbox *hsb =
      static_cast<lsb_heka_sandbox *>(lua_touserdata(lua, -1));
  lua_pop(lua, 1); // remove this ptr
  if (!hsb) {
    return luaL_error(lua, "parse_message() invalid " LSB_HEKA_THIS_PTR);
  }
  int n = lua_gettop(lua);
  int idx = 1;

  const lsb_heka_message *msg = NULL;
  if (lsb_heka_get_type(hsb) == 'i') {
    luaL_argcheck(lua, n >= 2 && n <= 5, 0, "invalid number of arguments");
    heka_stream_reader *hsr = static_cast<heka_stream_reader *>
        (luaL_checkudata(lua, 1, LSB_HEKA_STREAM_READER));
    msg = &hsr->msg;
    idx = 2;
  } else {
    luaL_argcheck(lua, n >= 1 && n <= 4, 0, "invalid number of arguments");
    const lsb_heka_message *hm = lsb_heka_get_message(hsb);
    if (!hm || !hm->raw.s) {
      return luaL_error(lua, "parse_message() no active message");
    }
    msg = hm;
  }
  bool validate = false;
  int t = lua_type(lua, idx + 3);
  if (t == LUA_TNONE || t == LUA_TNIL || LUA_TBOOLEAN) {
    validate = lua_toboolean(lua, idx + 3);
  } else {
    luaL_typerror(lua, idx + 3, "boolean");
  }

  lsb_const_string json = read_message(lua, idx, msg);
  if (!json.s) return luaL_error(lua, "field not found");

  char *inflated = NULL;
#ifdef HAVE_ZLIB
  // automatically handle gzipped strings (optimization for Mozilla telemetry
  // messages)
  if (json.len > 2) {
    if (json.s[0] == 0x1f && (unsigned char)json.s[1] == 0x8b) {
      size_t mms = (size_t)lua_tointeger(lua, lua_upvalueindex(1));
      inflated = ungzip(json.s, json.len, mms, NULL);
      if (!inflated) return luaL_error(lua, "ungzip failed");
    }
  }
#endif

  rjson *j = static_cast<rjson *>(lua_newuserdata(lua, sizeof*j));
  j->doc = new rj::Document;
  j->val = NULL;
  j->insitu = inflated;
  j->refs =  new std::set<rj::Value *>;
  luaL_getmetatable(lua, mozsvc_rjson);
  lua_setmetatable(lua, -2);

  if (!j->doc || !j->refs) {
    lua_pushstring(lua, "memory allocation failed");
    return lua_error(lua);
  }

  bool err = false;
  if (validate) {
    if (j->insitu) {
      if (j->doc->ParseInsitu<rj::kParseValidateEncodingFlag | rj::kParseStopWhenDoneFlag>(j->insitu).HasParseError()) {
        err = true;
        lua_pushfstring(lua, "failed to parse offset:%f %s",
                        (lua_Number)j->doc->GetErrorOffset(),
                        rj::GetParseError_En(j->doc->GetParseError()));
      }
    } else {
      rj::MemoryStream ms(json.s, json.len);
      if (j->doc->ParseStream<rj::kParseValidateEncodingFlag, rj::UTF8<> >(ms).HasParseError()) {
        err = true;
        lua_pushfstring(lua, "failed to parse offset:%f %s",
                        (lua_Number)j->doc->GetErrorOffset(),
                        rj::GetParseError_En(j->doc->GetParseError()));
      }
    }
  } else {
    if (j->insitu) {
      if (j->doc->ParseInsitu<rj::kParseStopWhenDoneFlag>(j->insitu).HasParseError()) {
        err = true;
        lua_pushfstring(lua, "failed to parse offset:%f %s",
                        (lua_Number)j->doc->GetErrorOffset(),
                        rj::GetParseError_En(j->doc->GetParseError()));
      }
    } else {
      rj::MemoryStream ms(json.s, json.len);
      if (j->doc->ParseStream<0, rj::UTF8<> >(ms).HasParseError()) {
        err = true;
        lua_pushfstring(lua, "failed to parse offset:%f %s",
                        (lua_Number)j->doc->GetErrorOffset(),
                        rj::GetParseError_En(j->doc->GetParseError()));
      }
    }
  }

  if (err) return lua_error(lua);
  j->refs->insert(j->doc);
  return 1;
}
#endif

static const struct luaL_reg schemalib_m[] =
{
  { "__gc", schema_gc },
  { NULL, NULL }
};


static const struct luaL_reg iterlib_m[] =
{
  { "__gc", iter_gc },
  { NULL, NULL }
};


static int rjson_version(lua_State *lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


static const struct luaL_reg rjsonlib_f[] =
{
  { "parse_schema", rjson_parse_schema },
  { "parse", rjson_parse },
  { "version", rjson_version },
  { NULL, NULL }
};


static const struct luaL_reg rjsonlib_m[] =
{
  { "validate", rjson_validate },
  { "type", rjson_type },
  { "find", rjson_find },
  { "value", rjson_value },
  { "iter", rjson_iter },
  { "size", rjson_size },
  { "remove", rjson_remove },
  { "__gc", rjson_gc },
  { NULL, NULL }
};

int luaopen_rjson(lua_State *lua)
{
#ifdef LUA_SANDBOX
  lua_newtable(lua);
  lsb_add_output_function(lua, output_rjson);
  lua_replace(lua, LUA_ENVIRONINDEX);
#endif

  luaL_newmetatable(lua, mozsvc_rjson_schema);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, schemalib_m);
  lua_pop(lua, 1);

  luaL_newmetatable(lua, mozsvc_rjson_object_iter);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, iterlib_m);
  lua_pop(lua, 1);

  luaL_newmetatable(lua, mozsvc_rjson);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, rjsonlib_m);
  luaL_register(lua, "rjson", rjsonlib_f);

#ifdef LUA_SANDBOX
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_HEKA_THIS_PTR);
  lsb_heka_sandbox *hsb = static_cast<lsb_heka_sandbox *>(lua_touserdata(lua, -1));
  lua_pop(lua, 1); // remove this ptr
  if (hsb) {
    lua_pushcfunction(lua, rjson_make_field);
    lua_setfield(lua, -3, "make_field");

    // special case parse_message and give it easy access to the sandbox
    // configuration value it requires
    lua_getfield(lua, LUA_REGISTRYINDEX, LSB_CONFIG_TABLE);
    if (lua_type(lua, -1) != LUA_TTABLE) {
      return luaL_error(lua, LSB_CONFIG_TABLE " is missing");
    }
    lua_getfield(lua, -1, LSB_HEKA_MAX_MESSAGE_SIZE);
    lua_pushcclosure(lua, rjson_parse_message, 1);
    lua_setfield(lua, -3, "parse_message");
    lua_pop(lua, 1); // remove LSB_CONFIG_TABLE
  }
#endif
  return 1;
}
