/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Test module configuration @file */

#define TEST_MODULE_PATH \
"path  = [[${TEST_MODULE_PATH};${TEST_IOMODULE_PATH}]]\n" \
"cpath = [[${TEST_MODULE_CPATH};${TEST_IOMODULE_CPATH}]]\n"
