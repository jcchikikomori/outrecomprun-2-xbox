# OutRun 2 — Windows x64 cross-build of the SDK's `Game` executable, from Linux.
#
# Run it through scripts/cross-build.sh (container: scripts/cross-build-inner.sh); the build
# directory is out/build/cross-windows, the artifact out/build/cross-windows/Game.exe with the
# compiler folder out/build/cross-windows/compiler beside it.
#
# Release model (the SDK's XBE_GAME_DLL; sdk/cmake/XbeRecomp.cmake at b908ae7)
# ---------------------------------------------------------------------------
# The shipped Game.exe holds no game code. It carries the SDK runtime, this game's src/
# overrides and the XBE SHA-1; on the player's first start it recompiles the player's own
# default.xbe into Game.dll beside the executable (sdk/runtime/app/game_code.cpp) behind a
# progress window, using the compiler folder staged next to it: xbe_recomp.exe, clang.exe and
# lld-link.exe, the game's configs, the XDK layouts and the headers the generated code
# includes. Nothing is compiled while the game runs, and finished objects are kept, so a later
# start carries on where the last one stopped (IMPLEMENTATION_PLAN.md §1, §2).
#
# Why a separate project instead of the root CMakeLists.txt
# --------------------------------------------------------
# The root project includes sdk/cmake/XbeRecomp.cmake, whose add_xbe_image():
#   * builds xbe_recomp and xbe_symbols for the *target* platform, and
#   * runs xbe_recomp as a build step to regenerate generated/game.
# In a cross-build those tools are Windows PEs and cannot run on the Linux host, and this SDK
# commit (b908ae7) has no host-tools preset. So this project:
#   1. fetches the same dependencies the SDK's add_xbe_image() uses (pinned to the same tags)
#      and builds only the one host tool the release needs as a Windows PE: xbe_recomp.exe, and
#   2. uses the already-generated sources in generated/game, produced by the native Linux
#      xbe_recomp (scripts/container.sh bootstrap -> build/linux/xbe_recomp), plus the
#      imports.def that run writes for the game code DLL.
# Everything else (runtime sources, include paths, defines, link libraries, flags, the compiler
# folder's contents) mirrors add_xbe_image() and add_xbe_image_dll() at the pinned SDK commit.
# The generated C++ is platform-independent, so the same files the Linux harness uses are what
# the player's first start compiles into Game.dll.

