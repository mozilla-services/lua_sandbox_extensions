/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua AWS Kinesis wrapper implementation @file */

extern "C"
{
#include "lauxlib.h"
#include "lua.h"

#ifdef LUA_SANDBOX
#include <luasandbox.h>
#include <luasandbox/error.h>
#include <luasandbox/util/heka_message.h>
#endif

int luaopen_aws_kinesis(lua_State *lua);
}

#include <aws/core/Aws.h>
#include <aws/core/auth/AWSCredentialsProvider.h>
#include <aws/core/auth/AWSCredentialsProviderChain.h>
#include <aws/core/utils/Outcome.h>
#include <aws/core/utils/memory/stl/AWSAllocator.h>
#include <aws/core/utils/memory/stl/AWSMap.h>
#include <aws/core/utils/memory/stl/AWSString.h>
#include <aws/core/utils/memory/stl/AWSStringStream.h>
#include <aws/core/utils/memory/stl/AWSVector.h>
#include <aws/core/client/ClientConfiguration.h>
#include <aws/core/utils/DateTime.h>
#include <aws/kinesis/model/DescribeStreamRequest.h>
#include <aws/kinesis/model/GetRecordsRequest.h>
#include <aws/kinesis/model/GetShardIteratorRequest.h>
#include <aws/kinesis/model/PutRecordRequest.h>
#include <aws/kinesis/KinesisClient.h>
#include <aws/monitoring/CloudWatchClient.h>
#include <aws/monitoring/model/PutMetricDataRequest.h>
#include <chrono>
#include <ctime>
#include <thread>

static const char *mt_simple_consumer = "mozsvc.aws.kinesis.simple_consumer";
static const char *mt_simple_producer = "mozsvc.aws.kinesis.simple_producer";
static const char *cred_types[] = { "CHAIN", "INSTANCE", NULL };
static char hostname[256] = { 0 };
static const std::chrono::milliseconds one_second(1000);

namespace ath = Aws::Auth;
namespace cw  = Aws::CloudWatch;
namespace kin = Aws::Kinesis;

typedef struct shard {
  Aws::String it;         // current shard iterator
  Aws::String sequenceId; // last sequenceId read
  std::chrono::steady_clock::time_point next_request; // used to throttle requests
  long long ms_behind;
  bool active;            // pruning flag
} shard;

typedef struct simple_consumer
{
  cw::CloudWatchClient          *cwc;
  kin::KinesisClient            *client;
  Aws::String                   *streamName;
  Aws::Map<Aws::String, shard>  *shards;
  Aws::Map<Aws::String, shard>::iterator *it;
#ifdef LUA_SANDBOX
  const lsb_logger *logger;
#endif
  kin::Model::ShardIteratorType itType;
  time_t                        itTime;
  time_t                        refresh;
  time_t                        report;
} simple_consumer;

typedef struct simple_producer
{
  kin::KinesisClient            *client;
  Aws::String                   *streamName;
#ifdef LUA_SANDBOX
  const lsb_logger *logger;
#endif
} simple_producer;


static void log_error(simple_consumer *sc, const char *comp, int level, int ec, const Aws::String &em)
{
#ifdef LUA_SANDBOX
  if (sc->logger->cb) {
    sc->logger->cb(sc->logger->context, comp, level, "error: %d message: %s", ec, em.c_str());
  }
#else
  std::cerr << "component: " << comp << " error: " <<  ec << " message: " << em << std::endl;
#endif
}

static void load_string(lua_State *lua, int idx, const char *key, Aws::String &v)
{
  lua_getfield(lua, idx, key);
  const char *s = lua_tostring(lua, -1);
  if (s) v = s;
  lua_pop(lua, 1);
}


static void load_boolean(lua_State *lua, int idx, const char *key, bool &v)
{
  lua_getfield(lua, idx, key);
  if (lua_type(lua, -1) == LUA_TBOOLEAN) {
    v = lua_toboolean(lua, -1);
  }
  lua_pop(lua, 1);
}


