/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua parquet-cpp wrapper implementation @file */

#include <iostream>
#include <memory>
#include <string>
#include <vector>

#include <parquet/column/writer.h>
#include <parquet/file/writer.h>
#include <parquet/types.h>
#include <parquet/util/output.h>

extern "C"
{
#include "lauxlib.h"
#include "lua.h"

int luaopen_parquet(lua_State *lua);
}

#ifdef LUA_SANDBOX
#include <luasandbox/heka/sandbox.h>
#include <luasandbox/util/heka_message.h>
#include <luasandbox/util/protobuf.h>
#endif

using namespace std;

namespace pq = parquet;

static const char *mozsvc_parquet_schema    = "mozsvc.parquet_schema";
static const char *mozsvc_parquet_group     = "mozsvc.parquet_group";
static const char *mozsvc_parquet_writer    = "mozsvc.parquet_writer";
static const char *repetitions[] = { "required", "optional", "repeated", NULL };
static const char *data_types[] = { "boolean", "int32", "int64", "int96",
  "float", "double", "binary", "fixed_len_byte_array", NULL };
static const char *logical_types[] = { "none", "utf8", "map", "map_key_value",
  "list", "enum", "decimal", "date", "time_millis", "time_micros",
  "timestamp_millis", "timestamp_micros", "uint_8", "uint_16", "uint_32",
  "uint_64", "int_8", "int_16", "int_32", "int_64", "json", "bson", "interval",
  "tuple", NULL };

typedef struct pq_node pg_node;

typedef struct pq_group
{
  // these values must must be stored outside of the group node since it cannot
  // be constructed until the end
  pq::Repetition::type  rt;
  pq::LogicalType::type lt;
  vector<pq_node *>     fields;

  pq_group(pq::Repetition::type  rt, pq::LogicalType::type lt) : rt(rt), lt(lt)
  { }
} pq_group;


struct pq_node {
  string                  name; // original schema name
  pq::schema::Node::type  nt;
  int                     ref_cnt;
  pq::schema::NodePtr     node;
  int16_t                 rl;
  int16_t                 dl;
  bool                    hive_compatible;
  union {
    pq_group  *group;
    size_t    column; // just store the index; each writer will have its own
                      // column data storage
  };

  pq_node(const string &name, pq::schema::Node::type nt, bool hive_compatible) :
      name(name), nt(nt), ref_cnt(1), node(nullptr), rl(0), dl(0),
      hive_compatible(hive_compatible), group(nullptr) { }
};


typedef struct pq_column
{
  pq_node                                     *n;
  shared_ptr<parquet::schema::PrimitiveNode>  pn;

  size_t          num_values;
  vector<int16_t> *dlevels;
  vector<int16_t> *rlevels;

  vector<uint8_t> *bytes; // fixed length byte array/byte array/bool usage
  union {
    vector<int32_t>       *i32;
    vector<int64_t>       *i64;
    vector<pq::Int96>     *i96;
    vector<float>         *f;
    vector<double>        *d;
    vector<pq::ByteArray> *ba;
    vector<pq::FLBA>      *flba;
  };

  // rollback state for a dissect_record failure
  size_t rec_num;
  size_t rec_r_items;
  size_t rec_d_items;
  size_t rec_v_items;

  pq_column(pq_node *n) : n(n),
      pn(static_pointer_cast<pq::schema::PrimitiveNode>(n->node)),
      num_values(0), dlevels(nullptr), rlevels(nullptr), bytes(nullptr),
      i32(nullptr), rec_num(0), rec_r_items(0), rec_d_items(0), rec_v_items(0)
  { }
} pq_column;


typedef struct pq_node_ud {
  pq_node *n;
} pq_node_ud;


typedef struct pq_writer
{
  pq_node *node;
  vector<pq_column *> columns;
  unique_ptr<pq::ParquetFileWriter> writer;
  size_t num_records;

  ~pq_writer();
} pq_writer;


typedef struct pq_writer_ud
{
  pq_writer *w;
} pq_writer_ud;


static string hive_name(const string &name)
{
  vector<char> v;
  size_t len = name.size();
  bool upper = true;
  for (size_t i = 0; i < len; ++i) {
    if (isupper(name[i])) {
      if (!upper) {
        v.push_back('_');
      }
      upper = true;
      v.push_back(tolower(name[i]));
    } else {
      if (isalnum(name[i])) {
        upper = false;
        v.push_back(name[i]);
      } else {
        upper = true;
        v.push_back('_');
      }
    }
  }
  return string(v.begin(), v.end());
}


static pq_node* new_group(lua_State *lua, const char *name,
                          pq::Repetition::type rt, pq::LogicalType::type lt,
                          const char *metatable, bool hive_compatible)
{
  pq_node_ud *ud = static_cast<pq_node_ud *>(lua_newuserdata(lua, sizeof*ud));
  ud->n = NULL;
  luaL_getmetatable(lua, metatable);
  lua_setmetatable(lua, -2);

  ud->n = new pq_node(name, pq::schema::Node::GROUP, hive_compatible);
  ud->n->group = new pq_group(rt, lt);
  return ud->n;
}


static int pq_new_schema(lua_State *lua)
{
  size_t len;
  const char *name = luaL_checklstring(lua, 1, &len);
  luaL_argcheck(lua, len > 0, 1, "name cannot be empty");
  bool hive_compatible = false;
  int t = lua_type(lua, 2);
  switch (t) {
  case LUA_TNONE:
  case LUA_TNIL:
    break;
  case LUA_TBOOLEAN:
    hive_compatible = lua_toboolean(lua, 2);
    break;
  default:
    return luaL_typerror(lua, 2, "boolean, nil or none");
  }

  bool err = false;
  try {
    new_group(lua, name, pq::Repetition::REQUIRED, pq::LogicalType::NONE,
              mozsvc_parquet_schema, hive_compatible);
  } catch (exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown schema creation error");
    err = true;
  }
  return err ? lua_error(lua) : 1;
}


static void free_children(pq_node *n)
{
  if (n->nt == pq::schema::Node::GROUP) {
    if (!n->group) {return;}

    size_t len = n->group->fields.size();
    for (size_t i = 0; i < len; ++i) {
      free_children(n->group->fields[i]);
    }
    delete n->group;
  }
  delete n;
}


pq_writer::~pq_writer()
{
  size_t len = columns.size();
  for (size_t i = 0; i < len; ++i) {
    pq_column *c = columns[i];
    switch (c->pn->physical_type()) {
    case pq::Type::INT32:
      delete c->i32;
      break;
    case pq::Type::INT64:
      delete c->i64;
      break;
    case pq::Type::INT96:
      delete c->i96;
      break;
    case pq::Type::FLOAT:
      delete c->f;
      break;
    case pq::Type::DOUBLE:
      delete c->d;
      break;
    case pq::Type::BYTE_ARRAY:
      delete c->ba;
      break;
    case pq::Type::FIXED_LEN_BYTE_ARRAY:
      delete c->flba;
      break;
    case pq::Type::BOOLEAN:
      // uses bytes
      break;
    }
    delete c->bytes;
    delete c->rlevels;
    delete c->dlevels;
    delete c;
  }
}


static int pq_schema_gc(lua_State *lua)
{
  pq_node_ud *ud = static_cast<pq_node_ud *>
      (luaL_checkudata(lua, 1, mozsvc_parquet_schema));
  if (!ud->n) {return 0;}

  bool err = false;
  if (--ud->n->ref_cnt == 0) {
    try {
      free_children(ud->n);
    } catch (exception &e) {
      lua_pushstring(lua, e.what());
      err = true;
    } catch (...) {
      lua_pushstring(lua, "unknown schema gc error");
      err = true;
    }
  }
  return err ? lua_error(lua) : 0;
}


