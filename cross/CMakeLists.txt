# OutRun 2 — Windows x64 cross-build of the SDK's `Game` executable, from Linux.
#
# Run it through scripts/cross-build.sh (container: scripts/cross-build-inner.sh); the
# build directory is out/build/cross-windows and the artifact out/build/cross-windows/Game.exe.
#
# Developer model only: XBE_GAME_DLL is never defined, so the 64 recompiled partitions
# link into the executable (there is no release / first-start DLL build here).
#
# Why a separate project instead of the root CMakeLists.txt
# --------------------------------------------------------
# The root project includes sdk/cmake/XbeRecomp.cmake, whose add_xbe_image():
#   * builds xbe_recomp and xbe_symbols for the *target* platform, and
#   * runs xbe_recomp as a build step to regenerate generated/game.
# In a cross-build those tools are Windows PEs and cannot run on the Linux host, and
# this SDK commit (b908ae7) has no host-tools preset. So this project:
#   1. fetches the same dependencies the SDK's add_xbe_image() uses (pinned to the same
#      tags) without adding the host-tool targets, and
#   2. compiles the already-generated sources in generated/game, produced by the native
#      Linux xbe_recomp (scripts/container.sh bootstrap -> build/linux/xbe_recomp).
# Everything else (runtime sources, include paths, defines, link libraries, flags)
# mirrors add_xbe_image() at the pinned SDK commit. The generated C++ is
# platform-independent, so the same files the Linux harness uses build this PE.

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
set(GEN_SOURCES ${GEN}/x86_func_mapping.cpp)
math(EXPR last "${GAME_PARTITIONS} - 1")
foreach(i RANGE ${last})
    list(APPEND GEN_SOURCES ${GEN}/x86_recomp.${i}.cpp)
endforeach()
foreach(src ${GEN_SOURCES} ${GEN}/x86_recomp_shared.h ${GEN}/image_symbols.h)
    if(NOT EXISTS ${src})
        message(FATAL_ERROR "generated source missing: ${src}\n"
            "Run the native Linux recompiler first: scripts/container.sh bootstrap "
            "(or tools + recompile).")
    endif()
endforeach()

# --- dependencies the SDK's add_xbe_image() links -------------------------------
# Same repositories and tags as sdk/cmake/XbeRecomp.cmake at b908ae7; only the
# host-tool targets are left out.
include(FetchContent)
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
FetchContent_MakeAvailable(tomlplusplus imgui SDL3)

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
    ${imgui_SOURCE_DIR}/backends/imgui_impl_dx11.cpp)

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

set_source_files_properties(${GEN_SOURCES} PROPERTIES GENERATED TRUE
    COMPILE_OPTIONS "-O2;-fno-strict-aliasing;-Wno-unused-label;-Wno-parentheses-equality;-Wno-unused-variable")

# --- the executable -------------------------------------------------------------
add_executable(Game WIN32 ${XBE_RUNTIME_SOURCES} ${XBE_HOST_SOURCES} ${GAME_SOURCES}
    ${GEN_SOURCES} ${XBE_IMGUI_SOURCES} ${XBE_HASH})
target_include_directories(Game PRIVATE ${REPO_ROOT}/src ${SDK}/runtime ${GEN})
target_include_directories(Game SYSTEM PRIVATE ${imgui_SOURCE_DIR})
target_compile_options(Game PRIVATE -fno-strict-aliasing)
target_compile_definitions(Game PRIVATE UNICODE _UNICODE _CRT_SECURE_NO_WARNINGS)
target_link_libraries(Game PRIVATE tomlplusplus::tomlplusplus $<LINK_ONLY:SDL3::SDL3-static> d3d12 d3d11 dinput8 dxgi dxguid d3dcompiler xaudio2 ole32 windowscodecs dbghelp winmm dwmapi ws2_32)
# lld keeps the recompiled weak functions overridable by the host ones
target_link_options(Game PRIVATE -fuse-ld=lld -g)

# launcher/icon.ico, when there is one: the game's icon too (resource 1, which the window class loads)
if(WIN32 AND EXISTS ${REPO_ROOT}/launcher/icon.ico)
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/game_icon.rc "1 ICON \"${REPO_ROOT}/launcher/icon.ico\"\n")
    target_sources(Game PRIVATE ${CMAKE_CURRENT_BINARY_DIR}/game_icon.rc)
endif()
