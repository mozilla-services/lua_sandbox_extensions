/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua circular buffer implementation @file */

#include <ctype.h>
#include <float.h>
#include <math.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#ifdef _WIN32
#define snprintf _snprintf
#endif

#ifdef _MSC_VER
#pragma warning( disable : 4056 )
#pragma warning( disable : 4756 )
#endif

#ifdef LUA_SANDBOX
#include "luasandbox_output.h"
#include "luasandbox_serialize.h"
#endif

#define COLUMN_NAME_SIZE 16
#define UNIT_LABEL_SIZE 8

static const char *mozsvc_circular_buffer = "mozsvc.circular_buffer";
static const char *mozsvc_circular_buffer_table = "circular_buffer";

static const char *agg_methods[] = { "sum", "min", "max", "none", NULL };
static const char *default_unit = "count";

#if defined(_MSC_VER)
static const char *not_a_number = "nan";
#endif

typedef enum {
  AGGREGATION_SUM,
  AGGREGATION_MIN,
  AGGREGATION_MAX,
  AGGREGATION_NONE,
} COLUMN_AGGREGATION;

typedef enum {
  OUTPUT_CBUF,
  OUTPUT_CBUFD,
} OUTPUT_FORMAT;

typedef struct
{
  char name[COLUMN_NAME_SIZE];
  char unit[UNIT_LABEL_SIZE];
  COLUMN_AGGREGATION aggregation;
} header_info;

typedef struct circular_buffer
{
  time_t        current_time;
  unsigned      seconds_per_row;
  unsigned      current_row;
  unsigned      rows;
  unsigned      columns;
  unsigned      tcolumns; // columns * 2 since we now store the deltas in-line
  OUTPUT_FORMAT format;
  int           ref;

  header_info   *headers;
  double        values[];
} circular_buffer;


static time_t get_start_time(circular_buffer *cb)
{
  return cb->current_time - (cb->seconds_per_row * (cb->rows - 1));
}


static void copy_cleared_row(circular_buffer *cb, double *cleared, size_t rows)
{
  size_t pool = 1;
  size_t ask;

  while (rows > 0) {
    if (rows >= pool) {
      ask = pool;
    } else {
      ask = rows;
    }
    memcpy(cleared + (pool * cb->tcolumns), cleared,
           sizeof(double) * cb->tcolumns * ask);
    rows -= ask;
    pool += ask;
  }
}


static void clear_rows(circular_buffer *cb, unsigned num_rows)
{
  if (num_rows >= cb->rows) {
    num_rows = cb->rows;
  }
  unsigned row = cb->current_row;
  ++row;
  if (row >= cb->rows) {row = 0;}
  for (unsigned c = 0; c < cb->tcolumns; ++c) {
    cb->values[(row * cb->tcolumns) + c] = NAN;
  }
  double *cleared = &cb->values[row * cb->tcolumns];
  if (row + num_rows - 1 >= cb->rows) {
    copy_cleared_row(cb, cleared, cb->rows - row - 1);
    for (unsigned c = 0; c < cb->tcolumns; ++c) {
      cb->values[c] = NAN;
    }
    copy_cleared_row(cb, cb->values, row + num_rows - 1 - cb->rows);
  } else {
    copy_cleared_row(cb, cleared, num_rows - 1);
  }
}


static int cb_new(lua_State *lua)
{
  int n = lua_gettop(lua);
  luaL_argcheck(lua, n >= 3 && n <= 3, 0, "incorrect number of arguments");
  int rows = luaL_checkint(lua, 1);
  luaL_argcheck(lua, 1 < rows, 1, "rows must be > 1");
  int columns = luaL_checkint(lua, 2);
  luaL_argcheck(lua, 0 < columns &&  256 >= columns, 2,
                "columns must be > 0 and <= 256");
  int seconds_per_row = luaL_checkint(lua, 3);
  luaL_argcheck(lua, 0 < seconds_per_row, 3, "seconds_per_row is out of range");

  size_t header_bytes = sizeof(header_info) * columns;
  size_t buffer_bytes = sizeof(double) * rows * columns * 2;
  size_t struct_bytes = sizeof(circular_buffer);

  size_t nbytes = header_bytes + buffer_bytes + struct_bytes;
  circular_buffer *cb = (circular_buffer *)lua_newuserdata(lua, nbytes);
  cb->ref = LUA_NOREF;
  cb->format = OUTPUT_CBUF;
  cb->headers = (header_info *)&cb->values[rows * columns * 2];

  luaL_getmetatable(lua, mozsvc_circular_buffer);
  lua_setmetatable(lua, -2);

  cb->current_time = seconds_per_row * (rows - 1);
  cb->current_row = rows - 1;
  cb->rows = rows;
  cb->columns = columns;
  cb->tcolumns = columns * 2;
  cb->seconds_per_row = seconds_per_row;
  memset(cb->headers, 0, header_bytes);
  for (unsigned col = 0; col < cb->columns; ++col) {
    snprintf(cb->headers[col].name, COLUMN_NAME_SIZE,
             "Column_%d", col + 1);
    strncpy(cb->headers[col].unit, default_unit,
            UNIT_LABEL_SIZE - 1);
  }
  clear_rows(cb, rows);
  return 1;
}