static pq_node_ud* verify_group(lua_State *lua, int idx)
{
  void *p = lua_touserdata(lua, idx);
  if (p) {
    if (lua_getmetatable(lua, idx)) {
      lua_getfield(lua, LUA_REGISTRYINDEX, mozsvc_parquet_group);
      if (lua_rawequal(lua, -1, -2)) {
        lua_pop(lua, 2);
        pq_node_ud *ud = static_cast<pq_node_ud *>(p);
        if (ud->n->node) {
          luaL_error(lua, "cannot modify a finalized schema");
        }
        return ud;
      }

      lua_pop(lua, 1);
      lua_getfield(lua, LUA_REGISTRYINDEX, mozsvc_parquet_schema);
      if (lua_rawequal(lua, -1, -2)) {
        lua_pop(lua, 2);
        pq_node_ud *ud = static_cast<pq_node_ud *>(p);
        if (ud->n->node) {
          luaL_error(lua, "cannot modify a finalized schema");
        }
        return ud;
      }
    }
  }
  luaL_typerror(lua, idx, "schema/group");
  return NULL;
}


static int pq_new_group(lua_State *lua)
{
  pq_node_ud *ud = verify_group(lua, 1);
  size_t len;
  const char *name = luaL_checklstring(lua, 2, &len);
  luaL_argcheck(lua, len > 0, 2, "name cannot be empty");

  pq::Repetition::type rt = static_cast<pq::Repetition::type>(
      luaL_checkoption(lua, 3, NULL, repetitions));

  pq::LogicalType::type lt = static_cast<pq::LogicalType::type>(
      luaL_checkoption(lua, 4, logical_types[0], logical_types));

  if (lt == pq::LogicalType::MAP_KEY_VALUE) {
    luaL_argerror(lua, 4, "MAP_KEY_VALUE is deprecated");
  }

  bool err = false;
  try {
    ud->n->group->fields.push_back(new_group(lua, name, rt, lt,
                                             mozsvc_parquet_group,
                                             ud->n->hive_compatible));
  } catch (exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown group creation error");
    err = true;
  }
  return err ? lua_error(lua) : 1;
}


static int pq_new_column(lua_State *lua)
{
  pq_node_ud *ud = verify_group(lua, 1);
  size_t len;
  const char *name = luaL_checklstring(lua, 2, &len);
  luaL_argcheck(lua, len > 0, 2, "name cannot be empty");

  pq::Repetition::type rt = static_cast<pq::Repetition::type>(
      luaL_checkoption(lua, 3, NULL, repetitions));

  pq::Type::type dt = static_cast<pq::Type::type>(
      luaL_checkoption(lua, 4, NULL, data_types));

  pq::LogicalType::type lt = static_cast<pq::LogicalType::type>(
      luaL_checkoption(lua, 5, logical_types[0], logical_types));

  int fblen = luaL_optint(lua, 6, -1);
  int precision = luaL_optint(lua, 7, -1);
  int scale = luaL_optint(lua, 8, -1);

  bool err = false;
  try {
    auto n = new pq_node(name, pq::schema::Node::PRIMITIVE, ud->n->hive_compatible);
    n->node = pq::schema::PrimitiveNode::Make(n->hive_compatible ? hive_name(name) : name,
                                              rt, dt, lt, fblen, precision, scale);
    ud->n->group->fields.push_back(n);
  } catch (exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown column creation error");
    err = true;
  }
  return err ? lua_error(lua) : 0;
}


static void check_mapkv(pq_node *n)
{
  if (!n->node->is_repeated() || n->nt != pq::schema::Node::GROUP || n->name != "key_value") {
    stringstream ss;
    ss << "field '" << n->name << "' must be a repeated group named 'key_value'";
    throw pq::ParquetException(ss.str());
  }

  size_t len = n->group->fields.size();
  if (len != 2) {
    stringstream ss;
    ss << "group '" << n->name << "' must have 2 fields";
    throw pq::ParquetException(ss.str());
  }

  pq_node *cn = n->group->fields[0];
  if (!cn->node->is_required() || cn->nt != pq::schema::Node::PRIMITIVE || cn->name != "key") {
    stringstream ss;
    ss << "field '" << cn->name << "' must be a required primitive named 'key'";
    throw pq::ParquetException(ss.str());
  }

  cn = n->group->fields[1];
  if (cn->node->is_repeated() || cn->name != "value") {
    stringstream ss;
    ss << "field '" << cn->name << "' must be optional or required and named 'value'";
    throw pq::ParquetException(ss.str());
  }
}


static void check_list(pq_node *n)
{
  if (!n->node->is_repeated() || n->nt != pq::schema::Node::GROUP || n->name != "list") {
    stringstream ss;
    ss << "field '" << n->name << "' must be a repeated group named 'list'";
    throw pq::ParquetException(ss.str());
  }

  size_t len = n->group->fields.size();
  if (len != 1) {
    stringstream ss;
    ss << "group '" << n->name << "' must have 1 field";
    throw pq::ParquetException(ss.str());
  }

  pq_node *cn = n->group->fields[0];
  if (cn->node->is_repeated() || cn->name != "element") {
    stringstream ss;
    ss << "field '" << cn->name << "' must be optional or required and named 'element'";
    throw pq::ParquetException(ss.str());
  }
}


static pq::schema::NodePtr build_nested(pq_node *n, int16_t r, int16_t d, size_t &cid)
{
  vector<pq::schema::NodePtr> fields;
  size_t len = n->group->fields.size();

  if (len == 0) {
    stringstream ss;
    ss << "group '" << n->name << "' is empty";
    throw pq::ParquetException(ss.str());
  }

  for (size_t i = 0; i < len; ++i) {
    pq_node *cn = n->group->fields[i];
    pq::Repetition::type rt = cn->node ? cn->node->repetition() : cn->group->rt;
    int16_t cr = r;
    int16_t cd = d;
    if (rt == pq::Repetition::REPEATED) {
      cr = r + 1;
      cd = d + 1;
    } else if (rt == pq::Repetition::OPTIONAL) {
      cd = d + 1;
    }
    cn->rl = cr;
    cn->dl = cd;
    if (!cn->node) {
      cn->node = build_nested(cn, cr, cd, cid);
      auto lt = cn->node->logical_type();
      if (lt == pq::LogicalType::MAP || lt == pq::LogicalType::LIST) {
        if (cn->node->is_repeated() || cn->group->fields.size() != 1) {
          stringstream ss;
          ss << "group '" << cn->name << "' must be required or optional and contain a single group field";
          throw pq::ParquetException(ss.str());
        }
        if (lt == pq::LogicalType::MAP) {
          check_mapkv(cn->group->fields[0]);
        } else if (lt == pq::LogicalType::LIST) {
          check_list(cn->group->fields[0]);
        }
      }
    } else {
      cn->column = cid++;
    }
    fields.push_back(cn->node);
  }
  return pq::schema::GroupNode::Make(n->hive_compatible ? hive_name(n->name) : n->name,
                                     n->group->rt, fields,
                                     n->group->lt > pq::LogicalType::INTERVAL ? pq::LogicalType::NONE : n->group->lt);
}


