# X3-6 (ADR-088): MSVC cannot compile an init-capture inside a lambda that is itself inside a
# lambda, when the initialiser uses the outer lambda's `this`:
#
#     [this] { callAsync([safe = juce::Component::SafePointer<T>(this)] { ... }); }   // no
#     const juce::Component::SafePointer<T> safe(this);                              // yes
#     [safe] { callAsync([safe] { ... }); }
#
# Clang and GCC accept both, so this side cannot catch it: it cost the owner a build on 2026-09-20,
# they fixed it by hand, and it was reintroduced in the SAME session, hours after being written
# into CLAUDE.md's gotchas. Judgement about which ones are nested is what failed, so the form is
# banned outright and checked here — a SafePointer is always a named local, captured by copy.
#
#   cmake -DS1_UI_DIR=<Sources/S1Plugin/UI> -P NoNestedInitCapture.cmake

if(NOT DEFINED S1_UI_DIR)
    message(FATAL_ERROR "S1_UI_DIR is not set")
endif()

file(GLOB_RECURSE sources "${S1_UI_DIR}/*.cpp" "${S1_UI_DIR}/*.h")
set(found "")
foreach(source IN LISTS sources)
    file(STRINGS "${source}" lines)
    set(number 0)
    foreach(line IN LISTS lines)
        math(EXPR number "${number} + 1")
        if(line MATCHES "\\[[ \t]*[A-Za-z_][A-Za-z0-9_]*[ \t]*=[ \t]*juce::Component::SafePointer")
            get_filename_component(name "${source}" NAME)
            list(APPEND found "${name}:${number}")
        endif()
    endforeach()
endforeach()

list(LENGTH found count)
if(count GREATER 0)
    string(REPLACE ";" "\n      " printable "${found}")
    message(FATAL_ERROR
        "A juce::Component::SafePointer is made inside a lambda's capture list, which MSVC refuses\n"
        "when that lambda sits inside another one. Make it a named local and capture it by copy.\n"
        "      ${printable}")
endif()
message(STATUS "ok    no SafePointer is made in a capture list (${count} found); MSVC can compile these lambdas")