static circular_buffer* check_circular_buffer(lua_State *lua, int min_args)
{
  circular_buffer *cb = luaL_checkudata(lua, 1, mozsvc_circular_buffer);
  luaL_argcheck(lua, min_args <= lua_gettop(lua), 0,
                "incorrect number of arguments");
  return cb;
}


static int check_row(circular_buffer *cb, double ns, int advance)
{
  time_t t = (time_t)(ns / 1e9);
  t = t - (t % cb->seconds_per_row);

  int current_row = (int)(cb->current_time / cb->seconds_per_row);
  int requested_row = (int)(t / cb->seconds_per_row);
  int row_delta = requested_row - current_row;
  int row = requested_row % cb->rows;

  if (row_delta > 0 && advance) {
    clear_rows(cb, row_delta);
    cb->current_time = t;
    cb->current_row = row;
  } else if (requested_row > current_row
             || abs(row_delta) >= (int)cb->rows) {
    return -1;
  }
  return row;
}


static int check_column(lua_State *lua, circular_buffer *cb, int arg)
{
  unsigned column = luaL_checkint(lua, arg);
  luaL_argcheck(lua, 1 <= column && column <= cb->columns, arg,
                "column out of range");
  --column; // make zero based
  return column;
}


static int cb_add(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 4);
  double ns = luaL_checknumber(lua, 2);
  int row = check_row(cb, ns, 1); // advance the buffer forward if necessary
  int column = check_column(lua, cb, 3);
  double value = luaL_checknumber(lua, 4);

  if (row != -1) {
    int i = (row * cb->tcolumns) + column * 2;
    double old = cb->values[i];

    if (isnan(old)) {
      cb->values[i] = value;
    } else {
      if (isnan(value)) {
        luaL_error(lua, "cannot uninitialize a value");
      }
      cb->values[i] += value;
      if (isnan(cb->values[i])) {
        luaL_error(lua, "add produced a NAN");
      }
    }
    lua_pushnumber(lua, cb->values[i]);
    if (old == cb->values[i]) return 1;

    switch (cb->headers[column].aggregation) {
    case AGGREGATION_SUM:
      if (isnan(cb->values[i + 1])) {
        cb->values[i + 1] = value;
      } else {
        cb->values[i + 1] += value;
      }
      break;
    case AGGREGATION_MIN:
    case AGGREGATION_MAX:
      cb->values[i + 1] = cb->values[i];
      break;
    default:
      // none
      break;
    }
  } else {
    lua_pushnil(lua);
  }
  return 1;
}


static int cb_get(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 3);
  int row = check_row(cb, luaL_checknumber(lua, 2), 0);
  int column = check_column(lua, cb, 3);
  lua_Integer offset = lua_tointeger(lua, lua_upvalueindex(1));

  if (row != -1) {
    lua_pushnumber(lua, cb->values[(row * cb->tcolumns) + column * 2 + offset]);
  } else {
    lua_pushnil(lua);
  }
  return 1;
}


static int cb_get_configuration(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 1);

  lua_pushnumber(lua, cb->rows);
  lua_pushnumber(lua, cb->columns);
  lua_pushnumber(lua, cb->seconds_per_row);
  return 3;
}


