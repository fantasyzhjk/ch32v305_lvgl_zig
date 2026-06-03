#pragma once
#include <stddef.h>
void *malloc(size_t size);
void  free(void *ptr);
void *realloc(void *ptr, size_t size);
int   abs(int x);
long  labs(long x);