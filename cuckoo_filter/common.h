/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua cuckoo filter common functions  @file */

#ifndef common_h_
#define common_h_

#include <inttypes.h>

#define BUCKET_SIZE 4

/**
 * Hacker's Delight - Henry S. Warren, Jr. page 48
 *
 * @param x
 *
 * @return unsigned Least power of 2 greater than or equal to x
 */
unsigned clp2(unsigned x);

/**
 * Hacker's Delight - Henry S. Warren, Jr. page 78
 *
 * @param x
 *
 * @return int Number of leading zeros
 */
int nlz(unsigned x);

/**
 * Turn the unsigned value into a 16 bit fingerprint
 *
 * @param h
 *
 * @return unsigned short
 */
uint16_t fingerprint16(uint64_t h);

/**
 * Turn the unsigned value into a 32 bit fingerprint
 *
 * @param h
 *
 * @return uint32_t
 */
uint32_t fingerprint32(uint64_t h);
#endif