static int cb_set(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 4);
  double ns = luaL_checknumber(lua, 2);
  int row = check_row(cb, ns, 1); // advance the buffer forward if necessary
  int column = check_column(lua, cb, 3);
  double value = luaL_checknumber(lua, 4);

  if (row != -1) {
    int i = (row * cb->tcolumns) + column * 2;
    double old = cb->values[i];
    if (isnan(value) && !isnan(old)) {
      luaL_error(lua, "cannot uninitialize a value");
    }
    switch (cb->headers[column].aggregation) {
    case AGGREGATION_SUM:
      cb->values[i] = value;
      if (isfinite(old)) {
        value -= old;
        if (value == 0) break;
      }
      if (isnan(cb->values[i + 1])) {
        cb->values[i + 1] = value;
      } else {
        cb->values[i + 1] += value;
      }
      break;
    case AGGREGATION_MIN:
      if (isnan(old) || value < old) {
        cb->values[i] = value;
        cb->values[i + 1] = value;
      }
      break;
    case AGGREGATION_MAX:
      if (isnan(old) || value > old) {
        cb->values[i] = value;
        cb->values[i + 1] = value;
      }
      break;
    default:
      cb->values[i] = value;
      break;
    }
    lua_pushnumber(lua, cb->values[i]);
  } else {
    lua_pushnil(lua);
  }
  return 1;
}


static int cb_set_header(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 3);
  int column = check_column(lua, cb, 2);
  const char *name = luaL_checkstring(lua, 3);
  const char *unit = luaL_optstring(lua, 4, default_unit);
  cb->headers[column].aggregation = luaL_checkoption(lua, 5, "sum",
                                                     agg_methods);

  strncpy(cb->headers[column].name, name, COLUMN_NAME_SIZE - 1);
  char *n = cb->headers[column].name;
  for (int j = 0; n[j] != 0; ++j) {
    if (!isalnum(n[j])) {
      n[j] = '_';
    }
  }
  strncpy(cb->headers[column].unit, unit, UNIT_LABEL_SIZE - 1);
  n = cb->headers[column].unit;
  for (int j = 0; n[j] != 0; ++j) {
    if (n[j] != '/' && n[j] != '*' && !isalnum(n[j])) {
      n[j] = '_';
    }
  }

  lua_pushinteger(lua, column + 1); // return the 1 based Lua column
  return 1;
}


static int cb_get_header(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 2);
  int column = check_column(lua, cb, 2);

  lua_pushstring(lua, cb->headers[column].name);
  lua_pushstring(lua, cb->headers[column].unit);
  lua_pushstring(lua, agg_methods[cb->headers[column].aggregation]);
  return 3;
}


static int cb_get_range(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 2);
  int column = check_column(lua, cb, 2);
  lua_Integer offset = lua_tointeger(lua, lua_upvalueindex(1));

  // optional range arguments
  double start_ns = luaL_optnumber(lua, 3, get_start_time(cb) * 1e9);
  double end_ns = luaL_optnumber(lua, 4, cb->current_time * 1e9);
  luaL_argcheck(lua, end_ns >= start_ns, 4, "end must be >= start");

  int start_row = check_row(cb, start_ns, 0);
  int end_row = check_row(cb, end_ns, 0);
  if (-1 == start_row || -1 == end_row) {
    lua_pushnil(lua);
    return 1;
  }

  lua_newtable(lua);
  int row = start_row;
  int i = 0;
  do {
    if (row == (int)cb->rows) {
      row = 0;
    }
    lua_pushnumber(lua, cb->values[(row * cb->tcolumns) + column * 2 + offset]);
    lua_rawseti(lua, -2, ++i);
  } while (row++ != end_row);

  return 1;
}


static int cb_current_time(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 0);
  lua_pushnumber(lua, cb->current_time * 1e9);
  return 1; // return the current time
}


static int cb_version(lua_State *lua)
{
  lua_pushstring(lua, DIST_VERSION);
  return 1;
}


#ifdef LUA_SANDBOX
static void escape_annotation(lua_State *lua, const char *anno)
{
  luaL_Buffer b;
  luaL_buffinit(lua, &b);
  for (int i = 0; anno[i]; ++i) {
    switch (anno[i]) {
    case '\\':
    case '"':
    case '/':
      luaL_addchar(&b, '\\');
      luaL_addchar(&b, anno[i]);
      break;
    case '\b':
      luaL_addstring(&b, "\\b");
      break;
    case '\t':
      luaL_addstring(&b, "\\t");
      break;
    case '\n':
      luaL_addstring(&b, "\\n");
      break;
    case '\f':
      luaL_addstring(&b, "\\f");
      break;
    case '\r':
      luaL_addstring(&b, "\\r");
      break;
    default:
      if (isprint(anno[i])) {
        luaL_addchar(&b, anno[i]);
      } else {
        luaL_addchar(&b, ' ');
      }
    }
  }
  luaL_pushresult(&b);
}