static void load_unsigned(lua_State *lua, int idx, const char *key, unsigned &v)
{
  lua_getfield(lua, idx, key);
  if (lua_type(lua, -1) == LUA_TNUMBER) {
    v = static_cast<unsigned>(lua_tonumber(lua, -1));
  }
  lua_pop(lua, 1);
}


static void load_long(lua_State *lua, int idx, const char *key, long &v)
{
  lua_getfield(lua, idx, key);
  if (lua_type(lua, -1) == LUA_TNUMBER) {
    v = static_cast<long>(lua_tonumber(lua, -1));
  }
  lua_pop(lua, 1);
}


static void load_scheme(lua_State *lua, int idx, const char *key, Aws::Http::Scheme &v)
{
  lua_getfield(lua, idx, key);
  const char *s = lua_tostring(lua, -1);
  if (s) {
    v = Aws::Http::Scheme::HTTPS;
    if (strcmp("HTTP", s) == 0) {
      v = Aws::Http::Scheme::HTTP;
    }
  }
  lua_pop(lua, 1);
}


static void
load_configuration(lua_State *lua, int idx, Aws::Client::ClientConfiguration &conf)
{
  load_string(lua, idx, "userAgent", conf.userAgent);
  load_scheme(lua, idx, "scheme", conf.scheme);
  load_string(lua, idx, "region", conf.region);
  load_boolean(lua, idx, "useDualStack", conf.useDualStack);
  load_unsigned(lua, idx, "maxConnections", conf.maxConnections);
  load_long(lua, idx, "requestTimeoutMs", conf.requestTimeoutMs);
  load_long(lua, idx, "connectTimeoutMs", conf.connectTimeoutMs);
  load_string(lua, idx, "endpointOverride", conf.endpointOverride);
  load_scheme(lua, idx, "proxyScheme", conf.proxyScheme);
  load_string(lua, idx, "proxyHost", conf.proxyHost);
  load_unsigned(lua, idx, "proxyPort", conf.proxyPort);
  load_string(lua, idx, "proxyUserName", conf.proxyUserName);
  load_string(lua, idx, "proxyPassword", conf.proxyPassword);
  load_boolean(lua, idx, "verifySSL", conf.verifySSL);
  load_string(lua, idx, "caPath", conf.caPath);
  load_string(lua, idx, "caFile", conf.caFile);
  lua_getfield(lua, idx, "httpLibOverride");
  const char *s = lua_tostring(lua, -1);
  if (s) {
    conf.httpLibOverride = Aws::Http::TransferLibType::DEFAULT_CLIENT;
    if (strcmp("CURL_CLIENT", s) == 0) {
      conf.httpLibOverride = Aws::Http::TransferLibType::CURL_CLIENT;
    } else if (strcmp("WIN_INET_CLIENT", s) == 0) {
      conf.httpLibOverride = Aws::Http::TransferLibType::WIN_INET_CLIENT;
    } else if (strcmp("WIN_HTTP_CLIENT", s) == 0) {
      conf.httpLibOverride = Aws::Http::TransferLibType::WIN_HTTP_CLIENT;
    }
  }
  lua_pop(lua, 1);
  load_boolean(lua, idx, "followRedirects", conf.followRedirects);
}


static int parse_checkpoints(simple_consumer *sc, const char *checkpoints)
{
  const char *p = checkpoints;
  while (p && *p) {
    auto pos = strchr(p, '\t');
    if (!pos || p == pos) {return 1;}
    auto shardId = Aws::String(p, pos - p);
    p = ++pos;
    if (!p) {return 1;}

    pos = strchr(p, '\n');
    if (!pos || p == pos) {return 1;}
    auto sequenceId = Aws::String(p, pos - p);
    auto tp = std::chrono::time_point<std::chrono::steady_clock>();
    p = ++pos;
    sc->shards->insert({ shardId, { "", sequenceId, tp, 0, false } });
  }
  return 0;
}