static void add_columns(pq_writer *pw, pq_node *n)
{
  size_t len = n->group->fields.size();
  for (size_t i = 0; i < len; ++i) {
    pq_node *cn = n->group->fields[i];
    if (cn->nt == pq::schema::Node::GROUP) {
      add_columns(pw, cn);
    } else {
      // create a column data collector specific to this writer
      pq_column *c = new pq_column(cn);
      switch (c->pn->physical_type()) {
      case pq::Type::INT32:
        c->i32 = new vector<int32_t>;
        break;
      case pq::Type::INT64:
        c->i64 = new vector<int64_t>;
        break;
      case pq::Type::INT96:
        c->i96 = new vector<pq::Int96>;
        break;
      case pq::Type::FLOAT:
        c->f = new vector<float>;
        break;
      case pq::Type::DOUBLE:
        c->d = new vector<double>;
        break;
      case pq::Type::BYTE_ARRAY:
        c->ba = new vector<pq::ByteArray>;
        c->bytes = new vector<uint8_t>;
        break;
      case pq::Type::FIXED_LEN_BYTE_ARRAY:
        c->flba = new vector<pq::FixedLenByteArray>;
        c->bytes = new vector<uint8_t>;
        break;
      case pq::Type::BOOLEAN:
        c->bytes = new vector<uint8_t>;
        break;
      }
      if (cn->rl > 0) {
        c->rlevels = new vector<int16_t>;
      }
      if (cn->dl > 0) {
        c->dlevels = new vector<int16_t>;
      }
      pw->columns.push_back(c);
    }
  }
}


static int pq_schema_finalize(lua_State *lua)
{
  pq_node_ud *ud = static_cast<pq_node_ud *>
      (luaL_checkudata(lua, 1, mozsvc_parquet_schema));

  bool err = false;
  try {
    if (!ud->n->node) {
      size_t cid = 0;
      ud->n->node = build_nested(ud->n, 0, 0, cid);
      pq::SchemaDescriptor sd;
      sd.Init(ud->n->node);
    }
  } catch (exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown schema finalization error");
    err = true;
  }
  return err ? lua_error(lua) : 0;
}


static void setup_column_properties(lua_State *lua, const char *colname,
                                    pq::WriterProperties::Builder &pb)
{
  lua_pushnil(lua);
  while (lua_next(lua, -2) != 0) {
    const char *key = lua_tostring(lua, -2);
    if (key) {
      if (strcmp(key, "enable_dictionary") == 0) {
        if (lua_toboolean(lua, -1)) {
          pb.enable_dictionary(colname);
        } else {
          pb.disable_dictionary(colname);
        }
      } else if (strcmp(key, "encoding") == 0) {
        const char *v = lua_tostring(lua, -1);
        if (v) {
          if (strcmp(v, "plain") == 0) {
            pb.encoding(colname, pq::Encoding::PLAIN);
          } else if (strcmp(v, "plain_dictionary") == 0) {
            pb.encoding(colname, pq::Encoding::PLAIN_DICTIONARY);
          } else if (strcmp(v, "rle") == 0) {
            pb.encoding(colname, pq::Encoding::RLE);
          } else if (strcmp(v, "bit_packed") == 0) {
            pb.encoding(colname, pq::Encoding::BIT_PACKED);
          } else if (strcmp(v, "delta_binary_packed") == 0) {
            pb.encoding(colname, pq::Encoding::DELTA_BINARY_PACKED);
          } else if (strcmp(v, "delta_length_byte_array") == 0) {
            pb.encoding(colname, pq::Encoding::DELTA_LENGTH_BYTE_ARRAY);
          } else if (strcmp(v, "delta_byte_array") == 0) {
            pb.encoding(colname, pq::Encoding::DELTA_BYTE_ARRAY);
          } else if (strcmp(v, "rle_dictionary") == 0) {
            pb.encoding(colname, pq::Encoding::RLE_DICTIONARY);
          } else {
            stringstream ss;
            ss << "invalid encoding:" << v << " column:" << colname;
            throw pq::ParquetException(ss.str());
          }
        }
      } else if (strcmp(key, "compression") == 0) {
        const char *v = lua_tostring(lua, -1);
        if (v) {
          if (strcmp(v, "uncompressed") == 0) {
            pb.compression(colname, pq::Compression::UNCOMPRESSED);
          } else if (strcmp(v, "snappy") == 0) {
            pb.compression(colname, pq::Compression::SNAPPY);
          } else if (strcmp(v, "gzip") == 0) {
            pb.compression(colname, pq::Compression::GZIP);
          } else if (strcmp(v, "lzo") == 0) {
            pb.compression(colname, pq::Compression::LZO);
          } else if (strcmp(v, "brotli") == 0) {
            pb.compression(colname, pq::Compression::BROTLI);
          } else {
            stringstream ss;
            ss << "invalid compression:" << v << " column:" << colname;
            throw pq::ParquetException(ss.str());
          }
        }
      } else if (strcmp(key, "enable_statistics") == 0) {
        if (lua_toboolean(lua, -1)) {
          pb.enable_statistics(colname);
        } else {
          pb.disable_statistics(colname);
        }
      }
    }
    lua_pop(lua, 1);
  }
}


static shared_ptr<pq::WriterProperties> setup_properties(lua_State *lua)
{
  pq::WriterProperties::Builder pb;
  lua_pushnil(lua);
  while (lua_next(lua, 3) != 0) {
    if (lua_type(lua, -2) != LUA_TSTRING) {
      stringstream ss;
      ss << "non string key in the properties table";
      throw pq::ParquetException(ss.str());
    }

    const char *key = lua_tostring(lua, -2);
    if (key) {
      if (strcmp(key, "enable_dictionary") == 0) {
        if (lua_toboolean(lua, -1)) {
          pb.enable_dictionary();
        } else {
          pb.disable_dictionary();
        }
      } else if (strcmp(key, "dictionary_pagesize_limit") == 0) {
        int64_t i = static_cast<int64_t>(lua_tonumber(lua, -1));
        pb.dictionary_pagesize_limit(i);
      } else if (strcmp(key, "write_batch_size") == 0) {
        int64_t i = static_cast<int64_t>(lua_tonumber(lua, -1));
        pb.write_batch_size(i);
      } else if (strcmp(key, "data_pagesize") == 0) {
        int64_t i = static_cast<int64_t>(lua_tonumber(lua, -1));
        pb.data_pagesize(i);
      } else if (strcmp(key, "version") == 0) {
        const char *v = lua_tostring(lua, -1);
        if (v) {
          if (strcmp(v, "1.0") == 0) {
            pb.version(pq::ParquetVersion::PARQUET_1_0);
          } else if (strcmp(v, "2.0") == 0) {
            pb.version(pq::ParquetVersion::PARQUET_2_0);
          } else {
            stringstream ss;
            ss << "invalid version:" << v;
            throw pq::ParquetException(ss.str());
          }
        }
      } else if (strcmp(key, "created_by") == 0) {
        const char *v = lua_tostring(lua, -1);
        if (v) {
          pb.created_by(v);
        }
      } else if (strcmp(key, "encoding") == 0) {
        const char *v = lua_tostring(lua, -1);
        if (v) {
          if (strcmp(v, "plain") == 0) {
            pb.encoding(pq::Encoding::PLAIN);
          } else if (strcmp(v, "plain_dictionary") == 0) {
            pb.encoding(pq::Encoding::PLAIN_DICTIONARY);
          } else if (strcmp(v, "rle") == 0) {
            pb.encoding(pq::Encoding::RLE);
          } else if (strcmp(v, "bit_packed") == 0) {
            pb.encoding(pq::Encoding::BIT_PACKED);
          } else if (strcmp(v, "delta_binary_packed") == 0) {
            pb.encoding(pq::Encoding::DELTA_BINARY_PACKED);
          } else if (strcmp(v, "delta_length_byte_array") == 0) {
            pb.encoding(pq::Encoding::DELTA_LENGTH_BYTE_ARRAY);
          } else if (strcmp(v, "delta_byte_array") == 0) {
            pb.encoding(pq::Encoding::DELTA_BYTE_ARRAY);
          } else if (strcmp(v, "rle_dictionary") == 0) {
            pb.encoding(pq::Encoding::RLE_DICTIONARY);
          } else {
            stringstream ss;
            ss << "invalid encoding:" << v;
            throw pq::ParquetException(ss.str());
          }
        }
      } else if (strcmp(key, "compression") == 0) {
        const char *v = lua_tostring(lua, -1);
        if (v) {
          if (strcmp(v, "uncompressed") == 0) {
            pb.compression(pq::Compression::UNCOMPRESSED);
          } else if (strcmp(v, "snappy") == 0) {
            pb.compression(pq::Compression::SNAPPY);
          } else if (strcmp(v, "gzip") == 0) {
            pb.compression(pq::Compression::GZIP);
          } else if (strcmp(v, "lzo") == 0) {
            pb.compression(pq::Compression::LZO);
          } else if (strcmp(v, "brotli") == 0) {
            pb.compression(pq::Compression::BROTLI);
          } else {
            stringstream ss;
            ss << "invalid compression:" << v;
            throw pq::ParquetException(ss.str());
          }
        }
      } else if (strcmp(key, "enable_statistics") == 0) {
        if (lua_toboolean(lua, -1)) {
          pb.enable_statistics();
        } else {
          pb.disable_statistics();
        }
      } else if (strcmp(key, "columns") == 0) {
        if (lua_type(lua, -1) == LUA_TTABLE) {
          lua_pushnil(lua);
          while (lua_next(lua, -2) != 0) {
            const char *colname = lua_tostring(lua, -2);
            if (lua_type(lua, -1) == LUA_TTABLE) {
              setup_column_properties(lua, colname, pb);
            }
            lua_pop(lua, 1);
          }
        } else {
          stringstream ss;
          ss << "columns must be a table";
          throw pq::ParquetException(ss.str());
        }
      }
    }
    lua_pop(lua, 1);
  }
  return pb.build();
}


