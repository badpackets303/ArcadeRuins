# Tests for the portable engine. Plain executables, no test framework: a failed check prints
# what it measured and the process exits non-zero, which is all CTest needs.
add_executable(SoundpipeBehaviourTests SoundpipeBehaviourTests.cpp)
target_link_libraries(SoundpipeBehaviourTests PRIVATE s1engine)
add_test(NAME SoundpipeBehaviour COMMAND SoundpipeBehaviourTests)

add_executable(HeldNotesTests HeldNotesTests.cpp)
target_link_libraries(HeldNotesTests PRIVATE s1engine)
find_package(Threads REQUIRED)
target_link_libraries(HeldNotesTests PRIVATE Threads::Threads)
add_test(NAME HeldNotes COMMAND HeldNotesTests)

add_executable(KernelEventTests KernelEventTests.cpp)
target_link_libraries(KernelEventTests PRIVATE s1engine)
add_test(NAME KernelEvents COMMAND KernelEventTests)

# X2-4 (ADR-075): the host MIDI router against what the standalone's Swift chain plays — a fixture
# HostMIDIParityTests writes and guards (Scripts/write-host-midi-fixtures.sh).
add_executable(HostMIDITests HostMIDITests.cpp)
target_link_libraries(HostMIDITests PRIVATE s1engine)
add_test(NAME HostMIDI COMMAND HostMIDITests ${CMAKE_CURRENT_SOURCE_DIR}/Fixtures/host-midi.txt)

# X1-1's standing rule, as a test: nothing Apple under the engine or Soundpipe. A CMake script
# rather than grep, so it runs the same on Windows.
add_test(NAME NoAppleHeaders
    COMMAND ${CMAKE_COMMAND}
        -DROOTS=${CMAKE_SOURCE_DIR}/Sources/S1Engine|${CMAKE_SOURCE_DIR}/Sources/Soundpipe
        -P ${CMAKE_CURRENT_SOURCE_DIR}/NoAppleHeaders.cmake)

add_executable(TuningTableTests TuningTableTests.cpp)
target_link_libraries(TuningTableTests PRIVATE s1engine)
add_test(NAME TuningTable COMMAND TuningTableTests ${CMAKE_CURRENT_SOURCE_DIR}/Fixtures/factory-tunings.txt)

add_executable(PresetTests PresetTests.cpp)
target_link_libraries(PresetTests PRIVATE s1engine)
add_test(NAME Presets COMMAND PresetTests
    ${CMAKE_CURRENT_SOURCE_DIR}/Fixtures/factory-presets.txt
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/Presets/Data")

add_executable(WavetableTests WavetableTests.cpp)
target_link_libraries(WavetableTests PRIVATE s1engine)
add_test(NAME Wavetables COMMAND WavetableTests
    ${CMAKE_CURRENT_SOURCE_DIR}/Fixtures/wavetables.txt
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/DSP/BandlimitedWavetables")

# X1-7: the twenty goldens through the engine alone.
add_executable(GoldenHarness GoldenHarness.cpp WavFile.hpp)
target_link_libraries(GoldenHarness PRIVATE s1engine)
# Apple Silicon is the arithmetic that wrote the goldens: bit-exact or fail. Elsewhere, tolerances.
set(S1_GOLDEN_FLAGS "")
if(APPLE AND CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
    set(S1_GOLDEN_FLAGS "--require-exact")
endif()
add_test(NAME Goldens COMMAND GoldenHarness
    "${CMAKE_SOURCE_DIR}/Tests/Goldens"
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/Presets/Data"
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/DSP/BandlimitedWavetables"
    ${S1_GOLDEN_FLAGS})

# X2-7 (ADR-078): the same with subnormals flushed to zero, as a protected host renders — still
# bit-exact on Apple Silicon (within tolerance on an Intel Mac): the protection is not heard.
if(APPLE)
    add_test(NAME GoldensFlushToZero COMMAND GoldenHarness
        "${CMAKE_SOURCE_DIR}/Tests/Goldens"
        "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/Presets/Data"
        "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/DSP/BandlimitedWavetables"
        ${S1_GOLDEN_FLAGS} --flush-to-zero)
endif()

# X2-3 (ADR-074): with voices freed every frame — the option the JUCE plugin sets — every golden
# preset renders the same samples at five block sizes, and they are the samples upstream's own
# path renders in one-frame blocks. Exact everywhere.
add_test(NAME GoldensBlockIndependence COMMAND GoldenHarness
    "${CMAKE_SOURCE_DIR}/Tests/Goldens"
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/Presets/Data"
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/DSP/BandlimitedWavetables"
    --check-block-independence)

# The criterion has to reject a wrong render, not only accept the right one. Each self-check
# renders the twenty with one small deliberate fault and succeeds only if the TOLERANCE criterion
# (never --require-exact) rejects at least this many. Measured on arm64 and without FMA: a filter
# 1% sharp 19 of 20, a tuning 1 cent sharp 20 of 20, the second note one block late 7 of 20
# (the arpeggiated and sequenced presets only hold the note, so its timing is not in the sound).
foreach(check "cutoff:18" "detune:19" "late-note:6")
    string(REPLACE ":" ";" parts ${check})
    list(GET parts 0 mutation)
    list(GET parts 1 atLeast)
    add_test(NAME GoldensReject-${mutation} COMMAND GoldenHarness
        "${CMAKE_SOURCE_DIR}/Tests/Goldens"
        "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/Presets/Data"
        "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/DSP/BandlimitedWavetables"
        --mutation ${mutation} --expect-rejected ${atLeast})
endforeach()

# For `--target S1AllTests` (the root CMakeLists.txt).
add_dependencies(S1AllTests SoundpipeBehaviourTests HeldNotesTests KernelEventTests HostMIDITests TuningTableTests PresetTests WavetableTests GoldenHarness)
