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
  lsb_lua_sandbox *sb =
      lsb_create(NULL, "test.lua", TEST_MODULE_PATH
                 "instruction_limit = 0\n", NULL);
  mu_assert(sb, "lsb_create() received: NULL");

  lsb_err_value ret = lsb_init(sb, NULL);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  return NULL;
}


static char* test_sandbox()
{
  const char *output_file = "cuckoo_filter.preserve";
  const char *tests[] = {
    "1",
    "2",
    "3",
    NULL
  };

  remove(output_file);
  lsb_lua_sandbox *sb = lsb_create(NULL, "test_sandbox.lua", TEST_MODULE_PATH,
                                   NULL);
  mu_assert(sb, "lsb_create() received: NULL");

  lsb_err_value ret = lsb_init(sb, output_file);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  int i = 0;
  for (; tests[i]; ++i) {
    int result = lsb_test_process(sb, i);
    mu_assert(result == 0, "process() received: %d %s", result,
              lsb_get_error(sb));
    result = lsb_test_report(sb, 0);
    mu_assert(result == 0, "report() received: %d", result);
    mu_assert(strcmp(tests[i], lsb_test_output) == 0, "test: %d received: %s",
              i, lsb_test_output);
  }

  int result = lsb_test_process(sb, 0);
  mu_assert(result == 0, "process() received: %d %s", result,
            lsb_get_error(sb));
  result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp(tests[i - 1], lsb_test_output) == 0, "test: %d received: %s",
            i, lsb_test_output); // count should remain the same

  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);

  // re-load to test the preserved data
  sb = lsb_create(NULL, "test_sandbox.lua", TEST_MODULE_PATH, NULL);
  mu_assert(sb, "lsb_create() received: NULL");

  ret = lsb_init(sb, output_file);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  lsb_test_report(sb, 0);
  mu_assert(strcmp("3", lsb_test_output) == 0, "test: count received: %s",
            lsb_test_output);

  for (int i = 0; tests[i]; ++i) {
    result = lsb_test_process(sb, i);
    mu_assert(result == 0, "process() received: %d %s", result,
              lsb_get_error(sb));
  }
  result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp(tests[i - 1], lsb_test_output) == 0, "test: %d received: %s",
            i, lsb_test_output); // count should remain the same

  // test deletion
  lsb_test_report(sb, 98);
  mu_assert(strcmp("2", lsb_test_output) == 0, "test: delete received: %s",
            lsb_test_output);
  // tst clear
  lsb_test_report(sb, 99);
  mu_assert(strcmp("0", lsb_test_output) == 0, "test: clear received: %s",
            lsb_test_output);

  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  return NULL;}


static char* benchmark()
{
  int iter = 1000000;

  lsb_lua_sandbox *sb = lsb_create(NULL, "benchmark.lua", TEST_MODULE_PATH,
                                   NULL);
  mu_assert(sb, "lsb_create() received: NULL");
  lsb_err_value ret = lsb_init(sb, NULL);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  clock_t t = clock();
  for (int x = 0; x < iter; ++x) {  // test add speed
    mu_assert(0 == lsb_test_process(sb, x), "%s", lsb_get_error(sb));
  }
  t = clock() - t;
  lsb_test_report(sb, 0);
  mu_assert(strcmp("999985", lsb_test_output) == 0, "received: %s",
            lsb_test_output);
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
