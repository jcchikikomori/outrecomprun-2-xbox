# Cross-compiles the Windows x64 target on a Linux host: clang-cl (Clang >= 19) and
# lld-link against Microsoft's CRT and Windows SDK, downloaded and laid out by xwin
# (https://github.com/Jake-Shadle/xwin).
#
# Used by cross/CMakeLists.txt through scripts/cross-build.sh. The one-time setup is
# done by scripts/cross-build-inner.sh:
#
#   xwin --accept-license --arch x86_64 --cache-dir .local/xwin/cache \
#       splat --use-winsysroot-style --preserve-ms-arch-notation \
#       --output .local/xwin/sysroot
#
# XWIN_DIR, as a cache variable or environment variable, points at that output.
# Modelled on abilliontokens/fuzionfrenzy-recomp cmake/windows-cross.cmake.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_VERSION 10.0)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

if(NOT XWIN_DIR)
    if(DEFINED ENV{XWIN_DIR})
        set(XWIN_DIR "$ENV{XWIN_DIR}")
    else()
        set(XWIN_DIR "${CMAKE_CURRENT_LIST_DIR}/../.local/xwin/sysroot")
    endif()
endif()
set(XWIN_DIR "${XWIN_DIR}" CACHE PATH "xwin splat output in the /winsysroot layout (VC/Tools/MSVC, Windows Kits/10)")
if(NOT IS_DIRECTORY "${XWIN_DIR}/VC/Tools/MSVC" OR NOT IS_DIRECTORY "${XWIN_DIR}/Windows Kits/10/Lib")
    message(FATAL_ERROR "XWIN_DIR=\"${XWIN_DIR}\" is not an xwin splat made with --use-winsysroot-style "
        "--preserve-ms-arch-notation (see the top of ${CMAKE_CURRENT_LIST_FILE})")
endif()
# try_compile projects re-read this file without the cache
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES XWIN_DIR)
# xwin lays out the release CRT only (no msvcrtd.lib), so CMake's own test programs must not be Debug
set(CMAKE_TRY_COMPILE_CONFIGURATION Release)

# The LLVM 20 packages from apt.llvm.org keep their versioned names; the container image
# installs llvm-20, lld-20 and clang-20 (scripts/container/Dockerfile.cross).
find_program(CLANG_CL NAMES clang-cl-20 clang-cl-19 clang-cl REQUIRED)
find_program(LLD_LINK NAMES lld-link-20 lld-link-19 lld-link REQUIRED)
find_program(LLVM_LIB NAMES llvm-lib-20 llvm-lib-19 llvm-lib REQUIRED)
find_program(LLVM_RC NAMES llvm-rc-20 llvm-rc-19 llvm-rc REQUIRED)
find_program(LLVM_MT NAMES llvm-mt-20 llvm-mt-19 llvm-mt REQUIRED)
set(CMAKE_C_COMPILER "${CLANG_CL}")
set(CMAKE_CXX_COMPILER "${CLANG_CL}")
# lld-link, not link.exe: it keeps the recompiled weak functions overridable by the host ones
set(CMAKE_LINKER "${LLD_LINK}")
set(CMAKE_AR "${LLVM_LIB}")
set(CMAKE_RC_COMPILER "${LLVM_RC}")
set(CMAKE_MT "${LLVM_MT}")
set(CMAKE_C_COMPILER_TARGET x86_64-pc-windows-msvc)
set(CMAKE_CXX_COMPILER_TARGET x86_64-pc-windows-msvc)

# the _INIT forms: CMake appends its MSVC defaults (/DWIN32 /D_WINDOWS /GR /EHsc) to these, where
# setting CMAKE_<LANG>_FLAGS itself would replace them. -march matches the native Windows presets.
set(CMAKE_C_FLAGS_INIT "/winsysroot \"${XWIN_DIR}\" -march=x86-64-v2")
set(CMAKE_CXX_FLAGS_INIT "/winsysroot \"${XWIN_DIR}\" -march=x86-64-v2")
# CMake links with CMAKE_LINKER directly (vs_link_exe), so the sysroot has to reach
# lld-link as well; LLD >= 19 understands /winsysroot:
foreach(kind EXE SHARED MODULE)
    set(CMAKE_${kind}_LINKER_FLAGS_INIT "/winsysroot:\"${XWIN_DIR}\"")
endforeach()

# headers and libraries come from the Windows sysroot only; programs (host tools) from this machine
set(CMAKE_FIND_ROOT_PATH "${XWIN_DIR}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