static int cb_annotate(lua_State *lua)
{
  static const char *atypes[] = { "info", "alert", NULL };

  circular_buffer *cb = check_circular_buffer(lua, 5);
  double ns = luaL_checknumber(lua, 2);
  int row = check_row(cb, ns, 0);
  int column = check_column(lua, cb, 3);
  int atidx = luaL_checkoption(lua, 4, NULL, atypes);
  const char *annotation = luaL_checkstring(lua, 5);
  int delta = 1;
  switch (lua_type(lua, 6)) {
  case LUA_TNONE:
  case LUA_TNIL:
    break;
  case LUA_TBOOLEAN:
    delta = lua_toboolean(lua, 6);
    break;
  default:
    luaL_argerror(lua, 6, "delta must be boolean");
    break;
  }
  if (row == -1) {return 0;}

  time_t t = (time_t)(ns / 1e9);
  t = t - (t % cb->seconds_per_row);
  lua_getglobal(lua, mozsvc_circular_buffer_table);
  if (lua_istable(lua, -1)) {
    if (cb->ref == LUA_NOREF) {
      lua_newtable(lua);
      cb->ref = luaL_ref(lua, -2);
    }
    // get the annotation ref table for this cbuf
    lua_rawgeti(lua, -1, cb->ref);
    if (!lua_istable(lua, -1)) {
      return luaL_error(lua, "Could not find the annotation ref table");
    }

    // get the annotation row table using the timestamp
    lua_rawgeti(lua, -1, (int)t);
    if (!lua_istable(lua, -1)) {
      lua_pop(lua, 1); // remove non table entry
      lua_newtable(lua);
      lua_pushvalue(lua, -1);
      lua_rawseti(lua, -3, (int)t);
    }

    // get annotation column table
    lua_rawgeti(lua, -1, column + 1);
    if (!lua_istable(lua, -1)) {
      lua_pop(lua, 1); // remove non table entry
      lua_newtable(lua);
      lua_pushvalue(lua, -1);
      lua_rawseti(lua, -3, column + 1);
    }

    // create/overwrite table values
    lua_pushstring(lua, atypes[atidx]);
    lua_setfield(lua, -2, "type");

    escape_annotation(lua, annotation);
    lua_setfield(lua, -2, "annotation");

    if (delta) {
      lua_pushboolean(lua, delta);
      lua_setfield(lua, -2, "delta");
    }

    lua_pop(lua, 3); // remove ref table, row table, column table
  } else {
    luaL_error(lua, "Could not find table %s", mozsvc_circular_buffer_table);
  }
  lua_pop(lua, 1); // remove the circular buffer table or failed nil
  return 0;
}


static int cb_format(lua_State *lua)
{
  static const char *output_types[] = { "cbuf", "cbufd", NULL };
  circular_buffer *cb = check_circular_buffer(lua, 2);
  luaL_argcheck(lua, 2 == lua_gettop(lua), 0,
                "incorrect number of arguments");

  cb->format = luaL_checkoption(lua, 2, NULL, output_types);
  lua_pop(lua, 1); // remove the format
  return 1; // return the circular buffer object
}


static void read_time_row(char **p, circular_buffer *cb)
{
  cb->current_time = (time_t)strtoll(*p, &*p, 10);
  cb->current_row = strtoul(*p, &*p, 10);
}


static int read_double(char **p, double *value)
{
  while (**p && isspace(**p)) {
    ++*p;
  }
  if (!**p) return 0;

  char *end = NULL;
#ifdef _MSC_VER
  if ((*p)[0] == 'n' && strncmp(*p, not_a_number, 3) == 0) {
    *p += 3;
    *value = NAN;
  } else if ((*p)[0] == 'i' && strncmp(*p, "inf", 3) == 0) {
    *p += 3;
    *value = INFINITY;
  } else if ((*p)[0] == '-' && strncmp(*p, "-inf", 4) == 0) {
    *p += 4;
    *value = -INFINITY;
  } else {
    *value = strtod(*p, &end);
  }
#else
  *value = strtod(*p, &end);
#endif
  if (*p == end) {
    return 0;
  }
  *p = end;
  return 1;
}


