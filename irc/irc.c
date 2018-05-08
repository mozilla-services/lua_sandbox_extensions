/* -*- Mode: C; tab-width: 8; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* vim: set ts=2 et sw=2 tw=80: */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/** @brief Lua IRC integration @file */

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <netdb.h>
#include <errno.h>
#include <time.h>
#include <openssl/ssl.h>
#include <signal.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#define MOZSVC_IRC_TABLE	"irc"
#define MOZSVC_IRC		"mozsvc.irc"

#define CHANQUEUE_LENGTH 32

SSL_CTX *ctx;

enum {
  STATE_DOWN,
  STATE_CONNECTING,
  STATE_VERIFIED,
  STATE_JOINED
};

struct queueent {
  char            buf[400];
  struct queueent *next;
};

struct ircconn {
  pthread_t monitor;

  char  *irc_nick;
  char	*irc_chan;
  char	*irc_chankey;
  char	*irc_hn;
  int   irc_port;

  int             status; // STATE_DOWN, STATE_VERIFIED, etc...
  int             nothread; // non-zero if thread creation for monitor fails
  time_t          rejoin_timer;
  int             exit; // if non-zero thread should exit
  pthread_mutex_t exitlock;

  int	fd;
  BIO	*bio;
  SSL	*ssl;

  char    inbuf[10240];
  size_t  inbuf_len;

  struct queueent *chanqueue;
  int             chanqueue_size;
  pthread_mutex_t chanqueue_lock;
};

struct args {
  char **args;
  int n;
};

static void irclib_args_free(struct args *a) {
  int i;

  if (!a) {
    return;
  }
  if (a->args) {
    for (i = 0; i < a->n; ++i) {
      if (a->args[i]) {
        free(a->args[i]);
      }
    }
    free(a->args);
  }
  free(a);
}

static struct args *irclib_args_parse(char *buf)
{
  struct args *ret = NULL;
  char **tmp;
  char *t;

  ret = malloc(sizeof(struct args));
  if (!ret) {
    return NULL;
  }
  memset(ret, 0, sizeof(struct args));
  while ((t = strsep(&buf, " ")) != NULL) {
    ret->n++;
    tmp = realloc(ret->args, sizeof(char *) * ret->n);
    if (!tmp) {
      ret->n--;
      irclib_args_free(ret);
      return NULL;
    }
    ret->args = tmp;
    ret->args[ret->n - 1] = strdup(t);
    if (!ret->args[ret->n - 1]) {
      irclib_args_free(ret);
      return NULL;
    }
  }

  return ret;
}

static int irclib_bio_write(BIO *b, char *buf, size_t len)
{
  for (;;) {
    if (BIO_write(b, buf, len) <= 0) {
      if (!BIO_should_retry(b)) {
        return -1;
      }
      continue;
    }
    break;
  }

  return 0;
}

static int irclib_parse(struct ircconn *ic, char *buf)
{
  struct args *a = irclib_args_parse(buf);
  if (!a) {
    return -1;
  }

  if (a->n < 2) {
    irclib_args_free(a);
    return 0;
  }
  char outbuf[512];
  if (strcmp(a->args[0], "PING") == 0) {
    snprintf(outbuf, sizeof(outbuf), "PONG %s\r\n", a->args[1]);
    if (irclib_bio_write(ic->bio, outbuf, strlen(outbuf)) == -1) {
      irclib_args_free(a);
      return -1;
    }
    irclib_args_free(a);
    return 0;
  }
  switch (ic->status) {
    case STATE_CONNECTING:
      if (strcmp(a->args[1], "001") == 0) {
        ic->status = STATE_VERIFIED;
        // verified, send a join message
        snprintf(outbuf, sizeof(outbuf), "JOIN %s %s\r\n", ic->irc_chan,
            ic->irc_chankey != NULL ? ic->irc_chankey : "");
        if (irclib_bio_write(ic->bio, outbuf, strlen(outbuf)) == -1) {
          irclib_args_free(a);
          return -1;
        }
        // schedule a rejoin in case this one is not successful
        ic->rejoin_timer = time(NULL) + 30;
      }
      break;
    case STATE_VERIFIED:
      if (strcmp(a->args[1], "JOIN") == 0) {
        char u[512];
        snprintf(u, sizeof(u) - 1, ":%s!", ic->irc_nick);
        if (strncmp(u, a->args[0], strlen(u)) != 0) {
          break;
        }
        ic->rejoin_timer = 0;
        ic->status = STATE_JOINED;
      }
      break;
    case STATE_JOINED:
      if (strcmp(a->args[1], "KICK") == 0) {
        if (a->n >= 4) {
          if (strcmp(a->args[3], ic->irc_nick) == 0) {
            ic->status = STATE_VERIFIED;
            ic->rejoin_timer = time(NULL) + 30;
          }
        }
      }
      break;
  }

  irclib_args_free(a);
  return 0;
}

