#define DASM_CHECKS 1
int (*DASM_EXTERN_FUNC)(void *ctx, unsigned char *addr, unsigned int idx, int type);
#define DASM_EXTERN(ctx, addr, idx, type) DASM_EXTERN_FUNC(ctx, addr, idx, type)

#include "dasm_proto.h"
#include "dasm_x86.h"