static void cbufd_fromstring(lua_State *lua,
                             circular_buffer *cb,
                             char **p)
{
  double value, ns = 0;
  size_t pos = 0;
  int row = -1;
  while (read_double(&*p, &value)) {
    if (pos == 0) { // new row, starts with a time_t
      ns = value * 1e9;
      row = check_row(cb, ns, 0);
    } else {
      if (row != -1) {
        cb->values[(row * cb->tcolumns) + (pos - 1) * 2 + 1] = value;
      }
    }
    if (pos == cb->columns) {
      pos = 0;
    } else {
      ++pos;
    }
  }
  if (pos != 0) {
    lua_pushstring(lua, "fromstring() invalid delta");
    lua_error(lua);
  }
  return;
}


static int cb_fromstring(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 2);
  const char *values = luaL_checkstring(lua, 2);

  char *p = (char *)values;
  read_time_row(&p, cb);

  size_t pos = 0;
  size_t len = cb->rows * cb->columns;
  double value;
  while (pos < len && read_double(&p, &value)) {
    cb->values[pos++ * 2] = value;
  }

  if (pos == len) {
    cbufd_fromstring(lua, cb, &p);
  } else {
    luaL_error(lua, "fromstring() too few values: %d, expected %d", pos, len);
  }
  if (read_double(&p, &value)) {
    luaL_error(lua, "fromstring() too many values, more than: %d", len);
  }
  return 0;
}

static int output_cbuf(circular_buffer *cb, lsb_output_buffer *ob)
{
  unsigned col;
  unsigned row = cb->current_row + 1;
  for (unsigned i = 0; i < cb->rows; ++i, ++row) {
    if (row >= cb->rows) row = 0;
    for (col = 0; col < cb->columns; ++col) {
      if (col != 0) {
        if (lsb_outputc(ob, '\t')) return 1;
      }
      if (lsb_outputd(ob,
                      cb->values[(row * cb->tcolumns) + col * 2])) {
        return 1;
      }
    }
    if (lsb_outputc(ob, '\n')) return 1;
  }
  return 0;
}


static bool is_row_dirty(circular_buffer *cb, unsigned row)
{
  bool dirty = false;
  for (unsigned col = 0; col < cb->columns; ++col) {
    if (!isnan(cb->values[(row * cb->tcolumns) + col * 2 + 1])) {
      dirty = true;
      break;
    }
  }
  return dirty;
}


static int
output_cbufd(circular_buffer *cb, lsb_output_buffer *ob, bool serialize)
{
  char sep = '\t';
  char eol = '\n';
  if (serialize) {
    sep = ' ';
    eol = ' ';
  }
  long long t = get_start_time(cb);
  unsigned col;
  unsigned row = cb->current_row + 1;
  for (unsigned i = 0; i < cb->rows; ++i, ++row) {
    if (row >= cb->rows) {
      row = 0;
    }
    if (is_row_dirty(cb, row)) {
      if (lsb_outputf(ob, "%lld", t)) return 1;
      for (col = 0; col < cb->columns; ++col) {
        if (lsb_outputc(ob, sep)) return 1;
        int idx = (row * cb->tcolumns) + col * 2 + 1;
        if (lsb_outputd(ob, cb->values[idx])) return 1;
        cb->values[idx] = NAN;
      }
      if (lsb_outputc(ob, eol)) return 1;
    }
    t += cb->seconds_per_row;
  }
  return 0;
}