static int irclib_tryconn(struct ircconn *ic)
{
  char buf[1024];

  memset(ic->inbuf, 0, sizeof(ic->inbuf));
  ic->inbuf_len = 0;
  pthread_mutex_lock(&ic->chanqueue_lock);
  if (ic->chanqueue) {
    for (;;) {
      struct queueent *qp = ic->chanqueue->next;
      free(ic->chanqueue);
      if (!qp) {
        break;
      }
      ic->chanqueue = qp;
    }
  }
  ic->chanqueue = NULL;
  ic->chanqueue_size = 0;
  pthread_mutex_unlock(&ic->chanqueue_lock);

  ic->bio = BIO_new_ssl_connect(ctx);
  BIO_set_nbio(ic->bio, 1);
  snprintf(buf, sizeof(buf), "%s:%d", ic->irc_hn, ic->irc_port);
  BIO_set_conn_hostname(ic->bio, buf);
  BIO_get_ssl(ic->bio, &ic->ssl);

  for (;;) {
    if (BIO_do_connect(ic->bio) != 1) {
      if (!BIO_should_retry(ic->bio)) {
        BIO_free_all(ic->bio);
        return -1;
      }
    } else {
      break;
    }
  }
  for (;;) {
    if (BIO_do_handshake(ic->bio) != 1) {
      if (!BIO_should_retry(ic->bio)) {
        BIO_free_all(ic->bio);
        return -1;
      }
    } else {
      break;
    }
  }

  snprintf(buf, sizeof(buf), "NICK %s\r\nUSER %s @ %s :%s\r\n", ic->irc_nick, ic->irc_nick,
      ic->irc_nick, ic->irc_nick);
  if (irclib_bio_write(ic->bio, buf, strlen(buf)) == -1) {
    return -1;
  }

  return 0;
}

