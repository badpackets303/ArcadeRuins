# s1engine — the portable synth engine (X1, ADR-057).
#
# Two targets:
#   soundpipe  the vendored C DSP primitives, compiled IN PLACE from Sources/Soundpipe.
#              Nothing is copied or moved: the Xcode targets compile the same files.
#   s1engine   our C++17 engine. X1-2 … X1-6 move the kernel, note state, sequencer, rate,
#              tunings, presets and wavetables in here as each is freed of Apple code.
#
# No Apple headers, no Objective-C, anywhere under this directory or Sources/Soundpipe:
# Tests/Engine/NoAppleHeaders.cmake enforces it.

set(SOUNDPIPE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/../Soundpipe)

# Listed, not globbed: a module added to the directory and not to this list is a link error in
# the portable build, which is the prompt to add it to VENDORING.md too.
set(SOUNDPIPE_MODULES
    adsr base butbp buthp compressor crossfade delay fosc ftbl moogladder noise osc
    oscmorph2d pan2 phaser phasor port randmt revsc vdelay)
list(TRANSFORM SOUNDPIPE_MODULES PREPEND ${SOUNDPIPE_DIR}/modules/)
list(TRANSFORM SOUNDPIPE_MODULES APPEND .c)

# Leave this alone in anything that ships (the reason is at s1engine's options, below).
# `-DS1_FP_CONTRACT=off` exists to reproduce, on an Apple Silicon Mac, the arithmetic of a
# machine without fused multiply-add — which is how X1-7 studied what Linux and Windows measure.
set(S1_FP_CONTRACT "on" CACHE STRING "Clang/GCC -ffp-contract for the engine: on (ship) or off (study)")

add_library(soundpipe STATIC ${SOUNDPIPE_MODULES})
target_include_directories(soundpipe PUBLIC
    ${SOUNDPIPE_DIR}/include
    ${SOUNDPIPE_DIR}/lib/faust
    # soundpipe.h declares sp_wavin, whose struct needs dr_wav's types. Declarations only.
    ${SOUNDPIPE_DIR}/lib/dr_wav)
# Same definition project.yml gives the Xcode target: libsndfile is only for file I/O we never use.
target_compile_definitions(soundpipe PUBLIC NO_LIBSNDFILE=1)
if(MSVC)
    # Vendored third-party C: warnings off, as GCC_WARN_INHIBIT_ALL_WARNINGS does in Xcode.
    target_compile_options(soundpipe PRIVATE /w)
    target_compile_definitions(soundpipe PRIVATE _CRT_SECURE_NO_WARNINGS _USE_MATH_DEFINES)
else()
    # -ffp-contract=on: see the note on s1engine's options below (X1-7, ADR-071).
    target_compile_options(soundpipe PRIVATE -w -ffp-contract=${S1_FP_CONTRACT})
    find_library(MATH_LIBRARY m)
    if(MATH_LIBRARY)
        target_link_libraries(soundpipe PUBLIC ${MATH_LIBRARY})
    endif()
endif()

# NO -ffast-math, NO /fp:fast, anywhere. The golden renders (X1-7) compare against the Xcode
# build's output; value-changing float optimisations are how two builds of one engine drift.
set(S1ENGINE_SOURCES
    S1EngineInfo.cpp
    Kernel/S1DSPKernel.cpp
    Kernel/S1DSPKernel+MIDI.cpp
    Kernel/S1DSPKernel+destroy.cpp
    Kernel/S1DSPKernel+prepare.cpp
    Kernel/S1DSPKernel+didChanges.cpp
    Kernel/S1DSPKernel+events.cpp
    Kernel/S1DSPKernel+getSetDependentParameters.cpp
    Kernel/S1DSPKernel+getSetSynthParameters.cpp
    Kernel/S1DSPKernel+parameters.cpp
    Kernel/S1DSPKernel+process.cpp
    Kernel/S1DSPKernel+reset.cpp
    Kernel/S1DSPKernel+setup.cpp
    Kernel/S1DSPKernel+startStopNotes.cpp
    Kernel/S1DSPKernel+tapers.cpp
    Kernel/S1DSPKernel+toggleKeys.cpp
    Kernel/S1HostMIDI.cpp
    "Note State/S1NoteState.cpp"
    Sequencer/S1Sequencer.cpp
    Tunings/S1TuningTable.cpp
    Tunings/S1Scala.cpp
    Tunings/S1FactoryTunings.cpp
    Presets/S1Preset.cpp
    Wavetables/S1Wavetables.cpp)

add_library(s1engine STATIC ${S1ENGINE_SOURCES})
# The same directories the Xcode target searches (project.yml HEADER_SEARCH_PATHS), so every
# include line is the same file in both builds.
target_include_directories(s1engine PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/Kernel
    "${CMAKE_CURRENT_SOURCE_DIR}/Note State"
    ${CMAKE_CURRENT_SOURCE_DIR}/Sequencer
    ${CMAKE_CURRENT_SOURCE_DIR}/Rate
    ${CMAKE_CURRENT_SOURCE_DIR}/Tunings
    ${CMAKE_CURRENT_SOURCE_DIR}/Presets
    ${CMAKE_CURRENT_SOURCE_DIR}/Wavetables)
target_link_libraries(s1engine PUBLIC soundpipe)
target_compile_features(s1engine PUBLIC cxx_std_17)
# Warnings: on, and errors for the files we own outright. The ported kernel is compiled with
# warnings on but not as errors — it is upstream's code, kept as close to upstream as the port
# allows (CLAUDE.md: minimal diffs), and it carries upstream's unused variables and sign
# comparisons. Read them; do not "fix" the kernel to silence them.
if(MSVC)
    target_compile_options(s1engine PRIVATE /W3 /permissive- /fp:precise /utf-8)
    target_compile_definitions(s1engine PRIVATE _USE_MATH_DEFINES)   # M_PI in the LFO code
    set_source_files_properties(S1EngineInfo.cpp PROPERTIES COMPILE_OPTIONS "/W4;/WX")
else()
    # -Wno-missing-field-initializers: the 150-row parameter table leaves `portamento` and
    # `portamentoTarget` to be filled in at setup, on purpose.
    # -ffp-contract=on, spelled out (X1-7, ADR-071; it was `off` from X1-1 until the harness
    # measured it). It is Clang's default and therefore what the Xcode build — the shipped
    # product, and the goldens — has always had: on arm64 a*b+c within one expression is one
    # fused multiply-add. With `off`, this same machine reproduced 3 of 20 goldens; with `on`,
    # 20 of 20, bit for bit. x86-64 has no FMA in its baseline, so there the flag changes
    # nothing and the renders differ from the goldens in the last bits either way — that is
    # what GoldenHarness's tolerances are for.
    target_compile_options(s1engine PRIVATE -Wall -Wextra -Wno-missing-field-initializers -ffp-contract=${S1_FP_CONTRACT})
    set_source_files_properties(S1EngineInfo.cpp PROPERTIES COMPILE_OPTIONS "-Wpedantic;-Werror")
endif()
