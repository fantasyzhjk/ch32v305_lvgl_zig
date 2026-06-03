#include "stdio.h"

#define NANOPRINTF_IMPLEMENTATION
#include "nanoprintf.h"

#define NANOPRINTF_USE_FIELD_WIDTH_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_PRECISION_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_FLOAT_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_LARGE_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_BINARY_FORMAT_SPECIFIERS 0
#define NANOPRINTF_USE_WRITEBACK_FORMAT_SPECIFIERS 0

extern int _write(int fd, char *buf, int size);

static void uart_putc(int c, void *ctx)
{
    (void)ctx;

    char ch = (char)c;
    _write(1, &ch, 1);
}

int printf(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);

    int ret = npf_vpprintf(uart_putc, NULL, fmt, args);

    va_end(args);
    return ret;
}


int vsnprintf(
    char *buffer,
    size_t count,
    const char *fmt,
    va_list args)
{
    return npf_vsnprintf(
        buffer,
        count,
        fmt,
        args);
}

int snprintf(
    char *buffer,
    size_t count,
    const char *fmt,
    ...)
{
    va_list args;
    va_start(args, fmt);

    int ret = npf_vsnprintf(
        buffer,
        count,
        fmt,
        args);

    va_end(args);

    return ret;
}