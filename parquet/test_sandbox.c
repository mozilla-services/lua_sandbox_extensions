/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief parquet luasandox tests @file */

#include <stdio.h>
#include <stdlib.h>

#include <luasandbox/heka/sandbox.h>
#include <luasandbox/test/mu_test.h>
#include <luasandbox/test/sandbox.h>

#include "test_module.h"

char *e = NULL;

void dlog(void *context, const char *component, int level, const char *fmt, ...)
{
  (void)context;
  va_list args;
  va_start(args, fmt);
  fprintf(stderr, "%lld [%d] %s ", (long long)time(NULL), level,
          component ? component : "unnamed");
  vfprintf(stderr, fmt, args);
  fwrite("\n", 1, 1, stderr);
  va_end(args);
}
static lsb_logger logger = { .context = NULL, .cb = dlog };


static int ucp(void *parent, void *sequence_id)
{
  (void)parent;
  (void)sequence_id;
  return 0;
}


static char* test_parquet()
{
  lsb_heka_sandbox *hsb;
  hsb = lsb_heka_create_output(NULL, "test.lua", NULL,
                               TEST_MODULE_PATH "log_level = 7\n",
                               &logger, ucp);
  mu_assert(hsb, "lsb_heka_create_input failed");
  e = lsb_heka_destroy_sandbox(hsb);
  return NULL;
}


static char* test_parquet_min()
{
  static char pb[] = "\x0a\x10" "abcdefghijklmnop" "\x10\x80\x94\xeb\xdc\x03";
  lsb_heka_message m;
  mu_assert(!lsb_init_heka_message(&m, 1), "failed to init message");
  mu_assert(lsb_decode_heka_message(&m, pb, sizeof pb - 1, NULL), "failed");
  lsb_heka_sandbox *hsb;
  hsb = lsb_heka_create_output(NULL, "test_sandbox_min.lua", NULL,
                               TEST_MODULE_PATH "log_level = 7\n",
                               &logger, ucp);
  mu_assert(hsb, "lsb_heka_create_output failed");
  mu_assert(0 == lsb_heka_pm_output(hsb, &m, (void *)1, false), "err: %s",
            lsb_heka_get_error(hsb));
  e = lsb_heka_destroy_sandbox(hsb);
  mu_assert(!e, "%s", e);
  lsb_free_heka_message(&m);
  return NULL;
}