static Aws::String
get_shard_iterator(simple_consumer *sc, const Aws::String &shardId,
                   const Aws::String &sequenceId)
{
  kin::Model::GetShardIteratorRequest sir;
  sir.SetStreamName(*sc->streamName);
  sir.SetShardId(shardId);
  sir.SetShardIteratorType(sc->itType);
  if (sc->itType == kin::Model::ShardIteratorType::AT_TIMESTAMP) {
    sir.SetTimestamp(Aws::Utils::DateTime(sc->itTime * 1000));
  }

  if (!sequenceId.empty()) {
    if (sequenceId != "*") {
      sir.SetShardIteratorType(kin::Model::ShardIteratorType::AFTER_SEQUENCE_NUMBER);
      sir.SetStartingSequenceNumber(sequenceId);
    } else {
      // there should never be an iterator request on a known closed shard
      // but the correct value is returned
      sir.SetShardIteratorType(kin::Model::ShardIteratorType::LATEST);
    }
  }

  auto outcome = sc->client->GetShardIterator(sir);
  if (!outcome.IsSuccess()) {
    auto e = outcome.GetError();
    log_error(sc, __func__, 7, (int)e.GetErrorType(), e.GetMessage());
    return Aws::String();
  }
  return outcome.GetResult().GetShardIterator();
}


static int get_shards(lua_State *lua, simple_consumer *sc, int num_retries)
{
  kin::Model::DescribeStreamRequest dsr;
  dsr.SetStreamName(*sc->streamName);
  Aws::Vector<kin::Model::Shard> shards;
  int retry_count = 0;
  do {
    auto outcome = sc->client->DescribeStream(dsr);
    if (!outcome.IsSuccess()) {
      auto e = outcome.GetError();
      switch (e.GetErrorType()) {
      case kin::KinesisErrors::THROTTLING:
      case kin::KinesisErrors::SLOW_DOWN:
      case kin::KinesisErrors::K_M_S_THROTTLING:
      case kin::KinesisErrors::LIMIT_EXCEEDED:
      case kin::KinesisErrors::PROVISIONED_THROUGHPUT_EXCEEDED:
        // retry in another second
        break;
      default:
        if (!e.ShouldRetry()) {
          lua_pushfstring(lua, "error: %d message: %s", (int)e.GetErrorType(), e.GetMessage().c_str());
          return 1;
        }
        break;
      }
      log_error(sc, __func__, 7, (int)e.GetErrorType(), e.GetMessage());
      std::this_thread::sleep_for(one_second);
      if (++retry_count > num_retries) {
        if (sc->shards->size() == 0) {
          lua_pushstring(lua, "cannot retrieve the shard list");
          return 1;
        }
        return 2;
      }
      continue;
    }
    auto &description = outcome.GetResult().GetStreamDescription();
    auto &status = description.GetStreamStatus();
    if (status != kin::Model::StreamStatus::ACTIVE &&
        status != kin::Model::StreamStatus::UPDATING) {
      lua_pushstring(lua, "stream not ready");
      return 1;
    }
    auto &vs = description.GetShards();
    shards.insert(shards.end(), vs.begin(), vs.end());
    if (description.GetHasMoreShards() && shards.size() > 0) {
      dsr.SetExclusiveStartShardId(shards[shards.size() - 1].GetShardId());
    } else {
      break;
    }
  } while (true);

  for (auto &kv:*sc->shards) {
    kv.second.active = false;
  }

  // add new and flag active shards
  for (const auto &sh: shards) {
    auto shardId = sh.GetShardId();
    auto it = sc->shards->find(shardId);
    if (it == sc->shards->end()) {
      auto sit = get_shard_iterator(sc, shardId, Aws::String());
      auto tp = std::chrono::time_point<std::chrono::steady_clock>();
      sc->shards->insert({ shardId, { sit, "", tp, 0, true } });
    } else {
      it->second.active = true;
    }
  }

  // delete_inactive shards
  auto it = sc->shards->begin();
  for (auto end = sc->shards->end(); it != end;) {
    auto cit = it++;
    if (!cit->second.active) {
      if (cit == *sc->it) {
        *sc->it = it;
      }
      sc->shards->erase(cit);
    }
  }

  if (sc->shards->size() == 0) {
    lua_pushstring(lua, "no shards available");
    return 1;
  }
  return 0;
}


