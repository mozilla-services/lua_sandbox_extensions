/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief rjson luasandbox tests @file */

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


static int iim(void *parent, const char *pb, size_t pb_len, double cp_numeric,
               const char *cp_string)
{
  (void)parent;
  (void)pb;
  (void)pb_len;
  (void)cp_numeric;
  (void)cp_string;
  return 0;
}


static char* test_rjson()
{
  lsb_heka_sandbox *hsb;
  hsb = lsb_heka_create_input(NULL, "test.lua", NULL,
                              "max_message_size = 8196\n"
                              TEST_MODULE_PATH,
                              &logger, iim);
  mu_assert(hsb, "lsb_heka_create_input failed");
  e = lsb_heka_destroy_sandbox(hsb);
  return NULL;
}


static char* test_rjson_sandbox()
{
  lsb_heka_sandbox *hsb;
  hsb = lsb_heka_create_input(NULL, "test_sandbox.lua", NULL,
#ifdef HAVE_ZLIB
                              "have_zlib = true\n"
#endif
                              "max_message_size = 8196\n"
                              TEST_MODULE_PATH,
                              &logger, iim);
  lsb_heka_stats stats = lsb_heka_get_stats(hsb);
  mu_assert(0 < stats.ext_mem_max, "received %llu", stats.ext_mem_max);
  mu_assert(hsb, "lsb_heka_create_input failed");
  e = lsb_heka_destroy_sandbox(hsb);
  return NULL;
}


static char* all_tests()
{
  mu_run_test(test_rjson);
  mu_run_test(test_rjson_sandbox);
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
