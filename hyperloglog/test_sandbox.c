/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <luasandbox/heka/sandbox.h>
#include <luasandbox/test/mu_test.h>
#include <luasandbox/test/sandbox.h>

#include "test_module.h"

char *e = NULL;

static char* test_core()
{
  lsb_lua_sandbox *sb = lsb_create(NULL, "test.lua", TEST_MODULE_PATH
                                   "instruction_limit = 0\n", &lsb_test_logger);
  mu_assert(sb, "lsb_create() received: NULL");

  lsb_err_value ret = lsb_init(sb, NULL);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  return NULL;
}


static char* test_sandbox()
{
  const char *output_file = "hyperloglog.preserve";

  remove(output_file);
  lsb_lua_sandbox *sb = lsb_create(NULL, "test_sandbox.lua", TEST_MODULE_PATH,
                                   NULL);
  mu_assert(sb, "lsb_create() received: NULL");

  lsb_err_value ret = lsb_init(sb, output_file);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");


  for (int i = 0; i < 100000; ++i) {
    int result = lsb_test_process(sb, i);
    mu_assert(result == 0, "process() received: %d %s", result,
              lsb_get_error(sb));
  }

  int result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp("100070", lsb_test_output) == 0, "test: initial received: %s",
            lsb_test_output); // count should remain the same

  result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp("100070", lsb_test_output) == 0, "test: cache received: %s",
            lsb_test_output); // count should remain the same

  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);

  // re-load to test the preserved data
  sb = lsb_create(NULL, "test_sandbox.lua", TEST_MODULE_PATH, NULL);
  mu_assert(sb, "lsb_create() received: NULL");

  ret = lsb_init(sb, output_file);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp("100070", lsb_test_output) == 0, "test: reload received: %s",
            lsb_test_output); // count should remain the same

  for (int i = 0; i < 100000; ++i) {
    result = lsb_test_process(sb, i);
    mu_assert(result == 0, "process() received: %d %s", result,
              lsb_get_error(sb));
  }
  result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp("100070", lsb_test_output) == 0,
            "test: data replay received: %s", lsb_test_output);
  // count should remain the same

  // test clear
  lsb_test_report(sb, 99);
  lsb_test_report(sb, 0);
  mu_assert(strcmp("0", lsb_test_output) == 0, "test: clear received: %s",
            lsb_test_output);

  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  return NULL;
}


static char* benchmark()
{
  int iter = 1000000;

  lsb_lua_sandbox *sb = lsb_create(NULL, "test_sandbox.lua", TEST_MODULE_PATH,
                                   NULL);
  mu_assert(sb, "lsb_create() received: NULL");
  lsb_err_value ret = lsb_init(sb, NULL);
  mu_assert(!ret, "lsb_init() received: %s", ret);
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  clock_t t = clock();
  for (int x = 0; x < iter; ++x) {
    mu_assert(0 == lsb_test_process(sb, x), "%s", lsb_get_error(sb)); // test add speed
  }
  t = clock() - t;
  lsb_test_report(sb, 0);
  mu_assert(strcmp("1006268", lsb_test_output) == 0, "received: %s", lsb_test_output);
  mu_assert(lsb_get_state(sb) == LSB_RUNNING, "benchmark failed %s",
            lsb_get_error(sb));
  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  printf("benchmark %g seconds\n", ((double)t) / CLOCKS_PER_SEC / iter);
  return NULL;
}


static char* all_tests()
{
  mu_run_test(test_core);
  mu_run_test(test_sandbox);
  mu_run_test(benchmark);
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