static int
output_annotations(lua_State *lua, circular_buffer *cb, lsb_output_buffer *ob,
                   const char *key)
{
  if (cb->ref == LUA_NOREF) return 0;

  lua_getglobal(lua, mozsvc_circular_buffer_table);
  if (lua_istable(lua, -1)) {
    lua_rawgeti(lua, -1, cb->ref); // get the annotation table for this cbuf
    if (!lua_istable(lua, -1)) {
      lua_pop(lua, 2); // remove value and cbuf table
      return 0;
    }
    lua_pushnil(lua);
    bool first = true;
    time_t st = get_start_time(cb);
    while (lua_next(lua, -2) != 0) {
      if (!lua_istable(lua, -1)) {
        luaL_error(lua, "Invalid annotation table value");
      }
      if (!lua_isnumber(lua, -2)) {
        luaL_error(lua, "Invalid annotation table key");
      }

      time_t ti = (time_t)lua_tointeger(lua, -2);
      if (ti < st) {
        lua_pop(lua, 1);        // remove the table value
        lua_pushvalue(lua, -1); // duplicate the key
        lua_pushnil(lua);
        lua_rawset(lua, -4);    // prune the old entry
        continue;
      }

      for (unsigned col = 1; col <= cb->columns; ++col) {
        lua_rawgeti(lua, -1, col);
        if (lua_type(lua, -1) == LUA_TTABLE) {
          lua_getfield(lua, -1, "delta");
          bool delta = lua_toboolean(lua, -1);
          lua_pop(lua, 1);

          bool output = true;
          if (!key && OUTPUT_CBUFD == cb->format) {
            if (delta) {
              lua_pushnil(lua);
              lua_setfield(lua, -2, "delta");
            } else {
              output = false;
            }
          }
          if (output) {
            lua_getfield(lua, -1, "annotation");
            const char *annotation = lua_tostring(lua, -1);
            size_t len;
            lua_getfield(lua, -2, "type");
            const char *atype = lua_tolstring(lua, -1, &len);
            if (!annotation || !atype || len == 0) {
              luaL_error(lua, "malformend annotation table");
            }
            if (key) {
              if (lsb_outputf(ob, "%s:annotate(%g, %u, \"%s\", \"%s\", %s)\n",
                              key,
                              ti * 1e9,
                              col,
                              atype,
                              annotation,
                              delta ? "true" : "false")) {
                return 1;
              }
            } else {
              if (first) {
                first = false;
              } else {
                if (lsb_outputc(ob, ',')) return 1;
              }
              if (lsb_outputf(ob, "{\"x\":%lld,"
                              "\"col\":%u,"
                              "\"shortText\":\"%c\","
                              "\"text\":\"%s\"}",
                              ti * 1000LL, col, atype[0], annotation)) {
                return 1;
              }
            }
            lua_pop(lua, 2); // remove atype and text
          }
        }
        lua_pop(lua, 1); // remove the column table
      }
      lua_pop(lua, 1); // remove the value, keep the key
    }
    lua_pop(lua, 1); // remove the annotation table
  } else {
    luaL_error(lua, "Could not find table %s", mozsvc_circular_buffer_table);
  }
  lua_pop(lua, 1); // remove the circular buffer table or failed nil
  return 0;
}


static int cb_output(lua_State *lua)
{
  lsb_output_buffer *ob = lua_touserdata(lua, -1);
  circular_buffer *cb = lua_touserdata(lua, -2);
  if (!(ob && cb)) {
    return 1;
  }

  size_t pos;
  bool has_anno = false;
  if (lsb_outputf(ob,
                  "{\"time\":%lld,\"rows\":%d,\"columns\":%d,\""
                  "seconds_per_row\":%d,\"column_info\":[",
                  (long long)get_start_time(cb),
                  cb->rows,
                  cb->columns,
                  cb->seconds_per_row)) {
    return 1;
  }

  for (unsigned col = 0; col < cb->columns; ++col) {
    if (col != 0) {
      if (lsb_outputc(ob, ',')) return 1;
    }
    if (lsb_outputf(ob, "{\"name\":\"%s\",\"unit\":\"%s\",\""
                    "aggregation\":\"%s\"}",
                    cb->headers[col].name,
                    cb->headers[col].unit,
                    agg_methods[cb->headers[col].aggregation])) {
      return 1;
    }
  }
  if (lsb_outputs(ob, "],\"annotations\":[", 17)) return 1;
  pos = ob->pos;
  if (output_annotations(lua, cb, ob, NULL)) return 1;
  if (pos != ob->pos) has_anno = true;
  if (lsb_outputs(ob, "]}\n", 3)) return 1;

  if (OUTPUT_CBUFD == cb->format) {
    pos = ob->pos;
    int rv = output_cbufd(cb, ob, false);
    if (rv == 0 && ob->pos == pos && !has_anno) {
      ob->pos = 0;
    }
    return rv;
  }
  return output_cbuf(cb, ob);
}


