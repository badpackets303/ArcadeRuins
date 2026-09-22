//
//  S1StandaloneApp.cpp
//  Arcade Ruins
//
//  X2-10 (ADR-081): the standalone's application object. JUCE's own (StandaloneFilterApp, which
//  is `final`, so this is its text with two differences) is used when
//  JUCE_USE_CUSTOM_PLUGIN_STANDALONE_APP is 0; this one is compiled into the Standalone target
//  only, and differs in:
//
//    1. EVERY MIDI INPUT IS OPEN, and one plugged in later opens by itself. JUCE opens none on a
//       desktop: a keyboard makes no sound until its box is ticked in Options > Audio/MIDI
//       Settings. An instrument should play when it is played — the Mac app listens to every
//       source too. (The holder's half-second timer does it: `autoOpenMidiDevices`.)
//    2. THE SETTINGS FILE is beside the preset banks — <application data>/BadPackets/Arcade Ruins/
//       — not loose in the application-data folder. It holds the audio device, and the sound as
//       it was at the last quit (the plugin's own state, ADR-076).
//
//  Everything else is the holder's: it restarts the processor when the audio device changes
//  (prepareToPlay at the new rate — ADR-043's failure, which JUCE does not have), and the
//  window shows whatever createEditor gives it.
//
// What juce_audio_plugin_client_Standalone.cpp includes before the window's header, in its order.
#include <juce_core/system/juce_TargetPlatform.h>
#include <juce_audio_plugin_client/detail/juce_CheckSettingMacros.h>
#include <juce_audio_plugin_client/detail/juce_IncludeSystemHeaders.h>
#include <juce_audio_plugin_client/detail/juce_IncludeModuleHeaders.h>
#include <juce_audio_plugin_client/detail/juce_PluginUtilities.h>
#include <juce_audio_devices/juce_audio_devices.h>
#include <juce_gui_extra/juce_gui_extra.h>
#include <juce_audio_utils/juce_audio_utils.h>
#include <juce_audio_plugin_client/Standalone/juce_StandaloneFilterWindow.h>

namespace {

class S1StandaloneApp final : public juce::JUCEApplication {
public:
    S1StandaloneApp() {
        juce::PropertiesFile::Options options;
        options.applicationName = juce::CharPointer_UTF8(JucePlugin_Name);
        options.filenameSuffix = ".settings";
        options.osxLibrarySubFolder = "Application Support";
       #if JUCE_LINUX || JUCE_BSD
        options.folderName = "~/.config/BadPackets/Arcade Ruins";
       #else
        options.folderName = "BadPackets/Arcade Ruins";
       #endif
        appProperties.setStorageParameters(options);
    }

    const juce::String getApplicationName() override { return juce::CharPointer_UTF8(JucePlugin_Name); }
    const juce::String getApplicationVersion() override { return JucePlugin_VersionString; }
    bool moreThanOneInstanceAllowed() override { return true; }
    void anotherInstanceStarted(const juce::String &) override {}

    void initialise(const juce::String &) override {
        if (juce::Desktop::getInstance().getDisplays().displays.isEmpty()) {
            pluginHolder = createPluginHolder();          // no display: sound without a window
            return;
        }
        mainWindow = std::make_unique<juce::StandaloneFilterWindow>(
            getApplicationName(),
            juce::LookAndFeel::getDefaultLookAndFeel().findColour(juce::ResizableWindow::backgroundColourId),
            createPluginHolder());
        mainWindow->setVisible(true);
    }

    void shutdown() override {
        pluginHolder = nullptr;
        mainWindow = nullptr;
        appProperties.saveIfNeeded();
    }

    void systemRequestedQuit() override {
        if (pluginHolder != nullptr) { pluginHolder->savePluginState(); }
        if (mainWindow != nullptr) { mainWindow->pluginHolder->savePluginState(); }
        if (juce::ModalComponentManager::getInstance()->cancelAllModalComponents()) {
            juce::Timer::callAfterDelay(100, [] {
                if (auto *app = juce::JUCEApplicationBase::getInstance()) { app->systemRequestedQuit(); }
            });
        } else {
            quit();
        }
    }

private:
    std::unique_ptr<juce::StandalonePluginHolder> createPluginHolder() {
        constexpr bool autoOpenMidiDevices = true;
        return std::make_unique<juce::StandalonePluginHolder>(appProperties.getUserSettings(), false, juce::String {}, nullptr,
                                                              juce::Array<juce::StandalonePluginHolder::PluginInOuts> {}, autoOpenMidiDevices);
    }

    juce::ApplicationProperties appProperties;
    std::unique_ptr<juce::StandaloneFilterWindow> mainWindow;
    std::unique_ptr<juce::StandalonePluginHolder> pluginHolder;
};

} // namespace

juce::JUCEApplicationBase *juce_CreateApplication();
juce::JUCEApplicationBase *juce_CreateApplication() { return new S1StandaloneApp(); }
