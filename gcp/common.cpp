/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief GCP common functions  @file */

#include "common.h"

#include <climits>
#include <iomanip>
#include <sstream>

typedef google::protobuf::MapPair<std::string, std::string> MapPairString;

void gcp_headers_to_map(const lsb_heka_message *hm, MapString* m)
{
  m->insert(MapPairString("heka_message", "1"));
  if (hm->uuid.len == LSB_UUID_SIZE) {
    std::ostringstream oss;
    oss << std::hex << std::setfill('0');
    for (size_t i = 0; i < hm->uuid.len; ++i) {
      unsigned u = (unsigned char)hm->uuid.s[i];
      oss << std::setw(2) << u;
      switch (i) {
      case 3:
      case 5:
      case 7:
      case 9:
        oss << '-';
        break;
      }
    }
    m->insert(MapPairString(LSB_UUID, oss.str()));
  }

  std::ostringstream oss;
  oss << hm->timestamp;
  m->insert(MapPairString(LSB_TIMESTAMP, oss.str()));
  oss.str("");

  if (hm->type.s) {
    m->insert(MapPairString(LSB_TYPE, std::string(hm->type.s, hm->type.len)));
  }
  if (hm->logger.s) {
    m->insert(MapPairString(LSB_LOGGER, std::string(hm->logger.s, hm->logger.len)));
  }
  if (hm->env_version.s) {
    m->insert(MapPairString(LSB_ENV_VERSION, std::string(hm->env_version.s, hm->env_version.len)));
  }
  if (hm->hostname.s) {
    m->insert(MapPairString(LSB_HOSTNAME, std::string(hm->hostname.s, hm->hostname.len)));
  }
  if (hm->pid != INT_MIN) {
    oss << hm->pid;
    m->insert(MapPairString(LSB_PID, oss.str()));
    oss.str("");
  }

  oss << hm->severity;
  m->insert(MapPairString(LSB_SEVERITY, oss.str()));
  oss.str("");
}


void gcp_fields_to_map(const lsb_heka_message *hm, MapString *m)
{
  const char *p, *e;
  for (int i = 0; i < hm->fields_len; ++i) {
    std::ostringstream oss;
    bool first = true;
    std::string type_ext;
    lsb_heka_field *f = &hm->fields[i];
    auto name = std::string(f->name.s, f->name.len);
    p = f->value.s;
    e = p + f->value.len;
    switch (f->value_type) {
    case LSB_PB_BYTES:
      break; // don't encode binary data to work with text attributes
    case LSB_PB_STRING:
      {
        int tag = 0;
        int wiretype = 0;
        while (p && p < e) {
          p = lsb_pb_read_key(p, &tag, &wiretype);
          if (wiretype == LSB_PB_WT_LENGTH) {
            long long len;
            p = lsb_pb_read_varint(p, e, &len);
            if (p && (len >= 0 || len <= e - p)) {
              if (first) {
                first = false;
              } else {
                oss << '\t';
              }
              for (int i = 0; i < len; ++i) {
                if (p[i] == '\t') {
                  oss << "\\t";
                } else {
                  oss << p[i];
                }
              }
              p += len;
            } else {
              p = e; // bogus length, move to the end
            }
          }
        }
      }
      break;
    case LSB_PB_DOUBLE:
      type_ext = "_dbl";
      for (;p < e; p += sizeof(double)) {
        double d;
        memcpy(&d, p, sizeof(double));
        if (first) {
          first = false;
        } else {
          oss << '\t';
        }
        oss << d;
      }
      break;
    case LSB_PB_INTEGER:
      {
        type_ext = "_int";
        long long ll = 0;
        while (p && p < e) {
          p = lsb_pb_read_varint(p, e, &ll);
          if (p) {
            if (first) {
              first = false;
            } else {
              oss << '\t';
            }
            oss << ll;
          }
        }
      }
      break;
    case LSB_PB_BOOL:
      {
        type_ext = "_bool";
        long long ll = 0;
        while (p && p < e) {
          p = lsb_pb_read_varint(p, e, &ll);
          if (p) {
            if (first) {
              first = false;
            } else {
              oss << '\t';
            }
            oss << (ll ? "true" : "false");
          }
        }
      }
      break;
    }
    if (!first) {
      m->insert(MapPairString(name + type_ext, oss.str()));
    }
  }
}

