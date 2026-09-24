// X3-3 (ADR-085): the editor painted into a PNG with no window — the picture held beside the Mac
// app's render (Scripts/check-layout-spec.sh). `--program` loads a factory preset by its host
// program name ("BankA: 0: Analog Brass"), so both pictures can show the same sound.
// X3-4 (ADR-086): `--presets` drops the preset browser's card down first. It reads and writes
// banks, so it is given a folder of its own under the system's temporary folder — the plugin's
// real one is the OWNER'S.
//
//   EditorSnapshot <studio|cabinet|darkArcade> <out.png> [--program "<Bank: Name>"] [--scale 2] [--presets] [--tunings] [--linked-face] [--lean <points>]
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include "S1PluginProcessor.h"
#include "UI/S1KitControls.h"
#include "UI/S1PluginEditor.h"

int main(int argc, char **argv) {
    if (argc < 3) { std::fprintf(stderr, "usage: EditorSnapshot <skin> <out.png> [--program <name>] [--scale N]\n"); return 2; }
    const juce::ScopedJuceInitialiser_GUI gui;
    std::string program;
    float scale = 2;
    bool withPresets = false, withTunings = false, withKeyboard = false;
    double padFor = -1;    // seconds the first XY pad is held and swept, for its starfield
    double powerAt = -1;   // X3-9: seconds into the cycle that cuts the power
    float lean = 0;
    int windowWidth = 0, windowHeight = 0;
    for (int i = 3; i < argc; ++i) {
        if (std::string(argv[i]) == "--presets") { withPresets = true; continue; }
        if (std::string(argv[i]) == "--tunings") { withTunings = true; continue; }
        // X3-8: the keyboard drawer up over the lower sections.
        if (std::string(argv[i]) == "--keyboard") { withKeyboard = true; continue; }
        if (std::string(argv[i]) == "--power" && i + 1 < argc) { powerAt = std::atof(argv[++i]); continue; }
        if (std::string(argv[i]) == "--pad" && i + 1 < argc) { padFor = std::atof(argv[++i]); continue; }
        // X3-6: the cabinet's stick leaned over, to see that it is drawn whole.
        if (std::string(argv[i]) == "--lean" && i + 1 < argc) { lean = float(std::atof(argv[++i])); continue; }
        // What Windows and Linux see: the linked face, even here where Avenir exists (ADR-088).
        if (std::string(argv[i]) == "--linked-face") { s1ui::Style::preferLinkedTypeface(true); continue; }
        if (i + 1 >= argc) { continue; }
        if (std::string(argv[i]) == "--program") { program = argv[++i]; }
        if (std::string(argv[i]) == "--scale") { scale = float(std::atof(argv[++i])); }
        // X3-7: the window at a size of its own — "1224x765" is the 1280 x 800 laptop.
        if (std::string(argv[i]) == "--window") { std::sscanf(argv[++i], "%dx%d", &windowWidth, &windowHeight); }
    }
    S1PluginProcessor processor;
    const std::filesystem::path scratch = std::filesystem::temp_directory_path()
        / ("ArcadeRuinsSnapshot-" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    processor.presetLibrary().setUserDirectory((scratch / "Banks").u8string());
    if (!program.empty()) {
        s1plugin::PresetLibrary &library = processor.presetLibrary();
        bool found = false;
        for (int i = 0; i < library.factoryProgramCount() && !found; ++i) {
            if (library.factoryProgramName(i).find(program) == std::string::npos) { continue; }
            processor.loadPreset(*library.factoryProgram(i), false);
            found = true;
        }
        if (!found) { std::fprintf(stderr, "no factory program named like \"%s\"\n", program.c_str()); return 1; }
    }
    S1PluginEditor editor(processor, argv[1]);
    if (windowWidth > 0 && windowHeight > 0) { editor.setSize(windowWidth, windowHeight); }
    if (powerAt >= 0) {
        editor.runPower(false);
        const double until = juce::Time::getMillisecondCounterHiRes() + powerAt * 1000.0;
        while (juce::Time::getMillisecondCounterHiRes() < until) { juce::Thread::sleep(10); editor.refreshLiveState(); }
        editor.refreshLiveState();
    }
    if (withKeyboard) { editor.showKeyboard(true); }
    if (withPresets) { editor.showPresets(true); }
    if (withTunings) { editor.showTunings(true); }
    if (padFor > 0) {
        // Hold the first pad and sweep the touch across it, as a hand would: the stars stream behind.
        std::vector<juce::Component *> queue { &editor };
        s1ui::XYPad *pad = nullptr;
        for (size_t at = 0; at < queue.size() && pad == nullptr; ++at) {
            pad = dynamic_cast<s1ui::XYPad *>(queue[at]);
            for (juce::Component *child : queue[at]->getChildren()) { queue.push_back(child); }
        }
        if (pad != nullptr) {
            pad->grab();
            const double started = juce::Time::getMillisecondCounterHiRes();
            for (;;) {
                const double t = (juce::Time::getMillisecondCounterHiRes() - started) / (padFor * 1000.0);
                if (t >= 1.0) { break; }
                pad->moveTo({ float(pad->getWidth()) * float(0.2 + 0.55 * t), float(pad->getHeight()) * float(0.7 - 0.4 * t) });
                juce::Thread::sleep(15);
            }
        }
    }
    if (lean != 0) { editor.joystickGrab(); editor.joystickMoveBy(lean, 0.0f); }
    editor.refreshLiveState();
    const auto started = std::chrono::steady_clock::now();
    const juce::Image image = editor.createComponentSnapshot(editor.getLocalBounds(), false, scale);
    const double milliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();

    const juce::File out = juce::File::getCurrentWorkingDirectory().getChildFile(argv[2]);
    out.deleteFile();
    juce::FileOutputStream stream(out);
    if (!stream.openedOk() || !juce::PNGImageFormat().writeImageToStream(image, stream)) { std::fprintf(stderr, "cannot write %s\n", argv[2]); return 1; }
    std::printf("%s: \"%s\", %d parameter controls%s, a window of %d x %d at %.3gx, painted whole in %.0f ms at %gx -> %s (%d x %d)\n", editor.skin().key.c_str(),
                editor.presetTitle().toRawUTF8(), int(editor.parameterControls().size()),
                withPresets ? ", the preset browser open" : (withTunings ? ", the Tunings card open" : (withKeyboard ? ", the keyboard drawer up" : "")),
                editor.getWidth(), editor.getHeight(), double(editor.interfaceScale()), milliseconds, double(scale), argv[2], image.getWidth(), image.getHeight());
    std::error_code removing;
    std::filesystem::remove_all(scratch, removing);
    return 0;
}