void *irclib_monitor(void *args)
{
  char buf[4096];
  char linebuf[4096];
  fd_set rfds;
  struct ircconn *ic;
  int fflag, ret;
  char *p0, *p1, *p2;
  size_t avail, left;
  struct timeval tv;

  signal(SIGPIPE, SIG_IGN);
  ic = (struct ircconn *)args;

  for (;;) {
    pthread_mutex_lock(&ic->exitlock);
    if (ic->exit) {
      pthread_mutex_unlock(&ic->exitlock);
      pthread_exit(NULL);
    }
    pthread_mutex_unlock(&ic->exitlock);
    // if connection is down, try to initiate it
    if (ic->status == STATE_DOWN) {
      if (irclib_tryconn(ic) == -1) {
        sleep(5);
        continue;
      }
      ic->status = STATE_CONNECTING;
    }

    FD_ZERO(&rfds);
    FD_SET(BIO_get_fd(ic->bio, NULL), &rfds);
    memset(&tv, 0, sizeof(tv));
    tv.tv_sec = 1;
    ret = select(FD_SETSIZE, &rfds, NULL, NULL, &tv);
    if (ret == -1) {
      BIO_free_all(ic->bio);
      ic->inbuf_len = 0;
      ic->status = STATE_DOWN;
      ic->rejoin_timer = 0;
      continue;
    }
    if (FD_ISSET(BIO_get_fd(ic->bio, NULL), &rfds)) {
      memset(buf, 0, sizeof(buf));
      ret = BIO_read(ic->bio, buf, sizeof(buf));
      if (ret > 0) {
        int bufrem = sizeof(ic->inbuf) - ic->inbuf_len;
        if (bufrem < ret) {
          // input buffer is full, don't try to recover from this
          ic->inbuf_len = 0;
          BIO_free_all(ic->bio);
          ic->status = STATE_DOWN;
          ic->rejoin_timer = 0;
          continue;
        }
        // copy the input into the input buffer
        memcpy(ic->inbuf + ic->inbuf_len, buf, ret);
        ic->inbuf_len += ret;
      } else {
        if (BIO_should_retry(ic->bio)) {
          continue;
        }
        BIO_free_all(ic->bio);
        ic->inbuf_len = 0;
        ic->status = STATE_DOWN;
        ic->rejoin_timer = 0;
        continue;
      }
    }

    // loop over any messages we have available in the input buffer
    p0 = p1 = ic->inbuf;
    left = avail = ic->inbuf_len;
    fflag = 0;
    for (;;) {
      if (avail == 0) {
        break;
      }
      if (*p0 == '\n') {
        *p0 = '\0';
        // strip linefeed
        for (p2 = p1; *p2 != '\0'; ++p2) {
          if (*p2 == '\r') {
            *p2 = '\0';
          }
        }
        memset(linebuf, 0, sizeof(linebuf));
        strncpy(linebuf, p1, sizeof(linebuf) - 1);
        if (irclib_parse(ic, linebuf) == -1) {
          fflag = 1;
          break;
        }
        p0++;
        left -= (p0 - p1);
        p1 = p0;
        avail--;
        continue;
      }
      p0++;
      avail--;
    }
    if (fflag == 1) {
        BIO_free_all(ic->bio);
        ic->inbuf_len = 0;
        ic->status = STATE_DOWN;
        ic->rejoin_timer = 0;
        continue;
    }
    // move any remaining bytes back in the input buffer
    if (left > 0) {
      memmove(ic->inbuf, p1, left);
      ic->inbuf_len = left;
    } else {
      ic->inbuf_len = 0;
    }

    if (ic->status == STATE_VERIFIED) {
      if ((ic->rejoin_timer != 0) && (ic->rejoin_timer < time(NULL))) {
        snprintf(linebuf, sizeof(linebuf), "JOIN %s %s\r\n", ic->irc_chan,
            ic->irc_chankey != NULL ? ic->irc_chankey : "");
        if (irclib_bio_write(ic->bio, linebuf, strlen(linebuf)) == -1) {
          BIO_free_all(ic->bio);
          ic->inbuf_len = 0;
          ic->status = STATE_DOWN;
          ic->rejoin_timer = 0;
          continue;
        }
        ic->rejoin_timer = time(NULL) + 30;
      }
    } else if (ic->status == STATE_JOINED) {
      pthread_mutex_lock(&ic->chanqueue_lock);
      if (ic->chanqueue_size > 0) {
        struct queueent *qp;
        snprintf(linebuf, sizeof(linebuf), "PRIVMSG %s :%s\r\n", ic->irc_chan, ic->chanqueue->buf);
        if (irclib_bio_write(ic->bio, linebuf, strlen(linebuf)) == -1) {
          BIO_free_all(ic->bio);
          ic->inbuf_len = 0;
          ic->status = STATE_DOWN;
          ic->rejoin_timer = 0;
          pthread_mutex_unlock(&ic->chanqueue_lock);
          continue;
        }
        qp = ic->chanqueue;
        ic->chanqueue = ic->chanqueue->next;
        free(qp);
        ic->chanqueue_size--;
      }
      pthread_mutex_unlock(&ic->chanqueue_lock);
    }
  }

  return NULL;
}

static int irclib_new(lua_State *lua)
{
  struct ircconn *ic;
  int nargs = lua_gettop(lua);

  luaL_argcheck(lua, nargs == 4 || nargs == 5, 0, "incorrect number of arguments");

  const char *nick = luaL_checkstring(lua, 1);
  const char *hn = luaL_checkstring(lua, 2);
  int port = luaL_checkint(lua, 3);
  const char *chan = luaL_checkstring(lua, 4);
  const char *chankey = NULL;
  if (nargs > 4) {
    chankey = luaL_checkstring(lua, 5);
  }
  ic = lua_newuserdata(lua, sizeof(struct ircconn));
  memset(ic, 0, sizeof(struct ircconn));
  luaL_getmetatable(lua, MOZSVC_IRC);
  lua_setmetatable(lua, -2);
  ic->irc_nick = strdup(nick);
  ic->irc_hn = strdup(hn);
  ic->irc_port = port;
  ic->irc_chan = strdup(chan);
  if (chankey) {
    ic->irc_chankey = strdup(chankey);
  }
  ic->status = STATE_DOWN;
  ic->nothread = 0;

  pthread_mutex_init(&ic->exitlock, NULL);
  pthread_mutex_init(&ic->chanqueue_lock, NULL);
  if (pthread_create(&ic->monitor, NULL, irclib_monitor, ic) != 0) {
    // mark thread creation as failed so we don't try to join it during gc
    ic->nothread = 1;
    return luaL_error(lua, "pthread_create failed");
  }

  return 1;
}

