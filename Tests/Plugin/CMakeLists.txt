# Tests of the JUCE plugin (X2). Only with -DS1_BUILD_PLUGIN=ON.
#
# Each links the plugin's shared-code library — the very objects the VST3 and the standalone are
# made of — and drives S1PluginProcessor with no host and no window.
function(s1_plugin_test name)
    juce_add_console_app(${name} PRODUCT_NAME "${name}")
    target_sources(${name} PRIVATE ${name}.cpp)
    add_dependencies(S1AllTests ${name})
    target_link_libraries(${name} PRIVATE ArcadeRuins s1engine)
    # The shared-code target keeps JUCE's modules and the JucePlugin_* definitions to itself; a
    # test that includes its headers has to be compiled the same way.
    target_compile_definitions(${name} PRIVATE $<TARGET_PROPERTY:ArcadeRuins,COMPILE_DEFINITIONS>)
    target_include_directories(${name} SYSTEM PRIVATE $<TARGET_PROPERTY:s1engine,INTERFACE_INCLUDE_DIRECTORIES>)
    target_include_directories(${name} PRIVATE
        $<TARGET_PROPERTY:ArcadeRuins,INCLUDE_DIRECTORIES>
        ${CMAKE_SOURCE_DIR}/Sources/S1Plugin)
    # These tests compare floats exactly, on purpose: "the same number" is what they assert.
    if(NOT MSVC)
        target_compile_options(${name} PRIVATE -Wno-float-equal)
    endif()
endfunction()

