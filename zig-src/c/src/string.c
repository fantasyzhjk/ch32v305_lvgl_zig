#include <stddef.h>

void *memcpy(void *restrict dest, const void *restrict src, size_t n) {
    if (!dest || !src || n == 0) return dest;

    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;

    for (size_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
    return dest;
}

void *memset(void *s, int c, size_t n) {
    if (!s || n == 0) return s;

    unsigned char *d = (unsigned char *)s;
    unsigned char value = (unsigned char)c;

    for (size_t i = 0; i < n; i++) {
        d[i] = value;
    }
    return s;
}

void *memmove(void *dest, const void *src, size_t n) {
    if (!dest || !src || n == 0) return dest;

    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)src;

    if (d > s && d < s + n) {
        size_t i = n;
        while (i > 0) {
            i--;
            d[i] = s[i];
        }
    } else {
        for (size_t i = 0; i < n; i++) {
            d[i] = s[i];
        }
    }
    return dest;
}

int memcmp(const void *s1, const void *s2, size_t n) {
    if (!s1 || !s2 || n == 0) return 0;

    const unsigned char *p1 = (const unsigned char *)s1;
    const unsigned char *p2 = (const unsigned char *)s2;

    for (size_t i = 0; i < n; i++) {
        if (p1[i] != p2[i]) {
            return (p1[i] < p2[i]) ? -1 : 1;
        }
    }
    return 0;
}

size_t strlen(const char *s) {
    if (!s) return 0;

    size_t len = 0;
    while (s[len] != '\0') {
        len++;
    }
    return len;
}

int strcmp(const char *s1, const char *s2) {
    if (!s1 || !s2) return 0;

    size_t i = 0;
    while (s1[i] != '\0' && s1[i] == s2[i]) {
        i++;
    }

    return (unsigned char)s1[i] - (unsigned char)s2[i];
}

int strncmp(const char *s1, const char *s2, size_t n) {
    if (!s1 || !s2 || n == 0) return 0;

    for (size_t i = 0; i < n; i++) {
        if (s1[i] == '\0' || s1[i] != s2[i]) {
            return (unsigned char)s1[i] - (unsigned char)s2[i];
        }
    }
    return 0;
}