#pragma once

#include <stdarg.h>
#include <stddef.h>

int printf(const char *fmt, ...);
int snprintf(char *buffer, size_t bufsz, const char *fmt, ...);
int vsnprintf(char *buffer, size_t bufsz, const char *fmt, va_list vlist);