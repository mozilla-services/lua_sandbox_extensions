/* hyperloglog.c - Redis HyperLogLog probabilistic cardinality approximation.
 * This file implements the algorithm and the exported Redis commands.
 *
 * Copyright (c) 2014, Salvatore Sanfilippo <antirez at gmail dot com>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *   * Redistributions of source code must retain the above copyright notice,
 *     this list of conditions and the following disclaimer.
 *   * Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *   * Neither the name of Redis nor the names of its contributors may be used
 *     to endorse or promote products derived from this software without
 *     specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/* This file has been modified for use in the Mozilla lua_sandbox.  Dependencies
   on the redis.h header file and the unneed sparse and raw implementations have
   been removed.  The dense data representation remains unchanged. */

#include <stdio.h>
#include <stdint.h>
#include <math.h>

#include "redis_hyperloglog.h"


/* The Redis HyperLogLog implementation is based on the following ideas:
 *
 * * The use of a 64 bit hash function as proposed in [1], in order to don't
 *   limited to cardinalities up to 10^9, at the cost of just 1 additional
 *   bit per register.
 * * The use of 16384 6-bit registers for a great level of accuracy, using
 *   a total of 12k per key.
 * * The use of the Redis string data type. No new type is introduced.
 * * No attempt is made to compress the data structure as in [1]. Also the
 *   algorithm used is the original HyperLogLog Algorithm as in [2], with
 *   the only difference that a 64 bit hash function is used, so no correction
 *   is performed for values near 2^32 as in [1].
 *
 * [1] Heule, Nunkesser, Hall: HyperLogLog in Practice: Algorithmic
 *     Engineering of a State of The Art Cardinality Estimation Algorithm.
 *
 * [2] P. Flajolet, Eric Fusy, O. Gandouet, and F. Meunier. Hyperloglog: The
 *     analysis of a near-optimal cardinality estimation algorithm.
 *
 * The "dense" representation where every entry is represented by a
 * 6-bit integer.
 *
 * HLL header
 * ===
 *
 * Both the dense and sparse representation have a 16 byte header as follows:
 *
 * +------+---+-----+----------+
 * | HYLL | E | N/U | Cardin.  |
 * +------+---+-----+----------+
 *
 * The first 4 bytes are a magic string set to the bytes "HYLL".
 * "E" is one byte encoding, currently set to HLL_DENSE or
 * HLL_SPARSE. N/U are three not used bytes.
 *
 * The "Cardin." field is a 64 bit integer stored in little endian format
 * with the latest cardinality computed that can be reused if the data
 * structure was not modified since the last computation (this is useful
 * because there are high probabilities that HLLADD operations don't
 * modify the actual data structure and hence the approximated cardinality).
 *
 * When the most significant bit in the most significant byte of the cached
 * cardinality is set, it means that the data structure was modified and
 * we can't reuse the cached value that must be recomputed.
 *
 * Dense representation
 * ===
 *
 * The dense representation used by Redis is the following:
 *
 * +--------+--------+--------+------//      //--+
 * |11000000|22221111|33333322|55444444 ....     |
 * +--------+--------+--------+------//      //--+
 *
 * The 6 bits counters are encoded one after the other starting from the
 * LSB to the MSB, and using the next bytes as needed.
 *
 */

/* ========================= HyperLogLog algorithm  ========================= */

/* Our hash function is MurmurHash2, 64 bit version.
 * It was modified for Redis in order to provide the same result in
 * big and little endian archs (endian neutral). */
static uint64_t MurmurHash64A(const void *key, int len, unsigned int seed)
{
  const uint64_t m = 0xc6a4a7935bd1e995;
  const int r = 47;
  uint64_t h = seed ^ (len * m);
  const uint8_t *data = (const uint8_t *)key;
  const uint8_t *end = data + (len - (len & 7));

  while (data != end) {
    uint64_t k;

#if (BYTE_ORDER == LITTLE_ENDIAN)
    k = *((uint64_t *)data);
#else
    k = (uint64_t)data[0];
    k |= (uint64_t)data[1] << 8;
    k |= (uint64_t)data[2] << 16;
    k |= (uint64_t)data[3] << 24;
    k |= (uint64_t)data[4] << 32;
    k |= (uint64_t)data[5] << 40;
    k |= (uint64_t)data[6] << 48;
    k |= (uint64_t)data[7] << 56;
#endif

    k *= m;
    k ^= k >> r;
    k *= m;
    h ^= k;
    h *= m;
    data += 8;
  }

  switch (len & 7) {
  case 7:
    h ^= (uint64_t)data[6] << 48;
    /* FALLTHRU */
  case 6:
    h ^= (uint64_t)data[5] << 40;
    /* FALLTHRU */
  case 5:
    h ^= (uint64_t)data[4] << 32;
    /* FALLTHRU */
  case 4:
    h ^= (uint64_t)data[3] << 24;
    /* FALLTHRU */
  case 3:
    h ^= (uint64_t)data[2] << 16;
    /* FALLTHRU */
  case 2:
    h ^= (uint64_t)data[1] << 8;
    /* FALLTHRU */
  case 1:
    h ^= (uint64_t)data[0];
    h *= m;
  };

  h ^= h >> r;
  h *= m;
  h ^= h >> r;
  return h;
}

