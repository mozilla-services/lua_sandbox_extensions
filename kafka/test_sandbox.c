/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Heka Kafka sandbox integration tests @file */

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

static volatile ptrdiff_t g_sequence = 0;
static int ucp(void *parent, void *sequence_id)
{
  (void)parent;
  g_sequence = (ptrdiff_t)sequence_id;
  return 0;
}


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


static char* test_errors()
{
  lsb_heka_sandbox *hsb;
  hsb = lsb_heka_create_input(NULL, "test_errors.lua", NULL,
                              TEST_MODULE_PATH "log_level = 7\n",
                              &logger, iim);
  mu_assert(hsb, "lsb_heka_create_input failed");
  e = lsb_heka_destroy_sandbox(hsb);
  mu_assert(!e, "%s", e);
  return NULL;
}


static char* test_producer()
{
  static const char pb[] = "\x0a\x10\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x10\x00\x32\x03one";
  lsb_heka_message m;
  mu_assert(!lsb_init_heka_message(&m, 1), "failed to init message");
  mu_assert(lsb_decode_heka_message(&m, pb, sizeof pb - 1, NULL), "failed");
  lsb_heka_sandbox *hsb;
  hsb = lsb_heka_create_output(NULL, "test_sandbox_producer.lua", NULL,
                               TEST_MODULE_PATH "log_level = 7\n",
                               &logger, ucp);
  mu_assert(hsb, "lsb_heka_create_output failed");
  mu_assert(0 == lsb_heka_pm_output(hsb, &m, (void*)1, false), "err: %s",
            lsb_heka_get_error(hsb));
  mu_assert(0 == lsb_heka_pm_output(hsb, &m, (void*)2, false), "err: %s",
            lsb_heka_get_error(hsb));
  mu_assert(0 == lsb_heka_pm_output(hsb, &m, (void*)3, false), "err: %s",
            lsb_heka_get_error(hsb));
  while (g_sequence != 3) {
    mu_assert(0 == lsb_heka_timer_event(hsb, 0, false), "err: %s",
              lsb_heka_get_error(hsb));
  }
  lsb_heka_stats stats = lsb_heka_get_stats(hsb);
  mu_assert(stats.pm_failures == 0, "pm_failures: %llu", stats.pm_failures);
  e = lsb_heka_destroy_sandbox(hsb);
  mu_assert(!e, "%s", e);
  lsb_free_heka_message(&m);
  return NULL;
}


static char* test_consumer()
{
  lsb_heka_sandbox *hsb;
  hsb = lsb_heka_create_input(NULL, "test_sandbox_consumer.lua", NULL,
                              TEST_MODULE_PATH "log_level = 7\n",
                              &logger, iim);
  mu_assert(hsb, "lsb_heka_create_input failed");
  mu_assert(0 == lsb_heka_pm_input(hsb, 0, NULL, false), "err: %s",
            lsb_heka_get_error(hsb));
  e = lsb_heka_destroy_sandbox(hsb);
  mu_assert(!e, "%s", e);
  return NULL;
}


static char* all_tests()
{
  mu_run_test(test_errors);
  mu_run_test(test_producer);
  mu_run_test(test_consumer);
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
