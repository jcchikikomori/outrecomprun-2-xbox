// Hooks for OutRun 2's default.xbe (title 53450036, XDK 5849, 64 partitions).
// A strong definition replaces the recompiled function at that address, for example:
//
// #include "xdk/hle.h"
//
// X86_EXTERN_FUNC(__imp__sub_00012345);
// X86_FUNC(sub_00012345) {
//     __imp__sub_00012345(ctx, base);  // the original
// }
//
// Instruction-level hooks are declared in config/outrun2.toml ([[hook]]) and implemented here.
