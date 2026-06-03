#pragma once
#ifdef NDEBUG
    #define assert(expr) ((void)0)
#else
    #define assert(expr) \
        ((expr) ? (void)0 : __builtin_trap())
#endif