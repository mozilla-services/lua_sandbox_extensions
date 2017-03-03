/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua cuckoo filter common functions  @file */

#include "common.h"

unsigned clp2(unsigned x)
{
  x = x - 1;
  x = x | (x >> 1);
  x = x | (x >> 2);
  x = x | (x >> 4);
  x = x | (x >> 8);
  x = x | (x >> 16);
  return x + 1;
}


int nlz(unsigned x)
{
  int n;

  if (x == 0) return 32;
  n = 1;
  if ((x >> 16) == 0) {n = n + 16; x = x << 16;}
  if ((x >> 24) == 0) {n = n + 8; x = x << 8;}
  if ((x >> 28) == 0) {n = n + 4; x = x << 4;}
  if ((x >> 30) == 0) {n = n + 2; x = x << 2;}
  n = n - (x >> 31);
  return n;
}


uint16_t fingerprint16(uint64_t h)
{
  h = h >> 48;
  return h ? h : 1;
}


uint32_t fingerprint32(uint64_t h)
{
  h = h >> 32;
  return h ? h : 1;
}
