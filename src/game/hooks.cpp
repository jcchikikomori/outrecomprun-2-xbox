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

#include "xdk/hle.h"

// 0x00195D09, before `MOV EAX,dword ptr [ESI]`, inside FUN_00195CF0
// (D3DDevice_DrawIndexedVerticesUP: prim, count, indices, base, stride).
//
// FUN_00195CF0 runs as guest code, but the library routines that fill the CDevice's cached vertex
// layout no longer do: the SDK's HLE bodies for D3DDevice_SetVertexShader (0x196DF0) and
// D3DDevice_SetStreamSource (0x1969D0) replace the guest ones. Those bodies call FUN_00196200 to
// build the FVF declaration object at 0x001A67C8 and FUN_0019E9E0 to cache it in the device:
//   +0xBC8 0x001A4D18  total vertex size in dwords   (the divisor at 0x00195D6B)
//   +0xBCC 0x001A4D1C  first input's byte offset
//   +0xBD0 0x001A4D20  first offset minus the end offset (-stride)
//   +0xBD4 0x001A4D24  input size in dwords, then gaps (size, gap pairs)
//   +0xC54 0x001A4DA4  input count
// With the HLE in place the cache stays 0, so the first indexed user-pointer draw of 17 or more
// indices divides 0x7FF by zero: the OUTRUN MODE banner's 0x46-index draw at 0x0002AE36 (through
// FUN_0002AB40 0x00195CF0(6,0x46,...,0x28)) is the first such draw.
//
// A user-pointer draw has one interleaved stream of the caller's stride (the fifth argument), and
// for FVF 0x1D2 the declaration FUN_00196200 builds adds up to exactly that stride: 3+3+1+1+2
// dwords = 0x28 bytes. Describe that one stream, which is what FUN_0019E9E0 would have cached.
void FixIndexedVerticesUpLayout(X86Context& ctx, uint8_t* base) {
    (void)base;
    const uint32_t stride = kernel::R32(ctx.ebp + 0x18);  // arg 4: vertex stride in bytes
    if (stride == 0 || (stride & 3)) return;      // no usable layout: leave the guest state alone
    const uint32_t dwords = stride / 4;
    kernel::W32(0x001A4D18, dwords);
    kernel::W32(0x001A4D1C, 0);
    kernel::W32(0x001A4D20, 0u - stride);
    kernel::W32(0x001A4D24, dwords);
    kernel::W32(0x001A4D28, 0);
    kernel::W32(0x001A4DA4, 1);
    LOGR_FIRST(1, "hooks: 00195CF0 vertex layout %u dwords (stride %u), cached at 001A4D18", dwords, stride);
}
