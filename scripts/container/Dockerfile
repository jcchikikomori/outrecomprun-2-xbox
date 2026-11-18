# Build environment for the SDK's Linux tools and headless harness.
# The Windows-compatible executable is built on Windows with build.bat; this image is for the Linux validation lane.
#
#   docker build -t outrun2-xbe-tools:24.04 scripts/container
#
# scripts/container.sh builds it when it is missing.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# clang/cmake/ninja build the tools; git is for FetchContent; imagemagick is the harness's TGA -> PNG step.
# The SDL/mesa development packages are only configure-time dependencies of the SDK's bundled SDL3.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        clang \
        lld \
        cmake \
        ninja-build \
        git \
        python3 \
        ca-certificates \
        pkg-config \
        imagemagick \
        libasound2-dev \
        libpulse-dev \
        libdbus-1-dev \
        libudev-dev \
        libdrm-dev \
        libgbm-dev \
    && rm -rf /var/lib/apt/lists/*

# Keep FetchContent and the build tree out of any host home directory the container may see.
ENV HOME=/tmp

WORKDIR /work
