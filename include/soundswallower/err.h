/* -*- c-basic-offset: 4; indent-tabs-mode: nil -*- */
/* ====================================================================
 * Copyright (c) 1999-2004 Carnegie Mellon University.  All rights
 * reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in
 *    the documentation and/or other materials provided with the
 *    distribution.
 *
 * This work was supported in part by funding from the Defense Advanced
 * Research Projects Agency and the National Science Foundation of the
 * United States of America, and the CMU Sphinx Speech Consortium.
 *
 * THIS SOFTWARE IS PROVIDED BY CARNEGIE MELLON UNIVERSITY ``AS IS'' AND
 * ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL CARNEGIE MELLON UNIVERSITY
 * NOR ITS EMPLOYEES BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * ====================================================================
 *
 */

#ifndef _LIBUTIL_ERR_H_
#define _LIBUTIL_ERR_H_

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>

/**
 * @file err.h
 * @brief Implementation of logging routines.
 *
 * Logging, warning, debug and error message output funtionality is provided in this file.
 * Sphinxbase defines several level of logging messages - INFO, WARNING, ERROR, FATAL. By
 * default output goes to standard error output.
 *
 * Logging is implemented through macros. They take same arguments as printf: format string and
 * values. By default source file name and source line are prepended to the message. Log output
 * could be redirected to any file using err_set_logfp() and err_set_logfile() functions. To disable
 * logging in your application, call err_set_logfp(NULL).
 *
 * It's possible to log multiline info messages, to do that you need to start message with
 * E_INFO and output other lines with E_INFOCONT.
 */

#ifdef __cplusplus
extern "C" {
#endif
#if 0
/* Fool Emacs. */
}
#endif

#define E_SYSCALL(stmt, ...)  if (stmt) E_FATAL_SYSTEM(__VA_ARGS__);

#define FILELINE  __FILE__ , __LINE__

/**
 * Exit with non-zero status after error message
 */
#define E_FATAL(...)                               \
    do {                                           \
        err_msg(ERR_FATAL, FILELINE, __VA_ARGS__); \
        exit(EXIT_FAILURE);                        \
    } while (0)

/**
 * Print error text; Call perror(""); exit(errno);
 */
#define E_FATAL_SYSTEM(...)                                                  \
    do {                                                                     \
        err_msg_system(ERR_FATAL, FILELINE, __VA_ARGS__);		     \
        exit(EXIT_FAILURE);                                                  \
    } while (0)

/**
 * Print error text; Call perror("");
 */
#define E_ERROR_SYSTEM(...)     err_msg_system(ERR_ERROR, FILELINE, __VA_ARGS__)

/**
 * Print error message to error log
 */
#define E_ERROR(...)     err_msg(ERR_ERROR, FILELINE, __VA_ARGS__)

/**
 * Print warning message to error log
 */
#define E_WARN(...)      err_msg(ERR_WARN, FILELINE, __VA_ARGS__)

/**
 * Print logging information to standard error stream
 */
#define E_INFO(...)      err_msg(ERR_INFO, FILELINE, __VA_ARGS__)

/**
 * Continue printing the information to standard error stream
 */
#define E_INFOCONT(...)  err_msg(ERR_INFO, NULL, 0, __VA_ARGS__)

/**
 * Print logging information without filename.
 */
#define E_INFO_NOFN(...)  err_msg(ERR_INFO, NULL, 0, __VA_ARGS__)

/**
 * Debug is disabled by default
 */
#ifdef DEBUG
#define E_DEBUG(...) err_msg(ERR_DEBUG, NULL, 0, __VA_ARGS__)
#else
#define E_DEBUG(...)
#endif

typedef enum err_e {
    ERR_DEBUG,
    ERR_INFO,
    ERR_WARN,
    ERR_ERROR,
    ERR_FATAL,
    ERR_MAX
} err_lvl_t;

void err_msg(err_lvl_t lvl, const char *path, long ln, const char *fmt, ...);

void err_msg_system(err_lvl_t lvl, const char *path, long ln, const char *fmt, ...);

void err_logfp_cb(void * user_data, err_lvl_t level, const char *fmt, ...);

typedef void (*err_cb_f)(void* user_data, err_lvl_t, const char *, ...);

/**
 * Set minimum logging level.
 *
 * @param lvl Level below which messages will not be logged (note
 * ERR_DEBUG messages are not logged unless compiled in debugging
 * mode)
 * @return previous log level.
 */
int err_set_loglevel(err_lvl_t lvl);

/**
 * Set minimum logging levelfrom a string
 *
 * @param lvl Level below which messages will not be logged (note
 * ERR_DEBUG messages are not logged unless compiled in debugging
 * mode).  A string corresponding to the names in enum err_e, but
 * without the leading "ERR_" prefix.
 * @return previous log level string, or NULL for invalid argument.
 */
const char *err_set_loglevel_str(const char *lvl);

/**
 * Sets function to output error messages. Use it to redirect the logging
 * to your application. By default the handler which dumps messages to
 * stderr is set.
 *
 * @param callback callback to pass messages too
 * @param user_data data to pass to callback
 */
void err_set_callback(err_cb_f callback, void *user_data);

/**
 * Direct all logging to a given filehandle if default logfp callback is set.
 *
 * @param stream Filehandle to send log messages to, or NULL to disable logging.
 */
void err_set_logfp(FILE *stream);

/**
 * Get the current logging filehandle.
 *
 * @return Current logging filehandle, NULL if logging is disabled. Initially
 * it returns stderr
 */
FILE *err_get_logfp(void);

/**
 * Append all log messages to a given file.
 *
 * Previous logging filehandle is closed (unless it was stdout or stderr).
 *
 * @param path File path to send log messages to
 * @return 0 for success, <0 for failure (e.g. if file does not exist)
 */
int err_set_logfile(const char *path);

#ifdef __cplusplus
}
#endif

#endif /* !_ERR_H */
