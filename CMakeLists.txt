# Arcade Ruins — the portable build (cross-platform plan, ADR-057).
#
# This builds the engine and its tests with CMake on macOS, Windows and Linux. It does NOT build
# the Catalyst app or the AUv3: those are XcodeGen's (project.yml, Scripts/build.sh), and neither
# build system drives the other.
#
#   cmake -S . -B build/engine && cmake --build build/engine && ctest --test-dir build/engine
#   cmake -S . -B build/plugin -DS1_BUILD_PLUGIN=ON && cmake --build build/plugin      (X2: + the JUCE plugin)
cmake_minimum_required(VERSION 3.22)
# 1.0.0 is the CROSS-PLATFORM product's number (the owner, 2026-09-21: "the new version should be
# 1.0"). Classic — the Catalyst app and its AUv3 — keeps its own in project.yml, at 0.5.0, so the
# two downloads cannot be confused for one another. ADR-092, ADR-095.
project(ArcadeRuins VERSION 1.1.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)   # the library ends up inside plugin bundles (X2)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release)
endif()

# X2-8 (ADR-079): the RealtimeSanitizer build — Clang 20 or later. The render entry points are
# marked [[clang::nonblocking]] (S1_NONBLOCKING) only here; whatever they reach that allocates,
# locks or blocks stops the test with a stack. One CI job (`plugin.yml`, realtime-sanitizer).
option(S1_RTSAN "Build with -fsanitize=realtime and mark the render entry points nonblocking" OFF)
if(S1_RTSAN)
    add_compile_definitions(S1_RTSAN)
    add_compile_options(-fsanitize=realtime -fno-omit-frame-pointer -Wno-perf-constraint-implies-noexcept)
    add_link_options(-fsanitize=realtime)
endif()

add_subdirectory(Sources/S1Engine)

# X2 (ADR-072): the JUCE plugin. OFF by default — it fetches JUCE and compiles it, and the
# engine's build and CI (`engine.yml`) should stay a minute long. `plugin.yml` turns it on.
option(S1_BUILD_PLUGIN "Build the JUCE plugin (VST3 + Standalone); fetches JUCE" OFF)
if(S1_BUILD_PLUGIN)
    add_subdirectory(Sources/S1Plugin)
endif()

include(CTest)
# Every test executable and nothing else (not the .vst3, not the standalone): what a sanitizer
# build makes — `cmake --build … --target S1AllTests`. New tests join it where they are declared.
add_custom_target(S1AllTests)
if(BUILD_TESTING)
    add_subdirectory(Tests/Engine)
    if(S1_BUILD_PLUGIN)
        add_subdirectory(Tests/Plugin)
    endif()
endif()