static int simple_consumer_new(lua_State *lua)
{
  const char *streamName  = luaL_checkstring(lua, 1);
  auto iteratorType       = kin::Model::ShardIteratorType::TRIM_HORIZON;
  int64_t iteratorTime   = 0;
  int t = lua_type(lua, 2);
  switch (t) {
  case LUA_TSTRING:
    {
      const char *v = lua_tostring(lua, 2);
      if (strcmp(v, "TRIM_HORIZON") == 0) {
        iteratorType = kin::Model::ShardIteratorType::TRIM_HORIZON;
      } else if (strcmp(v, "LATEST") == 0) {
        iteratorType = kin::Model::ShardIteratorType::LATEST;
      } else {
        luaL_error(lua, "invalid iterator type: %s", v);
      }
    }
    break;
  case LUA_TNUMBER:
    iteratorType = kin::Model::ShardIteratorType::AT_TIMESTAMP;
    iteratorTime = static_cast<int64_t>(lua_tonumber(lua, 2));
    break;
  case LUA_TNONE:
  case LUA_TNIL:
    break;
  default:
    luaL_typerror(lua, 2, "string, number, none, nil");
    break;
  }
  const char *checkpoints = lua_tostring(lua, 3);
  Aws::Client::ClientConfiguration config;
  t = lua_type(lua, 4);
  switch (t) {
  case LUA_TTABLE:
    load_configuration(lua, 4, config);
    break;
  case LUA_TNIL:
  case LUA_TNONE:
    break;
  default:
    luaL_typerror(lua, 4, "table, none/nil");
    break;
  }
  int credType = luaL_checkoption(lua, 5, "INSTANCE", cred_types);

  simple_consumer *sc = static_cast<simple_consumer *>(lua_newuserdata(lua, sizeof*sc));
  switch (credType) {
  case 0:
    sc->cwc = new cw::CloudWatchClient(config);
    sc->client = new kin::KinesisClient(config);
    break;
  default:
    {
      auto cp = Aws::MakeShared<ath::InstanceProfileCredentialsProvider>(mt_simple_consumer);
      sc->cwc = new cw::CloudWatchClient(cp, config);
      sc->client = new kin::KinesisClient(cp, config);
    }
    break;
  }
  sc->streamName = new Aws::String(streamName);
  sc->shards = new Aws::Map<Aws::String, shard>;
  sc->it = new Aws::Map<Aws::String, shard>::iterator(sc->shards->end());
  sc->itType = static_cast<kin::Model::ShardIteratorType>(iteratorType);
  sc->itTime = iteratorTime;
  sc->refresh = time(NULL);
  sc->report = sc->refresh;
#ifdef LUA_SANDBOX
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_THIS_PTR);
  lsb_lua_sandbox *lsb = reinterpret_cast<lsb_lua_sandbox *>(lua_touserdata(lua, -1));
  lua_pop(lua, 1); // remove this ptr
  if (!lsb) {
    return luaL_error(lua, "invalid " LSB_THIS_PTR);
  }
  sc->logger = lsb_get_logger(lsb);
#endif
  luaL_getmetatable(lua, mt_simple_consumer);
  lua_setmetatable(lua, -2);

  if (!sc->streamName || !sc->cwc || !sc->client || !sc->shards || !sc->it) {
    return luaL_error(lua, "memory allocation failed");
  }

  if (parse_checkpoints(sc, checkpoints) != 0) {
    luaL_error(lua, "invalid checkpoint string");
    return 1;
  }

  // DescribeStream is rate limited to 10 requests/sec
  // This should allow all inputs to start (bandwidth wise we can only support
  // ~50 single shard streams on a single instance)
  if (get_shards(lua, sc, 10) != 0) {
    return lua_error(lua);
  }
  return 1;
}


static int simple_consumer_gc(lua_State *lua)
{
  simple_consumer *sc = static_cast<simple_consumer *>(luaL_checkudata(lua, 1, mt_simple_consumer));
  delete(sc->it);
  delete(sc->shards);
  delete(sc->streamName);
  delete(sc->client);
  delete(sc->cwc);
  return 0;
}