static int cb_serialize(lua_State *lua)
{
  lsb_output_buffer *ob = lua_touserdata(lua, -1);
  const char *key = lua_touserdata(lua, -2);
  circular_buffer *cb = lua_touserdata(lua, -3);
  if (!(ob && key && cb)) {return 1;}
  if (lsb_outputf(ob,
                  "if %s == nil then "
                  "%s = circular_buffer.new(%d, %d, %d) end\n",
                  key,
                  key,
                  cb->rows,
                  cb->columns,
                  cb->seconds_per_row)) {
    return 1;
  }

  unsigned col;
  for (col = 0; col < cb->columns; ++col) {
    if (lsb_outputf(ob, "%s:set_header(%d, \"%s\", \"%s\", \"%s\")\n",
                    key,
                    col + 1,
                    cb->headers[col].name,
                    cb->headers[col].unit,
                    agg_methods[cb->headers[col].aggregation])) {
      return 1;
    }
  }

  if (lsb_outputf(ob, "%s:fromstring(\"%lld %d",
                  key,
                  (long long)cb->current_time,
                  cb->current_row)) {
    return 1;
  }

  for (unsigned row = 0; row < cb->rows; ++row) {
    for (col = 0; col < cb->columns; ++col) {
      if (lsb_outputc(ob, ' ')) return 1;
      // intentionally not serialized as Lua
      if (lsb_outputd(ob,
                      cb->values[(row * cb->tcolumns) + col * 2])) {
        return 1;
      }
    }
  }
  if (lsb_outputc(ob, ' ')) return 1;
  if (output_cbufd(cb, ob, true)) {return 1;}
  if (ob->buf[ob->pos - 1] == ' ') {
    --ob->pos;
  }
  if (lsb_outputs(ob, "\")\n", 3)) {return 1;}
  if (output_annotations(lua, cb, ob, key)) return 1;
  return 0;
}


static int cb_gc(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 0);
  if (cb->ref != LUA_NOREF) {
    lua_getglobal(lua, mozsvc_circular_buffer_table);
    if (lua_istable(lua, -1)) {
      luaL_unref(lua, -1, cb->ref);
    }
    lua_pop(lua, 1);
    cb->ref = LUA_NOREF;
  }
  return 0;
}

#else
static int cb_reset_delta(lua_State *lua)
{
  circular_buffer *cb = check_circular_buffer(lua, 0);
  for (unsigned row = 0; row < cb->rows; ++row) {
    for (unsigned col = 0; col < cb->columns; ++col) {
      int idx = (row * cb->tcolumns) + col * 2 + 1;
      cb->values[idx] = NAN;
    }
  }
  return 0;
}
#endif

static const struct luaL_reg circular_bufferlib_f[] =
{
  { "new", cb_new },
  { "version", cb_version },
  { NULL, NULL }
};

static const struct luaL_reg circular_bufferlib_m[] =
{
  { "add", cb_add },
  { "get", cb_get },
  { "get_configuration", cb_get_configuration },
  { "current_time", cb_current_time },
  { "get_header", cb_get_header },
  { "get_range", cb_get_range },
  { "set", cb_set },
  { "set_header", cb_set_header },
  // @todo add __tostring for non sandbox use

#ifdef LUA_SANDBOX
  { "annotate", cb_annotate },
  { "format", cb_format },
  { "fromstring", cb_fromstring }, // used for sandbox data restoration
  { "__gc", cb_gc },
#else
  { "reset_delta", cb_reset_delta },
#endif
  { NULL, NULL }
};


int luaopen_circular_buffer(lua_State *lua)
{
#ifdef LUA_SANDBOX
  lua_newtable(lua);
  lsb_add_serialize_function(lua, cb_serialize);
  lsb_add_output_function(lua, cb_output);
  lua_replace(lua, LUA_ENVIRONINDEX);
#endif
  luaL_newmetatable(lua, mozsvc_circular_buffer);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, circular_bufferlib_m);

  lua_pushinteger(lua, 1); // offset to allow reuse of cb_get with deltas
  lua_pushcclosure(lua, cb_get, 1);
  lua_setfield(lua, -2, "get_delta");

  lua_pushinteger(lua, 1);  // offset to allow reuse of cb_get_range with deltas
  lua_pushcclosure(lua, cb_get_range, 1);
  lua_setfield(lua, -2, "get_range_delta");

  luaL_register(lua, mozsvc_circular_buffer_table, circular_bufferlib_f);
  return 1;
}
