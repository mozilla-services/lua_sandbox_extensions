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
  lsb_lua_sandbox *sb = lsb_create(NULL, "test.lua", TEST_MODULE_PATH, NULL);
  mu_assert(sb, "lsb_create() received: NULL");
  lsb_err_value ret = lsb_init(sb, NULL);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  return NULL;
}


static char* test_sandbox()
{
  const char *output_file = "circular_buffer.preserve";
  const char *outputs[] = {
    "{\"time\":0,\"rows\":3,\"columns\":3,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Add_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Set_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Get_column\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[]}\nnan\tnan\tnan\nnan\tnan\tnan\nnan\tnan\tnan\n"
    , "{\"time\":0,\"rows\":3,\"columns\":3,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Add_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Set_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Get_column\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[]}\n1\t1\t1\n2\t1\t2\n3\t1\t3\n"
    , "{\"time\":2,\"rows\":3,\"columns\":3,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Add_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Set_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Get_column\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[]}\n3\t1\t3\nnan\tnan\tnan\n1\t1\t1\n"
    , "{\"time\":8,\"rows\":3,\"columns\":3,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Add_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Set_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Get_column\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[]}\nnan\tnan\tnan\nnan\tnan\tnan\n1\t1\t1\n"
    , NULL
  };

  remove(output_file);
  lsb_lua_sandbox *sb = lsb_create(NULL, "test_sandbox.lua", TEST_MODULE_PATH
                                   "memory_limit = 32767\n", NULL);
  mu_assert(sb, "lsb_create() received: NULL");

  lsb_err_value ret = lsb_init(sb, output_file);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  int result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(lsb_get_state(sb) == LSB_RUNNING, "error %s",
            lsb_get_error(sb));
  mu_assert(strcmp(outputs[0], lsb_test_output) == 0, "received: %s",
            lsb_test_output);

  lsb_test_process(sb, 0);
  lsb_test_process(sb, 1e9);
  lsb_test_process(sb, 1e9);
  lsb_test_process(sb, 2e9);
  lsb_test_process(sb, 2e9);
  lsb_test_process(sb, 2e9);
  result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp(outputs[1], lsb_test_output) == 0, "received: %s",
            lsb_test_output);

  lsb_test_process(sb, 4e9);
  result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp(outputs[2], lsb_test_output) == 0, "received: %s",
            lsb_test_output);

  lsb_test_process(sb, 10e9);
  result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp(outputs[3], lsb_test_output) == 0, "received: %s",
            lsb_test_output);

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
  mu_assert(strcmp(outputs[3], lsb_test_output) == 0, "received: %s",
            lsb_test_output);

  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  return NULL;
}


static char* test_sandbox_delta()
{
  const char *output_file = "circular_buffer_delta.preserve";
  const char *outputs[] = {
    "{\"time\":0,\"rows\":3,\"columns\":3,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Add_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Set_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Get_column\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[]}\n1\t1\t1\n2\t1\t2\n3\t1\t3\n"
    , "{\"time\":0,\"rows\":3,\"columns\":3,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Add_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Set_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Get_column\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[]}\n0\t1\t1\t1\n1\t2\t1\t2\n2\t3\t1\t3\n"
    , "{\"time\":0,\"rows\":3,\"columns\":3,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Add_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Set_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Get_column\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[]}\n1\t1\t1\n2\t1\t2\n3\t1\t3\n"
    , ""
    , "{\"time\":0,\"rows\":2,\"columns\":2,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Sum_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Min\",\"unit\":\"count\",\"aggregation\":\"min\"}],\"annotations\":[]}\n0\t2\t5\n"
    , "{\"time\":0,\"rows\":2,\"columns\":2,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Sum_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Min\",\"unit\":\"count\",\"aggregation\":\"min\"}],\"annotations\":[]}\n0\t3\t4\n"
    , "{\"time\":0,\"rows\":3,\"columns\":3,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Add_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Set_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Get_column\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[]}\n0\tinf\t-inf\tinf\n"
    , "{\"time\":0,\"rows\":2,\"columns\":2,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Sum_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Min\",\"unit\":\"count\",\"aggregation\":\"min\"}],\"annotations\":[{\"x\":1000,\"col\":1,\"shortText\":\"i\",\"text\":\"delta anno\"}]}\n"
    , ""
    , NULL
  };

  remove(output_file);
  lsb_lua_sandbox *sb = lsb_create(NULL, "test_sandbox_delta.lua",
                                   TEST_MODULE_PATH, NULL);
  mu_assert(sb, "lsb_create() received: NULL");

  lsb_err_value ret = lsb_init(sb, output_file);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  lsb_test_process(sb, 0);
  lsb_test_process(sb, 1e9);
  lsb_test_process(sb, 1e9);
  lsb_test_process(sb, 2e9);
  lsb_test_process(sb, 2e9);
  lsb_test_process(sb, 2e9);
  int result = lsb_test_report(sb, 0);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp(outputs[0], lsb_test_output) == 0, "received: %s",
            lsb_test_output);

  result = lsb_test_report(sb, 1);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp(outputs[1], lsb_test_output) == 0, "received: %s",
            lsb_test_output);

  for (int i = 2; outputs[i] != NULL; ++i) {
    result = lsb_test_report(sb, i - 2);
    mu_assert(result == 0, "report() received: %d error: %s", result,
              lsb_get_error(sb));
    mu_assert(strcmp(outputs[i], lsb_test_output) == 0, "test: %d received: %s", i,
              lsb_test_output);
  }

  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);

  // re-load to test the preserved data
  sb = lsb_create(NULL, "test_sandbox_delta.lua", TEST_MODULE_PATH, NULL);
  mu_assert(sb, "lsb_create() received: NULL");

  ret = lsb_init(sb, output_file);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  result = lsb_test_report(sb, 7);
  mu_assert(result == 0, "report() received: %d", result);
  mu_assert(strcmp("{\"time\":4,\"rows\":3,\"columns\":3,\"seconds_per_row\":1,\"column_info\":[{\"name\":\"Add_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Set_column\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Get_column\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[{\"x\":6000,\"col\":1,\"shortText\":\"i\",\"text\":\"anno preserve\"}]}\n6\t1\tnan\tnan\n", lsb_test_output) == 0, "received: %s", lsb_test_output);
  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  return NULL;
}