# X2-1: processBlock against the bare engine, sample for sample.
s1_plugin_test(PluginRenderTests)
add_test(NAME PluginRender COMMAND PluginRenderTests
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/DSP/BandlimitedWavetables")

# X2-2: the 150 parameters — frozen identity, the kernel's ranges, every value reaching the
# kernel, the engine's own changes reported back, readouts.
#   To add a released parameter's line:  PluginParameterTests <fixture> --write-fixture
s1_plugin_test(PluginParameterTests)
add_test(NAME PluginParameters COMMAND PluginParameterTests
    "${CMAKE_CURRENT_SOURCE_DIR}/Fixtures/parameter-ids.txt")

# X2-4: MIDI as a host sends it — one key once, the pedal, mono, pitch bend heard and reported,
# the mod wheel. (The router's rules against the standalone's: Tests/Engine/HostMIDITests.)
s1_plugin_test(PluginMIDITests)
add_test(NAME PluginMIDI COMMAND PluginMIDITests)

# X2-5: state — save in one instance and reopen in another, a state loaded while audio runs,
# what is not a state, other versions' states, factory presets as states, and the committed
# version-1 state written on macOS.   To write it:  PluginStateTests <fixture> <banks> --write-fixture
s1_plugin_test(PluginStateTests)
add_test(NAME PluginState COMMAND PluginStateTests
    "${CMAKE_CURRENT_SOURCE_DIR}/Fixtures/state-v1.json"
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/Presets/Data")

# X2-6: the host's tempo and transport through a play head — step times measured from the
# rendered audio, the tempo parameter reported and not obeyed, a restored session's tempo, the
# stop edge heard.
s1_plugin_test(PluginTransportTests)
add_test(NAME PluginTransport COMMAND PluginTransportTests)

# X2-7: denormal protection — the render call runs with flush-to-zero on and hands the caller's
# mode back; nothing subnormal leaves the plugin; 40 s of tail cost no more per block
# than the sounding part. Prints the unprotected engine's timings beside the plugin's.
s1_plugin_test(PluginDenormalTests)
add_test(NAME PluginDenormals COMMAND PluginDenormalTests)

# X2-9: the preset library — the linked-in factory banks against the repository's files, the
# host's 695 programs against the Mac AUv3's own list (a Swift-written fixture:
# Scripts/write-factory-program-fixtures.sh), presets loaded by a host and by a person, user banks
# on disk in a temporary folder.
s1_plugin_test(PluginPresetTests)
add_test(NAME PluginPresets COMMAND PluginPresetTests
    "${CMAKE_CURRENT_SOURCE_DIR}/Fixtures/factory-programs.txt"
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/Presets/Data")

# X2-10: the plugin as the standalone runs it — through juce::AudioProcessorPlayer — across an
# audio device stopping and coming back at another rate and buffer size, with a key held.
s1_plugin_test(PluginStandaloneTests)
target_link_libraries(PluginStandaloneTests PRIVATE juce::juce_audio_utils)
add_test(NAME PluginStandalone COMMAND PluginStandaloneTests)

# X3-1 (ADR-083): the layout specification — the Swift-written file (Scripts/write-layout-spec.sh)
# as the binary carries it and as S1LayoutSpec reads it: every control on a real parameter and
# inside its section, the plan's rows and knob sizes, Cabinet's sections on the painting's
# rectangles, the 26 parameters with no control, and what is not a specification refused.
s1_plugin_test(PluginLayoutSpecTests)
add_test(NAME PluginLayoutSpec COMMAND PluginLayoutSpecTests
    "${CMAKE_SOURCE_DIR}/Sources/S1Plugin/Layout/layout-spec.json")

# A wireframe drawn from the specification by the same reader, alone or over a render of the Mac
# app (Scripts/check-layout-spec.sh). Run here for both skins so it is known to draw on every OS.
s1_plugin_test(LayoutWireframe)
add_test(NAME LayoutWireframeStudio COMMAND LayoutWireframe
    "${CMAKE_SOURCE_DIR}/Sources/S1Plugin/Layout/layout-spec.json" studio "${CMAKE_CURRENT_BINARY_DIR}/wireframe-studio.png")
add_test(NAME LayoutWireframeCabinet COMMAND LayoutWireframe
    "${CMAKE_SOURCE_DIR}/Sources/S1Plugin/Layout/layout-spec.json" cabinet "${CMAKE_CURRENT_BINARY_DIR}/wireframe-cabinet.png")

# X3-2 (ADR-084): the controls kit with no window — every control of the specification built for
# both skins and painted at 1x and 2x, each kind driven through the methods its mouse handlers
# call, the gestures a host would record counted, keys, wheel, reset, accessibility, crisp edges.
s1_plugin_test(PluginControlsKitTests)
add_test(NAME PluginControlsKit COMMAND PluginControlsKitTests)

# A picture of the whole kit on the specification's frames, to hold beside the Mac render. Run
# here for both skins so it is known to paint on every OS.
s1_plugin_test(ControlsKitSheet)
add_test(NAME ControlsKitSheetStudio COMMAND ControlsKitSheet studio "${CMAKE_CURRENT_BINARY_DIR}/kit-studio.png")
add_test(NAME ControlsKitSheetCabinet COMMAND ControlsKitSheet cabinet "${CMAKE_CURRENT_BINARY_DIR}/kit-cabinet.png")

# X3-3 (ADR-085): the editor with no window (PluginEditorTests), and a picture of it for each skin
# (EditorSnapshot) — run here so the whole interface is known to build and paint on every OS.
s1_plugin_test(PluginEditorTests)
add_test(NAME PluginEditor COMMAND PluginEditorTests)
s1_plugin_test(EditorSnapshot)
add_test(NAME EditorSnapshotStudio COMMAND EditorSnapshot studio "${CMAKE_CURRENT_BINARY_DIR}/editor-studio.png")
add_test(NAME EditorSnapshotCabinet COMMAND EditorSnapshot cabinet "${CMAKE_CURRENT_BINARY_DIR}/editor-cabinet.png")

# X3-4 (ADR-086): the preset browser's model with no window — the folder it seeds from the banks
# the Mac starts with, the category rows and their upstream numbers, what each row shows, the
# search, and every operation: New, New Bank, duplicate, star, save, delete, reorder, rename and
# delete a bank, import (a bank the Mac app exported, unchanged) and export.
s1_plugin_test(PluginPresetBrowserTests)
add_test(NAME PluginPresetBrowser COMMAND PluginPresetBrowserTests
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/Presets/Data")

# …and a picture of the card itself, for each skin: the browser is known to paint on every OS.
# It reads and writes banks, in a folder of its own under the system's temporary folder.
add_test(NAME EditorSnapshotPresetsStudio COMMAND EditorSnapshot studio "${CMAKE_CURRENT_BINARY_DIR}/presets-studio.png" --presets)
add_test(NAME EditorSnapshotPresetsCabinet COMMAND EditorSnapshot cabinet "${CMAKE_CURRENT_BINARY_DIR}/presets-cabinet.png" --presets)

# X3-5 (ADR-087): the tunings — the three banks and the sort that puts 12 ET at row 0, the 128
# frequencies, A4 moving the whole table, the user bank and Scala import, and the acceptance: the
# eleven factory presets whose tuning is not twelve notes play in it, measured from the audio.
s1_plugin_test(PluginTuningsTests)
add_test(NAME PluginTunings COMMAND PluginTuningsTests
    "${CMAKE_SOURCE_DIR}/Sources/SynthOneCore/Presets/Data")

# …and a picture of the Tunings card for each skin, so it is known to paint on every OS.
add_test(NAME EditorSnapshotTuningsStudio COMMAND EditorSnapshot studio "${CMAKE_CURRENT_BINARY_DIR}/tunings-studio.png" --tunings)
add_test(NAME EditorSnapshotTuningsCabinet COMMAND EditorSnapshot cabinet "${CMAKE_CURRENT_BINARY_DIR}/tunings-cabinet.png" --tunings)

# X3-6 (ADR-088): the typeface the plugin carries for Windows and Linux — Barlow Condensed, linked
# in. Every label the specification measured on the Mac must still fit its frame in it; the test
# forces the linked face so it cannot pass by measuring the Mac's own Avenir.
s1_plugin_test(PluginTypefaceTests)
add_test(NAME PluginTypeface COMMAND PluginTypefaceTests)

# X3-7 (ADR-089): the window at a size of its own. `PluginEditor` measures where everything lands
# at every scale; this paints one, so a scaled window is known to DRAW on every OS — 1224 x 765 is
# the plan's 1280 x 800 laptop, at 0.85x.
add_test(NAME EditorSnapshotLaptop COMMAND EditorSnapshot cabinet "${CMAKE_CURRENT_BINARY_DIR}/editor-laptop.png" --window 1224x765)

# X3-8 (ADR-090): the interface's own keyboard — the drawer's geometry (a port of upstream's
# `KeyboardView`, with no JUCE in it) and, the acceptance, a key played in the interface rendered
# SAMPLE FOR SAMPLE against the same note sent as the host's own MIDI.
s1_plugin_test(PluginKeyboardTests)
add_test(NAME PluginKeyboard COMMAND PluginKeyboardTests)

# …and a picture of the drawer for each skin, so the keys are known to draw on every OS.
add_test(NAME EditorSnapshotKeyboardStudio COMMAND EditorSnapshot studio "${CMAKE_CURRENT_BINARY_DIR}/keyboard-studio.png" --keyboard)
add_test(NAME EditorSnapshotKeyboardCabinet COMMAND EditorSnapshot cabinet "${CMAKE_CURRENT_BINARY_DIR}/keyboard-cabinet.png" --keyboard)

# X3-6 (ADR-088): the lambda form MSVC refuses, banned by grep — nothing here can catch it,
# because Clang and GCC accept it. It runs on every OS, and costs nothing.
add_test(NAME NoNestedInitCapture COMMAND ${CMAKE_COMMAND}
    -DS1_UI_DIR=${CMAKE_SOURCE_DIR}/Sources/S1Plugin/UI
    -P ${CMAKE_CURRENT_SOURCE_DIR}/NoNestedInitCapture.cmake)