static char* test_parquet_full()
{
/*
local msg = {
    Uuid = "abcdefghijklmnop",
    Timestamp = 1e9,
    Logger = "logger",
    Hostname = "hostname",
    Type = "type",
    Payload = "payload",
    EnvVersion = "envversion",
    Pid = 1234,
    Severity = 6,
    Fields = {
        bool = true,
        bools = {false, true},
        int = {value = 1, value_type = 2},
        ints = {value = {2,3}, value_type = 2},
        int64 = {value = 101, value_type = 2},
        int64s = {value = {102, 103}, value_type = 2},
        float = 1.1,
        floats = {1.2, 1.3},
        double = 101.1,
        doubles = {102.1, 103.1},
        binary = "s1",
        binaries = {"s2", "s3"},
        flba = "12345",
        flbas = {"23456", "34567"},
        int96 = "0123456789AB",
        int96s = {"123456789ABC", "23456789ABCD"},
    }
}
*/
  static char pb[] = "\x0A\x10\x61\x62\x63\x64\x65\x66\x67\x68\x69\x6A\x6B\x6C\x6D\x6E\x6F\x70\x10\x80\x94\xEB\xDC\x03\x1A\x04\x74\x79\x70\x65\x22\x06\x6C\x6F\x67\x67\x65\x72\x28\x06\x32\x07\x70\x61\x79\x6C\x6F\x61\x64\x3A\x0A\x65\x6E\x76\x76\x65\x72\x73\x69\x6F\x6E\x40\xD2\x09\x4A\x08\x68\x6F\x73\x74\x6E\x61\x6D\x65\x52\x0A\x0A\x04\x62\x6F\x6F\x6C\x10\x04\x40\x01\x52\x0E\x0A\x06\x69\x6E\x74\x36\x34\x73\x10\x02\x32\x02\x66\x67\x52\x1C\x0A\x06\x66\x6C\x6F\x61\x74\x73\x10\x03\x3A\x10\x33\x33\x33\x33\x33\x33\xF3\x3F\xCD\xCC\xCC\xCC\xCC\xCC\xF4\x3F\x52\x1D\x0A\x07\x64\x6F\x75\x62\x6C\x65\x73\x10\x03\x3A\x10\x66\x66\x66\x66\x66\x86\x59\x40\x66\x66\x66\x66\x66\xC6\x59\x40\x52\x0B\x0A\x05\x69\x6E\x74\x36\x34\x10\x02\x30\x65\x52\x0C\x0A\x06\x62\x69\x6E\x61\x72\x79\x22\x02\x73\x31\x52\x0C\x0A\x04\x69\x6E\x74\x73\x10\x02\x32\x02\x02\x03\x52\x15\x0A\x05\x66\x6C\x62\x61\x73\x22\x05\x32\x33\x34\x35\x36\x22\x05\x33\x34\x35\x36\x37\x52\x13\x0A\x06\x64\x6F\x75\x62\x6C\x65\x10\x03\x39\x66\x66\x66\x66\x66\x46\x59\x40\x52\x0D\x0A\x04\x66\x6C\x62\x61\x22\x05\x31\x32\x33\x34\x35\x52\x0D\x0A\x05\x62\x6F\x6F\x6C\x73\x10\x04\x42\x02\x00\x01\x52\x12\x0A\x08\x62\x69\x6E\x61\x72\x69\x65\x73\x22\x02\x73\x32\x22\x02\x73\x33\x52\x12\x0A\x05\x66\x6C\x6F\x61\x74\x10\x03\x39\x9A\x99\x99\x99\x99\x99\xF1\x3F\x52\x15\x0A\x05\x69\x6E\x74\x39\x36\x22\x0C\x30\x31\x32\x33\x34\x35\x36\x37\x38\x39\x41\x42\x52\x24\x0A\x06\x69\x6E\x74\x39\x36\x73\x22\x0C\x31\x32\x33\x34\x35\x36\x37\x38\x39\x41\x42\x43\x22\x0C\x32\x33\x34\x35\x36\x37\x38\x39\x41\x42\x43\x44\x52\x09\x0A\x03\x69\x6E\x74\x10\x02\x30\x01";

  lsb_heka_message m;
  mu_assert(!lsb_init_heka_message(&m, 1), "failed to init message");
  mu_assert(lsb_decode_heka_message(&m, pb, sizeof pb - 1, NULL), "failed");
  lsb_heka_sandbox *hsb;
  hsb = lsb_heka_create_output(NULL, "test_sandbox_full.lua", NULL,
                               TEST_MODULE_PATH "log_level = 7\n",
                               &logger, ucp);
  mu_assert(hsb, "lsb_heka_create_output failed");
  mu_assert(0 == lsb_heka_pm_output(hsb, &m, (void *)1, false), "err: %s",
            lsb_heka_get_error(hsb));
  e = lsb_heka_destroy_sandbox(hsb);
  mu_assert(!e, "%s", e);
  lsb_free_heka_message(&m);
  return NULL;
}



static char* all_tests()
{
  mu_run_test(test_parquet);
  mu_run_test(test_parquet_min);
  mu_run_test(test_parquet_full);
  return NULL;
}


int main()
{
  char *result = all_tests();
  if (result) {
    printf("%s\n", result);
  } else {
    printf("ALL TESTS PASSED\n");
  }
  printf("Tests run: %d\n", mu_tests_run);
  free(e);

  return result != 0;
}