/* Given a string element to add to the HyperLogLog, returns the length
 * of the pattern 000..1 of the element hash. As a side effect 'regp' is
 * set to the register index this element hashes to. */
static int hllPatLen(unsigned char *ele, size_t elesize, long *regp)
{
  uint64_t hash, bit, index;
  int count;

  /* Count the number of zeroes starting from bit HLL_REGISTERS
   * (that is a power of two corresponding to the first bit we don't use
   * as index). The max run can be 64-P+1 bits.
   *
   * Note that the final "1" ending the sequence of zeroes must be
   * included in the count, so if we find "001" the count is 3, and
   * the smallest count possible is no zeroes at all, just a 1 bit
   * at the first position, that is a count of 1.
   *
   * This may sound like inefficient, but actually in the average case
   * there are high probabilities to find a 1 after a few iterations. */
  hash = MurmurHash64A(ele, (int)elesize, 0xadc83b19ULL);
  index = hash & HLL_P_MASK; /* Register index. */
  hash |= ((uint64_t)1 << 63); /* Make sure the loop terminates. */
  bit = HLL_REGISTERS; /* First bit not used to address the register. */
  count = 1; /* Initialized to 1 since we count the "00000...1" pattern. */
  while ((hash & bit) == 0) {
    count++;
    bit <<= 1;
  }
  *regp = (int)index;
  return count;
}

/* Compute SUM(2^-reg) in the dense representation.
 * PE is an array with a pre-computer table of values 2^-reg indexed by reg.
 * As a side effect the integer pointed by 'ezp' is set to the number
 * of zero registers. */
static double hllDenseSum(uint8_t *registers, double *PE, int *ezp)
{
  double E = 0;
  int j, ez = 0;

  /* Redis default is to use 16384 registers 6 bits each. The code works
   * with other values by modifying the defines, but for our target value
   * we take a faster path with unrolled loops. */
  if (HLL_REGISTERS == 16384 && HLL_BITS == 6) {
    uint8_t *r = registers;
    unsigned long r0, r1, r2, r3, r4, r5, r6, r7, r8, r9,
        r10, r11, r12, r13, r14, r15;
    for (j = 0; j < 1024; j++) {
      /* Handle 16 registers per iteration. */
      r0 = r[0] & 63; if (r0 == 0) ez++;
      r1 = (r[0] >> 6 | r[1] << 2) & 63; if (r1 == 0) ez++;
      r2 = (r[1] >> 4 | r[2] << 4) & 63; if (r2 == 0) ez++;
      r3 = (r[2] >> 2) & 63; if (r3 == 0) ez++;
      r4 = r[3] & 63; if (r4 == 0) ez++;
      r5 = (r[3] >> 6 | r[4] << 2) & 63; if (r5 == 0) ez++;
      r6 = (r[4] >> 4 | r[5] << 4) & 63; if (r6 == 0) ez++;
      r7 = (r[5] >> 2) & 63; if (r7 == 0) ez++;
      r8 = r[6] & 63; if (r8 == 0) ez++;
      r9 = (r[6] >> 6 | r[7] << 2) & 63; if (r9 == 0) ez++;
      r10 = (r[7] >> 4 | r[8] << 4) & 63; if (r10 == 0) ez++;
      r11 = (r[8] >> 2) & 63; if (r11 == 0) ez++;
      r12 = r[9] & 63; if (r12 == 0) ez++;
      r13 = (r[9] >> 6 | r[10] << 2) & 63; if (r13 == 0) ez++;
      r14 = (r[10] >> 4 | r[11] << 4) & 63; if (r14 == 0) ez++;
      r15 = (r[11] >> 2) & 63; if (r15 == 0) ez++;

      /* Additional parens will allow the compiler to optimize the
       * code more with a loss of precision that is not very relevant
       * here (floating point math is not commutative!). */
      E += (PE[r0] + PE[r1]) + (PE[r2] + PE[r3]) + (PE[r4] + PE[r5]) +
          (PE[r6] + PE[r7]) + (PE[r8] + PE[r9]) + (PE[r10] + PE[r11]) +
          (PE[r12] + PE[r13]) + (PE[r14] + PE[r15]);
      r += 12;
    }
  } else {
    for (j = 0; j < HLL_REGISTERS; j++) {
      unsigned long reg;

      HLL_DENSE_GET_REGISTER(reg, registers, j);
      if (reg == 0) {
        ez++;
        /* Increment E at the end of the loop. */
      } else {
        E += PE[reg]; /* Precomputed 2^(-reg[j]). */
      }
    }
    E += ez; /* Add 2^0 'ez' times. */
  }
  *ezp = ez;
  return E;
}

/* Implements the SUM operation for uint8_t data type which is only used
 * internally as speedup for PFCOUNT with multiple keys. */