static int push_checkpoints(lua_State *lua, simple_consumer *sc)
{
  Aws::OStringStream buf;
  for (const auto &kv:*sc->shards) {
    if (!kv.second.sequenceId.empty()) {
      buf << kv.first << "\t" << kv.second.sequenceId << "\n";
    }
  }
  lua_pushstring(lua, buf.str().c_str());
  return 0;
}


static shard* get_next_shard(simple_consumer *sc)
{
  static const std::chrono::milliseconds zero_seconds(0);
  static const std::chrono::milliseconds minus_one(-1);
  auto begin    = sc->shards->begin();
  auto end      = sc->shards->end();
  shard *sh     = nullptr;
  shard *tsh    = nullptr;
  size_t items  = sc->shards->size();
  size_t cnt    = 0;
  while (cnt++ < items && !sh) {
    if (*sc->it == end || ++(*sc->it) == end) *sc->it = begin;
    tsh = &(*sc->it)->second;
    if (tsh->sequenceId != "*") {
      auto delta = std::chrono::duration_cast<std::chrono::milliseconds>(
          std::chrono::steady_clock::now() - tsh->next_request);
      if (tsh->it.empty()) {
        if (delta >= zero_seconds) {
          tsh->it = get_shard_iterator(sc, (*sc->it)->first, tsh->sequenceId);
          if (tsh->it.empty()) {
            tsh->next_request = std::chrono::steady_clock::now() + one_second;
            continue;
          }
        } else {
          continue;
        }
      }
      if (delta >= minus_one) {
        if (delta < zero_seconds) {
          std::this_thread::sleep_for(zero_seconds - delta);
        }
        sh = tsh;
      }
    }
  }
  return sh;
}


static int report_mills_behind(simple_consumer *sc)
{
  auto pmdr = cw::Model::PutMetricDataRequest();
  pmdr.SetNamespace("lsbe.kinesis.client-" + *sc->streamName);

  auto datum = cw::Model::MetricDatum();
  datum.SetMetricName("MillisBehindLatest");
  datum.SetUnit(cw::Model::StandardUnit::Milliseconds);

  Aws::Vector<cw::Model::Dimension> dims(3);
  dims[0].SetName("Operation");
  dims[0].SetValue("ProcessTask");
  dims[1].SetName("ShardId");
  dims[2].SetName("WorkerIdentifier");
  dims[2].SetValue(hostname);

  // mimic the KCL and don't send more than 20 metrics at once. The actual
  // limitation is 40KB but there is no easy way to get an accurate size of
  // the output.
  if (sc->shards->size() <= 20) {
    for (const auto &kv:*sc->shards) {
      dims[1].SetValue(kv.first);
      datum.SetValue(static_cast<double>(kv.second.ms_behind));
      datum.SetDimensions(dims);
      pmdr.AddMetricData(datum);
    }
  } else {
    Aws::Vector<cw::Model::MetricDatum> vmd;
    for (const auto &kv:*sc->shards) {
      dims[1].SetValue(kv.first);
      datum.SetValue(static_cast<double>(kv.second.ms_behind));
      datum.SetDimensions(dims);
      vmd.push_back(datum);
      if (vmd.size() == 20) {
        pmdr.SetMetricData(vmd);
        auto outcome = sc->cwc->PutMetricData(pmdr);
        if (!outcome.IsSuccess()) {
          auto e = outcome.GetError();
          log_error(sc, __func__, 7, (int)e.GetErrorType(), e.GetMessage());
          return 1;
        }
        vmd.clear();
      }
    }
    pmdr.SetMetricData(vmd);
  }

  if (pmdr.GetMetricData().size() > 0) {
    auto outcome = sc->cwc->PutMetricData(pmdr);
    if (!outcome.IsSuccess()) {
      auto e = outcome.GetError();
      log_error(sc, __func__, 7, (int)e.GetErrorType(), e.GetMessage());
      return 1;
    }
  }
  return 0;
}