static int irclib_writeraw(lua_State *lua)
{
  struct ircconn *ic = luaL_checkudata(lua, 1, MOZSVC_IRC);
  const char *s = luaL_checkstring(lua, 2);
  char buf[512];

  snprintf(buf, sizeof(buf), "%s\r\n", s);
  irclib_bio_write(ic->bio, buf, strlen(buf));
  return 0;
}

static int irclib_status(lua_State *lua)
{
  struct ircconn *ic = luaL_checkudata(lua, 1, MOZSVC_IRC);

  lua_newtable(lua);
  lua_pushstring(lua, "server");
  lua_pushstring(lua, ic->irc_hn);
  lua_settable(lua, -3);
  lua_pushstring(lua, "port");
  lua_pushnumber(lua, ic->irc_port);
  lua_settable(lua, -3);

  return 1;
}

static int irclib_writechan(lua_State *lua)
{
  struct ircconn *ic = luaL_checkudata(lua, 1, MOZSVC_IRC);
  const char *s = luaL_checkstring(lua, 2);
  struct queueent *q;

  pthread_mutex_lock(&ic->chanqueue_lock);
  if (ic->chanqueue_size == CHANQUEUE_LENGTH) {
    pthread_mutex_unlock(&ic->chanqueue_lock);
    return 0;
  }
  q = malloc(sizeof(struct queueent));
  if (!q) {
    pthread_mutex_unlock(&ic->chanqueue_lock);
    return luaL_error(lua, "queue allocation failed");
  }
  memset(q, 0, sizeof(struct queueent));
  strncpy(q->buf, s, sizeof(q->buf) - 1);
  if (!ic->chanqueue) {
    ic->chanqueue = q;
  } else {
    struct queueent *ptr;
    for (ptr = ic->chanqueue; ptr->next != NULL; ptr = ptr->next);
    ptr->next = q;
  }
  ic->chanqueue_size++;
  pthread_mutex_unlock(&ic->chanqueue_lock);

  return 0;
}

static int irclib_gc(lua_State *lua)
{
  struct ircconn *ic = luaL_checkudata(lua, 1, MOZSVC_IRC);
  pthread_mutex_lock(&ic->exitlock);
  ic->exit++;
  pthread_mutex_unlock(&ic->exitlock);
  if (!ic->nothread) {
    // if a thread was created, wait for it to exit before we continue
    pthread_join(ic->monitor, NULL);
    if (ic->status != STATE_DOWN) {
      BIO_free_all(ic->bio);
    }
  }
  free(ic->irc_nick);
  free(ic->irc_chan);
  free(ic->irc_chankey);
  free(ic->irc_hn);
  pthread_mutex_destroy(&ic->chanqueue_lock);
  pthread_mutex_destroy(&ic->exitlock);
  if (ic->chanqueue) {
    struct queueent *q, *q2;
    for (q = ic->chanqueue; q;) {
      q2 = q->next;
      free(q);
      q = q2;
    }
  }
  return 0;
}

static const luaL_Reg irclib[] = {
  { "new", irclib_new },
  { NULL, NULL }
};

static const luaL_Reg irclib_ud[] = {
  { "status", irclib_status },
  { "write_raw", irclib_writeraw },
  { "write_chan", irclib_writechan },
  { "__gc", irclib_gc },
  { NULL, NULL }
};

int luaopen_irc(lua_State *lua)
{
  // initialize OpenSSL here, we only support connections over SSL/TLS right now
  SSL_library_init();
  OpenSSL_add_all_ciphers();
  OpenSSL_add_all_digests();
  SSL_load_error_strings();
  ERR_load_BIO_strings();
  ctx = SSL_CTX_new(SSLv23_method());

  luaL_newmetatable(lua, MOZSVC_IRC);
  lua_pushvalue(lua, -1);
  lua_setfield(lua, -2, "__index");
  luaL_register(lua, NULL, irclib_ud);
  luaL_register(lua,  MOZSVC_IRC_TABLE, irclib);
  return 1;
}