cmake_minimum_required(VERSION 3.25)
project(outrun2_cross LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(REPO_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/..)
get_filename_component(REPO_ROOT "${REPO_ROOT}" ABSOLUTE)

# the pinned SDK submodule
set(SDK ${REPO_ROOT}/sdk)
if(NOT EXISTS ${SDK}/cmake/XbeRecomp.cmake)
    message(FATAL_ERROR "sdk/cmake/XbeRecomp.cmake is missing: run `git submodule update --init sdk`")
endif()

# --- inputs ---------------------------------------------------------------------
set(GAME_XBE ${REPO_ROOT}/assets/default.xbe)
if(NOT EXISTS ${GAME_XBE})
    message(FATAL_ERROR "assets/default.xbe is missing: extract your own disc there first "
        "(game media is never committed)")
endif()

set(CONFIG ${REPO_ROOT}/config/game.toml)
if(NOT EXISTS ${CONFIG})
    message(FATAL_ERROR "config/game.toml is missing: run scripts/container.sh bootstrap or symbols")
endif()
# partitions as xbe_symbols wrote them into config/game.toml (OutRun 2: 64)
file(STRINGS ${CONFIG} GAME_PARTITIONS REGEX "^partitions *=")
string(REGEX MATCH "[0-9]+" GAME_PARTITIONS "${GAME_PARTITIONS}")
if(NOT GAME_PARTITIONS)
    message(FATAL_ERROR "config/game.toml does not set partitions")
endif()
message(STATUS "partitions: ${GAME_PARTITIONS}")

set(GEN ${REPO_ROOT}/generated/game)
# xbe_recomp writes the game code DLL's export list next to the generated C++ when the config
# names the DLL ([xbe] library = "Game", config/outrun2.toml). The executable's import library
# is made from it, so the native lane has to have run with that config.
set(IMPORTS_DEF ${GEN}/imports.def)
if(NOT EXISTS ${IMPORTS_DEF})
    message(FATAL_ERROR "generated/game/imports.def is missing.\n"
        "Regenerate the recompiled code with the native Linux lane first: "
        "RECOMPILE=1 scripts/cross-build.sh (or scripts/container.sh recompile).")
endif()
foreach(hdr ${GEN}/x86_recomp_shared.h ${GEN}/image_symbols.h ${GEN}/hook_exports.h)
    if(NOT EXISTS ${hdr})
        message(FATAL_ERROR "generated header missing: ${hdr}\n"
            "Run the native Linux recompiler first: RECOMPILE=1 scripts/cross-build.sh.")
    endif()
endforeach()

# --- dependencies the SDK's add_xbe_image() links -------------------------------
# Same repositories and tags as sdk/cmake/XbeRecomp.cmake at b908ae7; only the
# host-tool targets are left out (xbe_symbols is not part of a release).
include(FetchContent)
set(ZYDIS_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(ZYDIS_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(ZYDIS_BUILD_DOXYGEN OFF CACHE BOOL "" FORCE)
FetchContent_Declare(zydis GIT_REPOSITORY https://github.com/zyantific/zydis.git GIT_TAG v4.1.1 GIT_SHALLOW TRUE)
FetchContent_Declare(tomlplusplus GIT_REPOSITORY https://github.com/marzer/tomlplusplus.git GIT_TAG v3.4.0 GIT_SHALLOW TRUE)
FetchContent_Declare(imgui GIT_REPOSITORY https://github.com/ocornut/imgui.git GIT_TAG v1.91.0 GIT_SHALLOW TRUE)
# SDL3 for controllers, static so it links into the exe
set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_RENDER OFF CACHE BOOL "" FORCE)
set(SDL_GPU OFF CACHE BOOL "" FORCE)
set(SDL_CAMERA OFF CACHE BOOL "" FORCE)
FetchContent_Declare(SDL3 GIT_REPOSITORY https://github.com/libsdl-org/SDL.git GIT_TAG release-3.4.16 GIT_SHALLOW TRUE)
FetchContent_MakeAvailable(zydis tomlplusplus imgui SDL3)

# --- the compiler folder the release carries ------------------------------------
# Mirrors sdk/cmake/XbeRecomp.cmake:29-59: what the game needs to build its code on the
# player's PC, beside the executables.
set(XBE_COMPILER_DIR ${CMAKE_CURRENT_BINARY_DIR}/compiler)

# A game with a build per disc sets XBE_GAME_CONFIGS to this disc's configs: the generated one
# (partitions, path, symbols) and the hand-kept one that includes it and names the game code DLL
# ([xbe] library = "Game", which app/game_code.cpp's ConfigFor() looks for). config/*.sha1 is
# not read: the executable compares the SHA-1 it carries with the xbe it finds.
set(XBE_GAME_CONFIGS ${REPO_ROOT}/config/game.toml ${REPO_ROOT}/config/outrun2.toml)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${XBE_GAME_CONFIGS})

# clang.exe and lld-link.exe run on the player's Windows PC, so they have to be Windows PEs. A
# Windows build host has them in its toolchain's bin beside clang-cl (the SDK's XBE_LLVM_BIN);
# this Linux cross-build host does not (its clang-20 and lld-link-20 are ELF), so a Windows LLVM
# distribution's bin folder is used instead — cross/fetch-llvm-windows.sh fetches the pinned one
# and scripts/cross-build.sh runs it.
get_filename_component(XBE_LLVM_BIN ${CMAKE_CXX_COMPILER} DIRECTORY)
set(XBE_LLVM_WINDOWS_DIR "${XBE_LLVM_WINDOWS_DIR}" CACHE PATH
    "bin folder of a Windows LLVM distribution: clang.exe and lld-link.exe for the release's compiler folder")
if(NOT XBE_LLVM_WINDOWS_DIR)
    if(DEFINED ENV{XBE_LLVM_WINDOWS_DIR})
        set(XBE_LLVM_WINDOWS_DIR "$ENV{XBE_LLVM_WINDOWS_DIR}")
    else()
        set(XBE_LLVM_WINDOWS_DIR ${REPO_ROOT}/.local/llvm-windows/bin)
    endif()
endif()
if(EXISTS ${XBE_LLVM_BIN}/clang.exe AND EXISTS ${XBE_LLVM_BIN}/lld-link.exe)
    set(XBE_COMPILER_CLANG ${XBE_LLVM_BIN}/clang.exe)
    set(XBE_COMPILER_LLD ${XBE_LLVM_BIN}/lld-link.exe)
elseif(EXISTS ${XBE_LLVM_WINDOWS_DIR}/clang.exe AND EXISTS ${XBE_LLVM_WINDOWS_DIR}/lld-link.exe)
    set(XBE_COMPILER_CLANG ${XBE_LLVM_WINDOWS_DIR}/clang.exe)
    set(XBE_COMPILER_LLD ${XBE_LLVM_WINDOWS_DIR}/lld-link.exe)
else()
    message(FATAL_ERROR "the release's compiler folder needs a Windows clang.exe and lld-link.exe, "
        "and neither ${XBE_LLVM_BIN} nor ${XBE_LLVM_WINDOWS_DIR} has them.\n"
        "Fetch them: cross/fetch-llvm-windows.sh (scripts/cross-build.sh runs it), or point "
        "-DXBE_LLVM_WINDOWS_DIR at your own Windows LLVM's bin folder.")
endif()
# the two files above are copied into the release as they are, so a mistake here is shipped
foreach(tool ${XBE_COMPILER_CLANG} ${XBE_COMPILER_LLD})
    file(READ ${tool} tool_magic LIMIT 2 HEX)
    if(NOT tool_magic STREQUAL "4d5a")  # "MZ"
        message(FATAL_ERROR "${tool} is not a Windows executable: the release's compiler folder must hold "
            "Windows PEs, which the player's PC runs. See XBE_LLVM_WINDOWS_DIR above.")
    endif()
endforeach()

set(XBE_COMPILER_HEADERS ${SDK}/runtime/cpu/x86_ops.h ${SDK}/runtime/cpu/x86_context.h)
file(GLOB XBE_FREESTANDING_HEADERS CONFIGURE_DEPENDS ${SDK}/runtime/cpu/freestanding/*)
file(GLOB XBE_LAYOUTS CONFIGURE_DEPENDS ${SDK}/xdk/*/layout.toml)
set(XBE_COPY_LAYOUTS)
foreach(layout ${XBE_LAYOUTS})
    get_filename_component(build_dir ${layout} DIRECTORY)
    get_filename_component(build ${build_dir} NAME)
    list(APPEND XBE_COPY_LAYOUTS COMMAND ${CMAKE_COMMAND} -E make_directory ${XBE_COMPILER_DIR}/xdk/${build}
         COMMAND ${CMAKE_COMMAND} -E copy_if_different ${layout} ${XBE_COMPILER_DIR}/xdk/${build})
endforeach()
add_custom_target(compiler_files ALL
    COMMAND ${CMAKE_COMMAND} -E make_directory ${XBE_COMPILER_DIR}/config ${XBE_COMPILER_DIR}/include/cpu
            ${XBE_COMPILER_DIR}/include/freestanding
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${XBE_COMPILER_CLANG} ${XBE_COMPILER_DIR}/clang.exe
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${XBE_COMPILER_LLD} ${XBE_COMPILER_DIR}/lld-link.exe
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${SDK}/tools/LLVM-LICENSE.txt ${XBE_COMPILER_DIR}
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${XBE_GAME_CONFIGS} ${XBE_COMPILER_DIR}/config
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${XBE_COMPILER_HEADERS} ${XBE_COMPILER_DIR}/include/cpu
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${XBE_FREESTANDING_HEADERS} ${XBE_COMPILER_DIR}/include/freestanding
    ${XBE_COPY_LAYOUTS}
    VERBATIM)

# x86 to C++ recompiler, as a Windows PE: the player's first start runs it (app/game_code.cpp
# Translate()). The Linux lane's copy (build/linux/xbe_recomp) is what regenerates generated/game.
file(GLOB XBE_RECOMP_SOURCES CONFIGURE_DEPENDS ${SDK}/tools/recomp/*.cpp)
add_executable(xbe_recomp ${XBE_RECOMP_SOURCES})
set_target_properties(xbe_recomp PROPERTIES RUNTIME_OUTPUT_DIRECTORY ${XBE_COMPILER_DIR})
target_include_directories(xbe_recomp PRIVATE ${SDK}/runtime ${SDK}/tools/recomp)
target_compile_definitions(xbe_recomp PRIVATE _CRT_SECURE_NO_WARNINGS)
target_link_libraries(xbe_recomp PRIVATE Zydis tomlplusplus::tomlplusplus)

# The executable looks the recompiled bodies up in Game.dll, which only exists after the
# player's first start: its import library is made from the generated imports.def, as
# add_xbe_image_dll() does at build time with the toolchain's lld-link.
add_custom_command(OUTPUT ${GEN}/code.lib
    COMMAND ${CMAKE_LINKER} /lib /machine:x64 /def:${IMPORTS_DEF} /out:${GEN}/code.lib
    DEPENDS ${IMPORTS_DEF}
    COMMENT "Creating the game code DLL's import library"
    VERBATIM)
add_custom_target(code_lib DEPENDS ${GEN}/code.lib)

# --- game sources ---------------------------------------------------------------
file(GLOB XBE_HOST_SOURCES CONFIGURE_DEPENDS ${REPO_ROOT}/src/*/*.cpp)
list(FILTER XBE_HOST_SOURCES EXCLUDE REGEX "/src/game/")
file(GLOB GAME_SOURCES CONFIGURE_DEPENDS ${REPO_ROOT}/src/game/*.cpp)

set(XBE_IMGUI_SOURCES
    ${imgui_SOURCE_DIR}/imgui.cpp
    ${imgui_SOURCE_DIR}/imgui_draw.cpp
    ${imgui_SOURCE_DIR}/imgui_tables.cpp
    ${imgui_SOURCE_DIR}/imgui_widgets.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_win32.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_dx12.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_dx11.cpp
    ${imgui_SOURCE_DIR}/backends/imgui_impl_dx9.cpp)

# the settings window reads controllers from the runtime's SDL input (app::FeedPad), not XInput
set_source_files_properties(${imgui_SOURCE_DIR}/backends/imgui_impl_win32.cpp PROPERTIES
    COMPILE_DEFINITIONS IMGUI_IMPL_WIN32_DISABLE_GAMEPAD)

file(GLOB XBE_RUNTIME_SOURCES CONFIGURE_DEPENDS ${SDK}/runtime/*/*.cpp)
# SDL's headers go to the input code alone (it is linked LINK_ONLY), so the generated sources' compile line stays the same
set_source_files_properties(${SDK}/runtime/core/input.cpp PROPERTIES INCLUDE_DIRECTORIES "${sdl3_SOURCE_DIR}/include")

# the xbe's SHA-1: the executable checks the game it finds is the release it was made from
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${GAME_XBE})
file(SHA1 ${GAME_XBE} xbe_sha1)
set(XBE_HASH ${CMAKE_CURRENT_BINARY_DIR}/Game_xbe.cpp)
file(CONFIGURE OUTPUT ${XBE_HASH} CONTENT "extern const char kImageSha1[] = \"${xbe_sha1}\";\n")

# --- the executable -------------------------------------------------------------
# No generated C++ here: the game's code is the DLL the player's first start builds. XBE_GAME_DLL
# selects that half of the SDK (runtime/app/game_code.cpp, cpu/dispatch.cpp, cpu/x86_ops.h) and
# exports the runtime and this game's overrides, which the DLL imports back.
add_executable(Game WIN32 ${XBE_RUNTIME_SOURCES} ${XBE_HOST_SOURCES} ${GAME_SOURCES}
    ${XBE_IMGUI_SOURCES} ${XBE_HASH})
add_dependencies(Game compiler_files xbe_recomp code_lib)
# the import library of what the executable exports to its DLL goes to the compiler folder
set_target_properties(Game PROPERTIES ENABLE_EXPORTS ON ARCHIVE_OUTPUT_DIRECTORY ${XBE_COMPILER_DIR})
target_include_directories(Game PRIVATE ${REPO_ROOT}/src ${SDK}/runtime ${GEN})
target_include_directories(Game SYSTEM PRIVATE ${imgui_SOURCE_DIR})
target_compile_options(Game PRIVATE -fno-strict-aliasing)
target_compile_definitions(Game PRIVATE XBE_GAME_DLL UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
target_link_libraries(Game PRIVATE tomlplusplus::tomlplusplus $<LINK_ONLY:SDL3::SDL3-static> d3d12 d3d11 dinput8 dxgi dxguid d3dcompiler xaudio2 ole32 windowscodecs dbghelp winmm dwmapi ws2_32)
target_link_libraries(Game PRIVATE ${GEN}/code.lib delayimp)
# Game.dll does not exist before the player's first start has built it: delay-loading lets the
# executable start with the runtime and app/game_code.cpp build it
target_link_options(Game PRIVATE -fuse-ld=lld -g -Xlinker /delayload:Game.dll)

# launcher/icon.ico, when there is one: the game's icon too (resource 1, which the window class loads)
if(WIN32 AND EXISTS ${REPO_ROOT}/launcher/icon.ico)
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/game_icon.rc "1 ICON \"${REPO_ROOT}/launcher/icon.ico\"\n")
    target_sources(Game PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/game_icon.rc)
endif()