static int pq_new_writer(lua_State *lua)
{
  size_t len;
  const char *name = luaL_checklstring(lua, 1, &len);
  luaL_argcheck(lua, len > 0, 1, "filenamename cannot be empty");

  pq_node_ud *ud = static_cast<pq_node_ud *>
      (luaL_checkudata(lua, 2, mozsvc_parquet_schema));
  luaL_argcheck(lua, ud->n->node, 2, "the schema has not been finalized");

  int t = lua_type(lua, 3);
  luaL_argcheck(lua, t == LUA_TTABLE || t == LUA_TNONE || t == LUA_TNIL, 3,
                "properties must be a table");

  pq_writer_ud *pw = static_cast<pq_writer_ud *>(lua_newuserdata(lua, sizeof*pw));
  pw->w = NULL;
  luaL_getmetatable(lua, mozsvc_parquet_writer);
  lua_setmetatable(lua, -2);

  bool err = false;
  try {
    pw->w = new pq_writer;
    pw->w->node = ud->n;
    ++pw->w->node->ref_cnt;
    pw->w->num_records = 0;
    add_columns(pw->w, pw->w->node);

    shared_ptr<pq::LocalFileOutputStream> sink(new pq::LocalFileOutputStream(name));
    if (t == LUA_TTABLE) {
      pw->w->writer = pq::ParquetFileWriter::Open(sink, static_pointer_cast<pq::schema::GroupNode>(ud->n->node),
                                                  setup_properties(lua));
    } else {
      pw->w->writer = pq::ParquetFileWriter::Open(sink, static_pointer_cast<pq::schema::GroupNode>(ud->n->node));
    }
  } catch (exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown writer creation error");
    err = true;
  }
  return err ? lua_error(lua) : 1;
}