static int simple_receive(lua_State *lua)
{
  simple_consumer *sc = static_cast<simple_consumer *>(luaL_checkudata(lua, 1, mt_simple_consumer));

  time_t t = time(NULL);
  if (t < sc->report || sc->report + 20LL < t) { // monitoring expects at least one report a minute
    if (report_mills_behind(sc) == 0) {
      sc->report = t;
    } else {
      sc->report += 1;
    }
  }

  if (t < sc->refresh || sc->refresh + 3600LL < t) { // prune deleted shards
    switch (get_shards(lua, sc, 0)) {
    case 0:
      sc->refresh = t;
      break;
    case 2:
      sc->refresh += 1;
      break;
    default:
      sc->refresh += 1; // throttle if the error is trapped and this is called repeatedly
      return lua_error(lua);
    }
  }

  shard *sh = get_next_shard(sc);
  if (!sh) {
    std::this_thread::sleep_for(one_second);
    lua_newtable(lua);
    return 1;
  }

  bool fatal = false;
  {
    kin::Model::GetRecordsRequest rr;
    rr.SetShardIterator(sh->it);
    auto outcome = sc->client->GetRecords(rr);
    if (outcome.IsSuccess()) {
      auto r = outcome.GetResult();
      sh->ms_behind = r.GetMillisBehindLatest();
      sh->it = r.GetNextShardIterator();
      if (sh->it.empty()) {
        sh->sequenceId = "*";
        sh->ms_behind = 0;
        sc->refresh = 0;
      }

      auto &recs = r.GetRecords();
      size_t nrecs = recs.size();
      if (nrecs == 0) {
        lua_newtable(lua);
        sh->next_request = std::chrono::steady_clock::now() + one_second;
        return 1;
      }

      if (!sh->it.empty()) sh->sequenceId = recs[nrecs - 1].GetSequenceNumber();

      lua_createtable(lua, nrecs, 0);
      int n = 0;
      size_t bytes = 0;
      for (auto &r : recs) {
        auto data = r.GetData();
        auto len = data.GetLength();
        bytes += len;
        lua_pushlstring(lua, reinterpret_cast<const char *>(data.GetUnderlyingData()), len);
        lua_rawseti(lua, -2, ++n);
      }
      push_checkpoints(lua, sc);
      auto units = (bytes / (1024 * 1024 * 2)) + 1;
      if (units > 5) units = 5;
      sh->next_request = std::chrono::steady_clock::now() + (one_second * units);
      return 2;
    } else {
      auto e = outcome.GetError();
      switch (e.GetErrorType()) {
      case kin::KinesisErrors::EXPIRED_ITERATOR:
        sh->it.clear();
        break;
      case kin::KinesisErrors::THROTTLING:
      case kin::KinesisErrors::SLOW_DOWN:
      case kin::KinesisErrors::K_M_S_THROTTLING:
      case kin::KinesisErrors::LIMIT_EXCEEDED:
      case kin::KinesisErrors::PROVISIONED_THROUGHPUT_EXCEEDED:
        // just retry in another second
        break;
      default:
        if (!e.ShouldRetry()) {
          lua_pushfstring(lua, "fatal: %d message: %s", (int)e.GetErrorType(), e.GetMessage().c_str());
          fatal = true;
        }
        break;
      }
      if (!fatal) {
        log_error(sc, __func__, 7, (int)e.GetErrorType(), e.GetMessage());
        lua_newtable(lua);
        sh->next_request = std::chrono::steady_clock::now() + one_second;
        return 1;
      }
    }
  }

  sh->next_request = std::chrono::steady_clock::now() + one_second;
  return lua_error(lua);
}


