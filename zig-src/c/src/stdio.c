#define NANOPRINTF_IMPLEMENTATION
#include "nanoprintf.h"

#include "stdio.h"

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