static int pq_version(lua_State *lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


static const struct luaL_reg pq_lib_f[] = {
  { "schema", pq_new_schema },
  { "writer", pq_new_writer },
  { "version", pq_version },
  { NULL, NULL }
};


static const struct luaL_reg pq_schemalib_m[] = {
  { "add_group", pq_new_group },
  { "add_column", pq_new_column },
  { "finalize", pq_schema_finalize },
  { "__gc", pq_schema_gc },
  { NULL, NULL }
};


static const struct luaL_reg pq_grouplib_m[] = {
  { "add_group", pq_new_group },
  { "add_column", pq_new_column },
  { NULL, NULL }
};


static void write_columns(pq_writer *pw, pq::RowGroupWriter *rgw)
{
  size_t len = pw->columns.size();
  for (size_t i = 0; i < len; ++i) {
    pq_column *c = pw->columns[i];
    size_t nv = c->num_values;
    int16_t *rlevels = c->rlevels ? c->rlevels->data() : nullptr;
    int16_t *dlevels = c->dlevels ? c->dlevels->data() : nullptr;
    switch (c->pn->physical_type()) {
    case pq::Type::BOOLEAN:
      {
        auto column_writer = static_cast<pq::TypedColumnWriter<pq::BooleanType> *>(rgw->NextColumn());
        column_writer->WriteBatch(nv, dlevels, rlevels, reinterpret_cast<bool *>(c->bytes->data()));
        column_writer->Close();
        c->bytes->clear();
      }
      break;
    case pq::Type::INT32:
      {
        auto column_writer = static_cast<pq::TypedColumnWriter<pq::Int32Type> *>(rgw->NextColumn());
        column_writer->WriteBatch(nv, dlevels, rlevels, c->i32->data());
        column_writer->Close();
        c->i32->clear();
      }
      break;
    case pq::Type::INT64:
      {
        auto column_writer = static_cast<pq::TypedColumnWriter<pq::Int64Type> *>(rgw->NextColumn());
        column_writer->WriteBatch(nv, dlevels, rlevels, c->i64->data());
        column_writer->Close();
        c->i64->clear();
      }
      break;
    case pq::Type::INT96:
      {
        auto column_writer = static_cast<pq::TypedColumnWriter<pq::Int96Type> *>(rgw->NextColumn());
        column_writer->WriteBatch(nv, dlevels, rlevels, c->i96->data());
        column_writer->Close();
        c->i96->clear();
      }
      break;
    case pq::Type::FLOAT:
      {
        auto column_writer = static_cast<pq::TypedColumnWriter<pq::FloatType> *>(rgw->NextColumn());
        column_writer->WriteBatch(nv, dlevels, rlevels, c->f->data());
        column_writer->Close();
        c->f->clear();
      }
      break;
    case pq::Type::DOUBLE:
      {
        auto column_writer = static_cast<pq::TypedColumnWriter<pq::DoubleType> *>(rgw->NextColumn());
        column_writer->WriteBatch(nv, dlevels, rlevels, c->d->data());
        column_writer->Close();
        c->d->clear();
      }
      break;
    case pq::Type::BYTE_ARRAY:
      {
        uint8_t *base = c->bytes->data();
        size_t len = c->ba->size();
        for (size_t i = 0; i < len; ++i) {
          uint8_t *adjusted = base + reinterpret_cast<size_t>((*c->ba)[i].ptr);
          (*c->ba)[i].ptr = adjusted;
        }
        auto column_writer = static_cast<pq::TypedColumnWriter<pq::ByteArrayType> *>(rgw->NextColumn());
        column_writer->WriteBatch(nv, dlevels, rlevels, c->ba->data());
        column_writer->Close();
        c->bytes->clear();
        c->ba->clear();
      }
      break;
    case pq::Type::FIXED_LEN_BYTE_ARRAY:
      {
        uint8_t *base = c->bytes->data();
        size_t len = c->flba->size();
        for (size_t i = 0; i < len; ++i) {
          uint8_t *adjusted = base + reinterpret_cast<size_t>((*c->flba)[i].ptr);
          (*c->flba)[i].ptr = adjusted;
        }
        auto column_writer = static_cast<pq::TypedColumnWriter<pq::FLBAType> *>(rgw->NextColumn());
        column_writer->WriteBatch(nv, dlevels, rlevels, c->flba->data());
        column_writer->Close();
        c->bytes->clear();
        c->flba->clear();
      }
      break;
    }
    c->num_values = 0;
    c->rec_num = 0;
    c->rec_v_items = 0;
    if (c->rlevels) {
      c->rlevels->clear();
      c->rec_r_items = 0;
    }
    if (c->dlevels) {
      c->dlevels->clear();
      c->rec_d_items = 0;
    }
  }
}


static void clear_columns(pq_writer *pw)
{
  size_t len = pw->columns.size();
  for (size_t i = 0; i < len; ++i) {
    pq_column *c = pw->columns[i];
    switch (c->pn->physical_type()) {
    case pq::Type::BOOLEAN:
      {
        c->bytes->clear();
      }
      break;
    case pq::Type::INT32:
      {
        c->i32->clear();
      }
      break;
    case pq::Type::INT64:
      {
        c->i64->clear();
      }
      break;
    case pq::Type::INT96:
      {
        c->i96->clear();
      }
      break;
    case pq::Type::FLOAT:
      {
        c->f->clear();
      }
      break;
    case pq::Type::DOUBLE:
      {
        c->d->clear();
      }
      break;
    case pq::Type::BYTE_ARRAY:
      c->bytes->clear();
      c->ba->clear();
      break;
    case pq::Type::FIXED_LEN_BYTE_ARRAY:
      c->bytes->clear();
      c->flba->clear();
      break;
    }
    c->num_values = 0;
    c->rec_num = 0;
    c->rec_v_items = 0;
    if (c->rlevels) {
      c->rlevels->clear();
      c->rec_r_items = 0;
    }
    if (c->dlevels) {
      c->dlevels->clear();
      c->rec_d_items = 0;
    }
  }
  pw->num_records = 0;
}

/* debugging only
static void dump_records(pq_writer *pw)
{
  size_t len = pw->columns.size();
  for (size_t i = 0; i < len; ++i) {
    pq_column *c = pw->columns[i];
    if (c->rlevels) {
      cerr << c->pn->name() << " rlevels:";
      size_t len = c->rlevels->size();
      for (size_t i = 0; i < len; ++i) {
        cerr << (*c->rlevels)[i] << "|";
      }
      cerr << endl;
    }
    if (c->dlevels) {
      cerr << c->pn->name() << " dlevels:";
      size_t len = c->dlevels->size();
      for (size_t i = 0; i < len; ++i) {
        cerr << (*c->dlevels)[i] << "|";
      }
      cerr << endl;
    }

    switch (c->pn->physical_type()) {
    case pq::Type::BOOLEAN:
      {
        cerr << c->pn->name() << " values:";
        size_t len = c->bytes->size();
        for (size_t i = 0; i < len; ++i) {
          cerr << ((*c->bytes)[i] ? 'T' : 'F') << "|";
        }
        cerr << endl;
      }
      break;
    case pq::Type::INT32:
      {
        cerr << c->pn->name() << " values:";
        size_t len = c->i32->size();
        for (size_t i = 0; i < len; ++i) {
          cerr << (*c->i32)[i] << "|";
        }
        cerr << endl;
      }
      break;
    case pq::Type::INT64:
      {
        cerr << c->pn->name() << " values:";
        size_t len = c->i64->size();
        for (size_t i = 0; i < len; ++i) {
          cerr << (*c->i64)[i] << "|";
        }
        cerr << endl;
      }
      break;
    case pq::Type::INT96:
      {
        cerr << c->pn->name() << " values:";
        size_t len = c->i96->size();
        for (size_t i = 0; i < len; ++i) {
          string s(reinterpret_cast<const char *>(&(*c->i96)[i]),
                   sizeof(pq::Int96));
          cerr << s << "|";
        }
        cerr << endl;
      }
      break;
    case pq::Type::FLOAT:
      {
        cerr << c->pn->name() << " values:";
        size_t len = c->f->size();
        for (size_t i = 0; i < len; ++i) {
          cerr << (*c->f)[i] << "|";
        }
        cerr << endl;
      }
      break;
    case pq::Type::DOUBLE:
      {
        cerr << c->pn->name() << " values:";
        size_t len = c->d->size();
        for (size_t i = 0; i < len; ++i) {
          cerr << (*c->d)[i] << "|";
        }
        cerr << endl;
      }
      break;
    case pq::Type::BYTE_ARRAY:
      {
        uint8_t *base = c->bytes->data();
        size_t len = c->ba->size();
        cerr << c->pn->name() << " values(" << len << "):";
        for (size_t i = 0; i < len; ++i) {
          uint8_t *adjusted = base + reinterpret_cast<size_t>((*c->ba)[i].ptr);
          cerr << string(reinterpret_cast<const char *>(adjusted),
                         (*c->ba)[i].len) << "|";
        }
        cerr << endl;
      }
      break;
    case pq::Type::FIXED_LEN_BYTE_ARRAY:
      {
        uint8_t *base = c->bytes->data();
        size_t len = c->flba->size();
        cerr << c->pn->name() << " values(" << len << "):";
        for (size_t i = 0; i < len; ++i) {
          uint8_t *adjusted = base + reinterpret_cast<size_t>((*c->flba)[i].ptr);
          cerr << string(reinterpret_cast<const char *>(adjusted),
                         c->pn->type_length()) << "|";
        }
        cerr << endl;
      }
      break;
    }
  }
}
*/


static void write_rowgroup(pq_writer *pw)
{
  if (pw->writer && pw->num_records > 0) {
    //dump_records(pw);
    auto rgw = pw->writer->AppendRowGroup(pw->num_records);
    write_columns(pw, rgw);
    rgw->Close();
    pw->num_records = 0;
  }
}


static int pq_writer_rowgroup(lua_State *lua)
{
  pq_writer_ud *pw = static_cast<pq_writer_ud *>
      (luaL_checkudata(lua, 1, mozsvc_parquet_writer));
  if (!pw->w->writer) {
    luaL_error(lua, "writer closed");
  }

  bool err = false;
  try {
    write_rowgroup(pw->w);
  } catch (exception &e) {
    clear_columns(pw->w);
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    clear_columns(pw->w);
    lua_pushstring(lua, "unknown write_rowgroup error");
    err = true;
  }
  return err ? lua_error(lua) : 0;
}


static void writer_close(pq_writer *pw)
{
  if (pw->writer) {
    pw->writer->Close();
    pw->writer = nullptr;
  }
}


static int pq_writer_close(lua_State *lua)
{
  pq_writer_ud *pw = static_cast<pq_writer_ud *>
      (luaL_checkudata(lua, 1, mozsvc_parquet_writer));

  bool err = false;
  try {
    try {
      write_rowgroup(pw->w);
    } catch (exception &e) {
      clear_columns(pw->w);
      lua_pushstring(lua, e.what());
      err = true;
    } catch (...) {
      clear_columns(pw->w);
      lua_pushstring(lua, "unknown write_rowgroup error");
      err = true;
    }
    writer_close(pw->w);
  } catch (exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown writer close error");
    err = true;
  }
  return err ? lua_error(lua) : 0;
}


static int pq_writer_gc(lua_State *lua)
{
  pq_writer_ud *pw = static_cast<pq_writer_ud *>
      (luaL_checkudata(lua, 1, mozsvc_parquet_writer));
  if (!pw->w) {return 0;}

  bool err = false;
  try {
    try {
      write_rowgroup(pw->w);
    } catch (...) {
      clear_columns(pw->w);
    }

    try {
      writer_close(pw->w);
    } catch (...) {}

    if (--pw->w->node->ref_cnt == 0) {
      free_children(pw->w->node);
    }
    delete(pw->w);
  } catch (exception &e) {
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    lua_pushstring(lua, "unknown writer gc error");
    err = true;
  }
  return err ? lua_error(lua) : 0;
}


static void update_levels(pq_column *c, int16_t r, int16_t d)
{
  ++c->num_values;
  if (c->rlevels) {
    c->rlevels->push_back(r);
    ++c->rec_r_items;
  }
  if (c->dlevels) {
    c->dlevels->push_back(d);
    ++c->rec_d_items;
  }
}


static void
add_string(pq_column *c, const char *cs, size_t cs_len, int16_t r, int16_t d)
{
  switch (c->pn->physical_type()) {
  case pq::Type::BYTE_ARRAY:
    {
      const uint8_t *s = reinterpret_cast<const uint8_t *>(cs);
      size_t pos = c->bytes->size();
      c->bytes->insert(c->bytes->end(), s, s + cs_len);
      c->ba->emplace_back(static_cast<uint32_t>(cs_len),
                          reinterpret_cast<uint8_t *>(pos));
    }
    break;
  case pq::Type::FIXED_LEN_BYTE_ARRAY:
    {
      size_t fixed_len = c->pn->type_length();
      const uint8_t *s = reinterpret_cast<const uint8_t *>(cs);
      if (cs_len != fixed_len) {
        stringstream ss;
        ss << "column '" << c->n->name << "' expected FIXED_LEN_BYTE_ARRAY("
            << fixed_len << ") but received " << cs_len << " bytes";
        throw pq::ParquetException(ss.str());
      }
      size_t pos = c->bytes->size();
      c->bytes->insert(c->bytes->end(), s, s + cs_len);
      c->flba->emplace_back(reinterpret_cast<uint8_t *>(pos));
    }
    break;
  case pq::Type::INT96:
    if (cs_len != sizeof(pq::Int96)) {
      stringstream ss;
      ss << "column '" << c->n->name << "' expected INT96 but received "
          << cs_len << " bytes";
      throw pq::ParquetException(ss.str());
    }
    c->i96->push_back(*reinterpret_cast<const pq::Int96 *>(cs));
    break;
  default:
    {
      stringstream ss;
      ss << "column '" << c->n->name << "' data type mismatch (string)";
      throw pq::ParquetException(ss.str());
    }
    break;
  }
  update_levels(c, r, d);
  ++c->rec_v_items;
}


static void add_boolean(pq_column *c, bool b, int16_t r, int16_t d)
{
  switch (c->pn->physical_type()) {
  case pq::Type::BOOLEAN:
    c->bytes->push_back(b);
    break;
  default:
    {
      stringstream ss;
      ss << "column '" << c->n->name << "' data type mismatch (boolean)";
      throw pq::ParquetException(ss.str());
    }
    break;
  }
  update_levels(c, r, d);
  ++c->rec_v_items;
}


static void add_integer(pq_column *c, long long i, int16_t r, int16_t d)
{
  switch (c->pn->physical_type()) {
  case pq::Type::INT32:
    c->i32->push_back(static_cast<int32_t>(i));
    break;
  case pq::Type::INT64:
    c->i64->push_back(static_cast<int64_t>(i));
    break;
  default:
    {
      stringstream ss;
      ss << "column '" << c->n->name << "' data type mismatch (integer)";
      throw pq::ParquetException(ss.str());
    }
    break;
  }
  update_levels(c, r, d);
  ++c->rec_v_items;
}


static void add_number(pq_column *c, double n, int16_t r, int16_t d)
{
  switch (c->pn->physical_type()) {
  case pq::Type::FLOAT:
    c->f->push_back(static_cast<float>(n));
    break;
  case pq::Type::DOUBLE:
    c->d->push_back(n);
    break;
  default:
    {
      stringstream ss;
      ss << "column '" << c->n->name << "' data type mismatch (number)";
      throw pq::ParquetException(ss.str());
    }
    break;
  }
  update_levels(c, r, d);
  ++c->rec_v_items;
}


static void add_null(pq_column *c, int16_t r, int16_t d)
{
  if (!c->dlevels || (c->n->dl == d && c->pn->is_required())) {
    stringstream ss;
    ss << "column '" << c->n->name << "' is required";
    throw pq::ParquetException(ss.str());
  }
  update_levels(c, r, d);
}


static void add_value(lua_State *lua, pq_node *n, pq_column *c, int16_t r, int16_t d)
{
  if (!c) {
    stringstream ss;
    ss << "group '" << n->name << "' expected, found data";
    throw pq::ParquetException(ss.str());
  }
  int t = lua_type(lua, -1);
  switch (t) {
  case LUA_TSTRING:
    {
      size_t len;
      const char *cs;
      cs = lua_tolstring(lua, -1, &len);
      add_string(c, cs, len, r, d);
    }
    break;
  case LUA_TNUMBER:
    {
      double num = lua_tonumber(lua, -1);
      auto t = c->pn->physical_type();
      if (t == pq::Type::DOUBLE || t == pq::Type::FLOAT) {
        add_number(c, num, r, d);
      } else {
        add_integer(c, static_cast<long long>(num), r, d);
      }
    }
    break;
  case LUA_TBOOLEAN:
    add_boolean(c, lua_toboolean(lua, -1), r, d);
    break;
  default:
    {
      stringstream ss;
      ss << "column '" << n->name << "' unsupported data type: " <<
          lua_typename(lua, t);
      throw pq::ParquetException(ss.str());
    }
    break;
  }
}


static void reset_record(pq_writer *pw, pq_column *c)
{
  if (c->rec_num != pw->num_records) {
    c->rec_num = pw->num_records;
    c->rec_r_items = 0;
    c->rec_d_items = 0;
    c->rec_v_items = 0;
  }
}


static void dissect_null(pq_writer *pw, pq_node *n, int16_t r, int16_t d)
{
  if (n->dl == 0) {
    stringstream ss;
    ss << "group '" << n->name << "' is required";
    throw pq::ParquetException(ss.str());
  }

  size_t len = n->group->fields.size();
  for (size_t i = 0; i < len; ++i) {
    pq_column *c = NULL;
    pq_node *cn = n->group->fields[i];
    if (cn->nt == pq::schema::Node::PRIMITIVE) {
      c = pw->columns[cn->column];
      reset_record(pw, c);
      add_null(c, r, d);
    } else {
      dissect_null(pw, cn, r, d);
    }
  }
}


static void dissect_record(pq_writer *pw, lua_State *lua, pq_node *n, int16_t r, int16_t d);
static void dissect_map(pq_writer *pw, lua_State *lua, pq_node *n, int16_t r, int16_t d);
static void dissect_list(pq_writer *pw, lua_State *lua, pq_node *n, int16_t r, int16_t d);
static void dissect_tuple(pq_writer *pw, lua_State *lua, pq_node *n, int16_t r, int16_t d);

static void dissect_field(pq_writer *pw, lua_State *lua, pq_node *n, int16_t r, int16_t d)
{
  pq_column *c = NULL;
  if (n->nt == pq::schema::Node::PRIMITIVE) {
    c = pw->columns[n->column];
    reset_record(pw, c);
  }

  switch (lua_type(lua, -1)) {
  case LUA_TTABLE:
    if (n->node->is_group()) {
      if (n->node->is_repeated() && lua_objlen(lua, -1) > 0) { // array of groups
        size_t ol = lua_objlen(lua, -1);
        for (size_t j = 1; j <= ol; ++j) {
          lua_rawgeti(lua, -1, j);
          if (lua_type(lua, -1) != LUA_TTABLE) {
            stringstream ss;
            ss << "column '" << n->name << "' expected an array of groups";
            throw pq::ParquetException(ss.str());
          }
          dissect_record(pw, lua, n, r, n->dl);
          lua_pop(lua, 1);
          r = n->rl;
        }
      } else {
        auto lt = n->group->lt;
        if (lt == pq::LogicalType::MAP) {
          dissect_map(pw, lua, n->group->fields[0], r, n->dl);
        } else if (lt == pq::LogicalType::LIST) {
          dissect_list(pw, lua, n->group->fields[0], r, n->dl);
        } else if (lt == pq::LogicalType::INTERVAL + 1) {
          dissect_tuple(pw, lua, n, r, n->dl);
        } else {
          dissect_record(pw, lua, n, r, n->dl);
        }
      }
    } else { // array of values
      if (!n->node->is_repeated()) {
        stringstream ss;
        ss << "column '" << n->name << "' should not be repeated";
        throw pq::ParquetException(ss.str());
      }
      size_t ol = lua_objlen(lua, -1);
      if (ol == 0) {
        add_null(c, r, d);
      } else {
        for (size_t j = 1; j <= ol; ++j) {
          lua_rawgeti(lua, -1, j);
          add_value(lua, n, c, r, n->dl);
          lua_pop(lua, 1);
          r = n->rl;
        }
      }
    }
    break;
  case LUA_TNIL:
    if (n->nt == pq::schema::Node::PRIMITIVE) {
      add_null(c, r, d);
    } else {
      dissect_null(pw, n, r, d);
    }
    break;
  default:
    add_value(lua, n, c, r, n->dl);
    break;
  }
}


static void dissect_map(pq_writer *pw, lua_State *lua, pq_node *n, int16_t r, int16_t d)
{
  pq_node *kn = n->group->fields[0];
  pq_node *vn = n->group->fields[1];

  pq_column *kc = pw->columns[kn->column];
  reset_record(pw, kc);

  int cr = r;
  bool found = false;
  lua_pushnil(lua);
  while (lua_next(lua, -2) != 0) {
    dissect_field(pw, lua, vn, cr, vn->dl);
    lua_pop(lua, 1);
    add_value(lua, kn, kc, cr, kn->dl);
    cr = n->rl;
    found = true;
  }

  if (!found) {
    dissect_null(pw, n, r, d);
  }
}


static void dissect_list(pq_writer *pw, lua_State *lua, pq_node *n, int16_t r, int16_t d)
{
  pq_node *vn = n->group->fields[0];

  int cr = r;
  bool found = false;
  lua_pushnil(lua);
  while (lua_next(lua, -2) != 0) {
    dissect_field(pw, lua, vn, cr, vn->dl);
    lua_pop(lua, 1);
    cr = n->rl;
    found = true;
  }

  if (!found) {
    dissect_null(pw, n, r, d);
  }
}


static void dissect_tuple(pq_writer *pw, lua_State *lua, pq_node *n, int16_t r, int16_t d)
{
  size_t len = n->group->fields.size();
  for (size_t i = 0; i < len; ++i) {
    pq_node *cn = n->group->fields[i];
    lua_checkstack(lua, 2);
    lua_rawgeti(lua, -1, i + 1);
    dissect_field(pw, lua, cn, r, d);
    lua_pop(lua, 1);
  }
}


static void dissect_record(pq_writer *pw, lua_State *lua, pq_node *n, int16_t r, int16_t d)
{
  size_t len = n->group->fields.size();
  for (size_t i = 0; i < len; ++i) {
    pq_node *cn = n->group->fields[i];
    lua_checkstack(lua, 2);
    lua_getfield(lua, -1, cn->name.c_str());
    dissect_field(pw, lua, cn, r, d);
    lua_pop(lua, 1);
  }
}


void rollback_record(pq_writer *pw)
{
  size_t len = pw->columns.size();
  for (size_t i = 0; i < len; ++i) {
    pq_column *c = pw->columns[i];

    if (c->rec_num != pw->num_records) {
      return;
    }

    size_t nv = c->rec_v_items;
    if (c->rec_r_items) {
      nv = c->rec_r_items;
      c->rlevels->resize(c->rlevels->size() - c->rec_r_items);
      c->rec_r_items = 0;
    }

    if (c->rec_d_items) {
      nv = c->rec_d_items;
      c->dlevels->resize(c->dlevels->size() - c->rec_d_items);
      c->rec_d_items = 0;
    }
    c->num_values -= nv;

    if (c->rec_v_items) {
      switch (c->pn->physical_type()) {
      case pq::Type::BOOLEAN:
        c->bytes->resize(c->bytes->size() - c->rec_v_items);
        break;
      case pq::Type::INT32:
        c->i32->resize(c->i32->size() - c->rec_v_items);
        break;
      case pq::Type::INT64:
        c->i64->resize(c->i64->size() - c->rec_v_items);
        break;
      case pq::Type::INT96:
        c->i96->resize(c->i96->size() - c->rec_v_items);
        break;
      case pq::Type::FLOAT:
        c->f->resize(c->f->size() - c->rec_v_items);
        break;
      case pq::Type::DOUBLE:
        c->d->resize(c->d->size() - c->rec_v_items);
        break;
      case pq::Type::BYTE_ARRAY:
        // we can leave the cruft in bytes as it won't impact the output
        c->ba->resize(c->ba->size() - c->rec_v_items);
        break;
      case pq::Type::FIXED_LEN_BYTE_ARRAY:
        // we can leave the cruft in bytes as it won't impact the output
        c->flba->resize(c->flba->size() - c->rec_v_items);
        break;
      }
      c->rec_v_items = 0;
    }
  }
}


static int pq_writer_dissect(lua_State *lua)
{
  pq_writer_ud *pw = static_cast<pq_writer_ud *>
      (luaL_checkudata(lua, 1, mozsvc_parquet_writer));
  luaL_checktype(lua, 2, LUA_TTABLE);
  if (!pw->w->writer) {
    luaL_error(lua, "writer closed");
  }

  bool err = false;
  try {
    dissect_record(pw->w, lua, pw->w->node, 0, 0);
    ++pw->w->num_records;
  } catch (exception &e) {
    rollback_record(pw->w);
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    rollback_record(pw->w);
    lua_pushstring(lua, "unknown dissect_record error");
    err = true;
  }
  return err ? lua_error(lua) : 0;
}


#ifdef LUA_SANDBOX
static const char*
read_string(const char *p, const char *e, lsb_const_string *s)
{
  int tag = 0;
  int wiretype = 0;
  p = lsb_pb_read_key(p, &tag, &wiretype);
  if (wiretype != LSB_PB_WT_LENGTH) {
    throw pq::ParquetException("invalid protobuf wiretype");
  }

  long long len;
  p = lsb_pb_read_varint(p, e, &len);
  if (!p || len < 0 || p + len > e) {
    throw pq::ParquetException("invalid protobuf length");
  }
  s->s = p;
  s->len = (size_t)len;
  return p + len;
}


static void dissect_fields(pq_writer *pw, const lsb_heka_message *m, pq_node *n)
{
  size_t len = n->group->fields.size();
  for (size_t i = 0; i < len; ++i) {
    pq_node *cn = n->group->fields[i];
    if (cn->nt == pq::schema::Node::PRIMITIVE) {
      pq_column *c = pw->columns[cn->column];
      if (c->rec_num != pw->num_records) {
        c->rec_num = pw->num_records;
        c->rec_r_items = 0;
        c->rec_d_items = 0;
        c->rec_v_items = 0;
      }

      bool repeated = cn->node->is_repeated();
      bool found = false;
      for (int i = 0; i < m->fields_len && !found; ++i) {
        if (cn->name.size() == m->fields[i].name.len
            && strncmp(cn->name.c_str(), m->fields[i].name.s, m->fields[i].name.len) == 0) {
          found = true;
          const char *p = m->fields[i].value.s;
          const char *e = p + m->fields[i].value.len;
          int16_t cr = 0;
          int cnt = 0;
          while (p && p < e) {
            if (cnt++ && !repeated) {
              stringstream ss;
              ss << "column '" << cn->name << "' data is repeated";
              throw pq::ParquetException(ss.str());
            }
            switch (m->fields[i].value_type) {
            case LSB_PB_STRING:
            case LSB_PB_BYTES:
              {
                lsb_const_string cs;
                p = read_string(p, e, &cs);
                add_string(c, cs.s, cs.len, cr, cn->dl);
              }
              break;
            case LSB_PB_INTEGER:
            case LSB_PB_BOOL:
              {
                long long n;
                p = lsb_pb_read_varint(p, e, &n);
                if (!p) {
                  stringstream ss;
                  ss << "column '" << cn->name << "' invalid protobuf varint";
                  throw pq::ParquetException(ss.str());
                }
                if (m->fields[i].value_type == LSB_PB_INTEGER) {
                  add_integer(c, n, cr, cn->dl);
                } else {
                  add_boolean(c, n, cr, cn->dl);
                }
              }
              break;
            case LSB_PB_DOUBLE:
              {
                if (p + (sizeof(double)) > e) {
                  stringstream ss;
                  ss << "column '" << cn->name << "' invalid protobuf double";
                  throw pq::ParquetException(ss.str());
                }
                double d;
                memcpy(&d, p, sizeof(double));
                p += sizeof(double);
                add_number(c, d, cr, cn->dl);
              }
              break;
            }
            cr = cn->rl;
          }
        }
      }
      if (!found) {
        add_null(c, n->rl, n->dl);
      }
    } else {
      stringstream ss;
      ss << "group '" << cn->name << "' not allowed in " << LSB_FIELDS;
      throw pq::ParquetException(ss.str());
    }
  }
}


static int pq_writer_dissect_message(lua_State *lua)
{
  pq_writer_ud *pw = static_cast<pq_writer_ud *>
      (luaL_checkudata(lua, 1, mozsvc_parquet_writer));
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n == 1, n, "invalid number of arguments");
  if (!pw->w->writer) {
    luaL_error(lua, "writer closed");
  }

  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_HEKA_THIS_PTR);
  lsb_heka_sandbox *hsb =
      static_cast<lsb_heka_sandbox *>(lua_touserdata(lua, -1));
  lua_pop(lua, 1); // remove this ptr
  if (!hsb) {
    return luaL_error(lua, "dissect_message() invalid " LSB_HEKA_THIS_PTR);
  }

  const lsb_heka_message *msg = lsb_heka_get_message(hsb);
  if (!msg || !msg->raw.s) {
    return luaL_error(lua, "dissect_message() no active message");
  }

  bool err = false;
  try {
    size_t len = pw->w->node->group->fields.size();
    for (size_t i = 0; i < len; ++i) {
      pq_node *cn = pw->w->node->group->fields[i];
      if (cn->nt == pq::schema::Node::PRIMITIVE && !cn->node->is_repeated()) {
        pq_column *c = pw->w->columns[cn->column];
        if (c->rec_num != pw->w->num_records) {
          c->rec_num = pw->w->num_records;
          c->rec_r_items = 0;
          c->rec_d_items = 0;
          c->rec_v_items = 0;
        }

        if (cn->name == LSB_UUID) {
          add_string(c, msg->uuid.s, msg->uuid.len, cn->rl, cn->dl);
        } else if (cn->name == LSB_TIMESTAMP) {
          add_integer(c, msg->timestamp, cn->rl, cn->dl);
        } else if (cn->name == LSB_TYPE) {
          if (msg->type.s) {
            add_string(c, msg->type.s, msg->type.len, cn->rl, cn->dl);
          } else {
            add_null(c, 0, 0);
          }
        } else if (cn->name == LSB_LOGGER) {
          if (msg->logger.s) {
            add_string(c, msg->logger.s, msg->logger.len, cn->rl, cn->dl);
          } else {
            add_null(c, 0, 0);
          }
        } else if (cn->name == LSB_SEVERITY) {
          add_integer(c, msg->severity, cn->rl, cn->dl);
        } else if (cn->name == LSB_PAYLOAD) {
          if (msg->payload.s) {
            add_string(c, msg->payload.s, msg->payload.len, cn->rl, cn->dl);
          } else {
            add_null(c, 0, 0);
          }
        } else if (cn->name == LSB_ENV_VERSION) {
          if (msg->env_version.s) {
            add_string(c, msg->env_version.s, msg->env_version.len, cn->rl, cn->dl);
          } else {
            add_null(c, 0, 0);
          }
        } else if (cn->name == LSB_PID) {
          if (msg->pid == INT_MIN) {
            add_null(c, 0, 0);
          } else {
            add_integer(c, msg->pid, cn->rl, cn->dl);
          }
        } else if (cn->name == LSB_HOSTNAME) {
          if (msg->hostname.s) {
            add_string(c, msg->hostname.s, msg->hostname.len, cn->rl, cn->dl);
          } else {
            add_null(c, 0, 0);
          }
        } else {
          stringstream ss;
          ss << "column '" << cn->name << "' invalid schema";
          throw pq::ParquetException(ss.str());
        }
      } else if (cn->name == LSB_FIELDS && !cn->node->is_repeated()) {
        dissect_fields(pw->w, msg, cn);
      } else {
        stringstream ss;
        ss << "group '" << cn->name << "' invalid schema";
        throw pq::ParquetException(ss.str());
      }
    }
    ++pw->w->num_records;
  } catch (exception &e) {
    rollback_record(pw->w);
    lua_pushstring(lua, e.what());
    err = true;
  } catch (...) {
    rollback_record(pw->w);
    lua_pushstring(lua, "unknown dissect_message error");
    err = true;
  }
  return err ? lua_error(lua) : 0;
}
#endif


static const struct luaL_reg pq_writerlib_m[] = {
  { "dissect_record", pq_writer_dissect },
  { "write_rowgroup", pq_writer_rowgroup },
  { "close", pq_writer_close },
  { "__gc", pq_writer_gc },
  { NULL, NULL }
};


int luaopen_parquet(lua_State *lua)
{
  luaL_newmetatable(lua, mozsvc_parquet_schema);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, pq_schemalib_m);
  lua_pop(lua, 1);

  luaL_newmetatable(lua, mozsvc_parquet_group);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, pq_grouplib_m);
  lua_pop(lua, 1);

  luaL_newmetatable(lua, mozsvc_parquet_writer);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, pq_writerlib_m);
#ifdef LUA_SANDBOX
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_HEKA_THIS_PTR);
  lsb_heka_sandbox *hsb = static_cast<lsb_heka_sandbox *>(lua_touserdata(lua, -1));
  lua_pop(lua, 1); // remove this ptr
  if (hsb) {
    lua_pushcfunction(lua, pq_writer_dissect_message);
    lua_setfield(lua, -2, "dissect_message");
  }
#endif
  lua_pop(lua, 1);

  luaL_register(lua, "parquet", pq_lib_f);
  return 1;
}