double hllRawSum(uint8_t *registers, double *PE, int *ezp)
{
  double E = 0;
  int j, ez = 0;
  uint64_t *word = (uint64_t *)registers;
  uint8_t *bytes;

  for (j = 0; j < HLL_REGISTERS / 8; j++) {
    if (*word == 0) {
      ez += 8;
    } else {
      bytes = (uint8_t *)word;
      if (bytes[0]) E += PE[bytes[0]];
      else ez++;
      if (bytes[1]) E += PE[bytes[1]];
      else ez++;
      if (bytes[2]) E += PE[bytes[2]];
      else ez++;
      if (bytes[3]) E += PE[bytes[3]];
      else ez++;
      if (bytes[4]) E += PE[bytes[4]];
      else ez++;
      if (bytes[5]) E += PE[bytes[5]];
      else ez++;
      if (bytes[6]) E += PE[bytes[6]];
      else ez++;
      if (bytes[7]) E += PE[bytes[7]];
      else ez++;
    }
    word++;
  }
  E += ez; /* 2^(-reg[j]) is 1 when m is 0, add it 'ez' times for every
              zero register in the HLL. */
  *ezp = ez;
  return E;
}

/* ================== Dense representation implementation  ================== */

/* "Add" the element in the dense hyperloglog data structure.
 * Actually nothing is added, but the max 0 pattern counter of the subset
 * the element belongs to is incremented if needed.
 *
 * 'registers' is expected to have room for HLL_REGISTERS plus an
 * additional byte on the right. This requirement is met by sds strings
 * automatically since they are implicitly null terminated.
 *
 * The function always succeed, however if as a result of the operation
 * the approximated cardinality changed, 1 is returned. Otherwise 0
 * is returned. */
int hllDenseAdd(uint8_t *registers, unsigned char *ele, size_t elesize)
{
  uint8_t oldcount, count;
  long index;

  /* Update the register if this element produced a longer run of zeroes. */
  count = hllPatLen(ele, elesize, &index);
  HLL_DENSE_GET_REGISTER(oldcount, registers, index);
  if (count > oldcount) {
    HLL_DENSE_SET_REGISTER(registers, index, count);
    return 1;
  } else {
    return 0;
  }
}

/* ========================= HyperLogLog Count ==============================
 * This is the core of the algorithm where the approximated count is computed.
 * The function uses the lower level hllDenseSum() function as helpers to
 * compute the SUM(2^-reg) part of the computation, which is
 * representation-specific, while all the rest is common. */

/* Return the approximated cardinality of the set based on the harmonic
 * mean of the registers values. 'hdr' points to the start of the SDS
 * representing the String object holding the HLL representation.
 *
 * hllCount() supports a special internal-only encoding of HLL_RAW, that
 * is, hdr->registers will point to an uint8_t array of HLL_REGISTERS element.
 * This is useful in order to speedup PFCOUNT when called against multiple
 * keys (no need to work with 6-bit integers encoding). */
uint64_t hllCount(hyperloglog *hdr)
{
  double m = HLL_REGISTERS;
  double E, alpha = 0.7213 / (1 + 1.079 / m);
  int j, ez; /* Number of registers equal to 0. */

/* We precompute 2^(-reg[j]) in a small table in order to
 * speedup the computation of SUM(2^-register[0..i]). */
  static int initialized = 0;
  static double PE[64];
  if (!initialized) {
    PE[0] = 1; /* 2^(-reg[j]) is 1 when m is 0. */
    for (j = 1; j < 64; j++) {
      /* 2^(-reg[j]) is the same as 1/2^reg[j]. */
      PE[j] = 1.0 / (1ULL << j);
    }
    initialized = 1;
  }

/* Compute SUM(2^-register[0..i]). */
  if (hdr->encoding == HLL_DENSE) {
    E = hllDenseSum(hdr->registers, PE, &ez);
  } else if (hdr->encoding == HLL_RAW) {
    E = hllRawSum(hdr->registers, PE, &ez);
  } else {
    return 0;
  }

/* Muliply the inverse of E for alpha_m * m^2 to have the raw estimate. */
  E = (1 / E) * alpha * m * m;

/* Use the LINEARCOUNTING algorithm for small cardinalities.
 * For larger values but up to 72000 HyperLogLog raw approximation is
 * used since linear counting error starts to increase. However HyperLogLog
 * shows a strong bias in the range 2.5*16384 - 72000, so we try to
 * compensate for it. */
  if (E < m * 2.5 && ez != 0) {
    E = m * log(m / ez); /* LINEARCOUNTING() */
  } else if (m == 16384 && E < 72000) {
    /* We did polynomial regression of the bias for this range, this
     * way we can compute the bias for a given cardinality and correct
     * according to it. Only apply the correction for P=14 that's what
     * we use and the value the correction was verified with. */
    double bias = 5.9119 * 1.0e-18 * (E * E * E * E)
        - 1.4253 * 1.0e-12 * (E * E * E) +
        1.2940 * 1.0e-7 * (E * E)
        - 5.2921 * 1.0e-3 * E +
        83.3216;
    E -= E * (bias / 100);
  }
/* We don't apply the correction for E > 1/30 of 2^32 since we use
 * a 64 bit function and 6 bit counters. To apply the correction for
 * 1/30 of 2^64 is not needed since it would require a huge set
 * to approach such a value. */
  return (uint64_t)E;
}