static char* test_sandbox_annotation()
{
  const char *outputs[] = {
    "{\"time\":0,\"rows\":2,\"columns\":2,\"seconds_per_row\":60,\"column_info\":[{\"name\":\"Column_1\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Column_2\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[{\"x\":0,\"col\":1,\"shortText\":\"i\",\"text\":\"annotation\\\"\\t\\b\\r\\n  end\"},{\"x\":60000,\"col\":2,\"shortText\":\"a\",\"text\":\"alert\"}]}\nnan\tnan\nnan\tnan\n",
    "{\"time\":60,\"rows\":2,\"columns\":2,\"seconds_per_row\":60,\"column_info\":[{\"name\":\"Column_1\",\"unit\":\"count\",\"aggregation\":\"sum\"},{\"name\":\"Column_2\",\"unit\":\"count\",\"aggregation\":\"sum\"}],\"annotations\":[{\"x\":60000,\"col\":2,\"shortText\":\"a\",\"text\":\"alert\"}]}\nnan\tnan\nnan\tnan\n",
    NULL
  };

  lsb_lua_sandbox *sb = lsb_create(NULL, "test_sandbox_annotation.lua",
                                   TEST_MODULE_PATH, NULL);
  mu_assert(sb, "lsb_create() received: NULL");

  lsb_err_value ret = lsb_init(sb, NULL);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  for (int x = 0; outputs[x]; ++x) {
    int result = lsb_test_process(sb, x);
    mu_assert(!result, "process() test: %d failed: %d %s", x, result,
              lsb_get_error(sb));
    if (outputs[x][0]) {
      mu_assert(strcmp(outputs[x], lsb_test_output) == 0,
                "test: %d received: %s", x, lsb_test_output);
    }
  }

  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  return NULL;
}


static char* benchmark()
{
  int iter = 1000000;

  lsb_lua_sandbox *sb = lsb_create(NULL, "benchmark.lua", TEST_MODULE_PATH,
                                   NULL);
  mu_assert(sb, "lsb_create() received: NULL");
  lsb_err_value ret = lsb_init(sb, NULL);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));

  double ts = 0;
  clock_t t = clock();
  for (int x = 0; x < iter; ++x) {
    mu_assert(0 == lsb_test_process(sb, 0), "%s", lsb_get_error(sb));
    ts += 1e9;
  }
  t = clock() - t;
  mu_assert(lsb_get_state(sb) == LSB_RUNNING, "benchmark failed %s",
            lsb_get_error(sb));
  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  printf("benchmark %g seconds\n", ((double)t) / CLOCKS_PER_SEC / iter);
  return NULL;
}


static char* benchmark_output()
{
  int iter = 10000;

  lsb_lua_sandbox *sb = lsb_create(NULL, "benchmark_output.lua",
                                   TEST_MODULE_PATH, NULL);
  mu_assert(sb, "lsb_create() received: NULL");
  lsb_err_value ret = lsb_init(sb, NULL);
  mu_assert(!ret, "lsb_init() received: %s %s", ret, lsb_get_error(sb));
  lsb_add_function(sb, &lsb_test_write_output, "write_output");

  clock_t t = clock();
  for (int x = 0; x < iter; ++x) {
    mu_assert(0 == lsb_test_process(sb, 1), "%s", lsb_get_error(sb));
  }
  t = clock() - t;
  e = lsb_destroy(sb);
  mu_assert(!e, "lsb_destroy() received: %s", e);
  printf("benchmark_output %g seconds\n", ((double)t) / CLOCKS_PER_SEC / iter);
  return NULL;
}


static char* all_tests()
{
  mu_run_test(test_core);
  mu_run_test(test_sandbox);
  mu_run_test(test_sandbox_delta);
  mu_run_test(test_sandbox_annotation);
  mu_run_test(benchmark);
  mu_run_test(benchmark_output);
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