static int simple_producer_new(lua_State *lua)
{
  Aws::Client::ClientConfiguration config;
  switch (lua_type(lua, 1)) {
  case LUA_TTABLE:
    load_configuration(lua, 1, config);
    break;
  case LUA_TNIL:
  case LUA_TNONE:
    break;
  default:
    luaL_typerror(lua, 1, "table, none/nil");
    break;
  }
  int credType = luaL_checkoption(lua, 2, "INSTANCE", cred_types);

  simple_producer *sp = static_cast<simple_producer *>(lua_newuserdata(lua, sizeof*sp));
  switch (credType) {
  case 0:
    sp->client = new kin::KinesisClient(config);
    break;
  default:
    {
      auto cp = Aws::MakeShared<ath::InstanceProfileCredentialsProvider>(mt_simple_producer);
      sp->client = new kin::KinesisClient(cp, config);
    }
    break;
  }
#ifdef LUA_SANDBOX
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_THIS_PTR);
  lsb_lua_sandbox *lsb = reinterpret_cast<lsb_lua_sandbox *>(lua_touserdata(lua, -1));
  lua_pop(lua, 1); // remove this ptr
  if (!lsb) {
    return luaL_error(lua, "invalid " LSB_THIS_PTR);
  }
  sp->logger = lsb_get_logger(lsb);
#endif
  luaL_getmetatable(lua, mt_simple_producer);
  lua_setmetatable(lua, -2);

  if (!sp->client) {
    return luaL_error(lua, "memory allocation failed");
  }
  return 1;
}


static int simple_producer_gc(lua_State *lua)
{
  simple_producer *sp = static_cast<simple_producer *>(luaL_checkudata(lua, 1, mt_simple_producer));
  delete(sp->client);
  return 0;
}


static int simple_send(lua_State *lua)
{
  simple_producer *sp = static_cast<simple_producer *>(luaL_checkudata(lua, 1, mt_simple_producer));

  size_t len = 0;
  auto streamName = luaL_checkstring(lua, 2);
  auto data       = reinterpret_cast<const unsigned char *>(luaL_checklstring(lua, 3, &len));
  auto *key       = luaL_checkstring(lua, 4);

  kin::Model::PutRecordRequest rr;
  rr.SetStreamName(streamName);
  rr.SetData(Aws::Utils::ByteBuffer(data, len));
  rr.SetPartitionKey(key);
  auto outcome = sp->client->PutRecord(rr);
  if (outcome.IsSuccess()) {
    lua_pushnil(lua);
  } else {
    auto e = outcome.GetError();
    lua_pushfstring(lua, "error: %d message: %s", (int)e.GetErrorType(), e.GetMessage().c_str());
  }
  return 1;
}


static const struct luaL_reg lib_f[] = {
  { "simple_consumer", simple_consumer_new },
  { "simple_producer", simple_producer_new },
  { NULL, NULL }
};


static const struct luaL_reg simple_consumer_lib_m[] = {
  { "receive", simple_receive },
  { "__gc", simple_consumer_gc },
  { NULL, NULL }
};

static const struct luaL_reg simple_producer_lib_m[] = {
  { "send", simple_send },
  { "__gc", simple_producer_gc },
  { NULL, NULL }
};


int luaopen_aws_kinesis(lua_State *lua)
{
  Aws::SDKOptions sdk_options;
  Aws::InitAPI(sdk_options);

  luaL_newmetatable(lua, mt_simple_consumer);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, simple_consumer_lib_m);
  lua_pop(lua, 1);

  luaL_newmetatable(lua, mt_simple_producer);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, simple_producer_lib_m);
  lua_pop(lua, 1);

  luaL_register(lua, "aws.kinesis", lib_f);

  // if necessary flag the parent table as non-data for preservation
  lua_getglobal(lua, "aws");
  if (lua_getmetatable(lua, -1) == 0) {
    lua_newtable(lua);
    lua_setmetatable(lua, -2);
  } else {
    lua_pop(lua, 1);
  }
  lua_pop(lua, 1);

#ifdef LUA_SANDBOX
  lua_getfield(lua, LUA_REGISTRYINDEX, LSB_CONFIG_TABLE);
  if (lua_type(lua, -1) == LUA_TTABLE) {
    lua_getfield(lua, -1, LSB_HOSTNAME);
    if (lua_type(lua, -1) == LUA_TSTRING) {
      size_t len;
      const char *hn = lua_tolstring(lua, -1, &len);
      strncpy(hostname, hn, sizeof(hostname) - 1);
    }
    lua_pop(lua, 1); // remove LSB_HOSTNAME
  }
  lua_pop(lua, 1); // remove LSB_CONFIG_TABLE
#endif

  return 1;
}
