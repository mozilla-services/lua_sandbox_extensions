/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief GCP common functions  @file */

#ifndef common_h_
#define common_h_

extern "C"
{
#include <luasandbox/util/heka_message.h>
#include <luasandbox/util/protobuf.h>
}

#include <google/protobuf/map.h>
#include <string>

typedef google::protobuf::Map<std::string, std::string> MapString;
typedef google::protobuf::MapPair<std::string, std::string> MapPairString;

/**
 * Loads the Heka message headers into the map.
 *
 * @param hm Heka message
 * @param m map
 */
void gcp_headers_to_map(const lsb_heka_message *hm, MapString *m);

/**
 * Loads the Heka message Fields into the map.
 *
 * @param hm Heka message
 * @param m map
 */
void gcp_fields_to_map(const lsb_heka_message *hm, MapString *m);

#endif

