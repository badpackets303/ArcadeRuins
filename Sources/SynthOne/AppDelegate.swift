//
//  AppDelegate.swift
//  AudioKitSynthOne
//
//  Created by AudioKit Contributors on 7/8/17.
//  Copyright © 2017 AudioKit. All rights reserved.
//
//  P3-1 port. The UI lives in SynthOneCore, so this talks to it through
//  `SynthOneApp` rather than reaching for `Conductor` and `TuningsPanelController`
//  directly — see `SynthOneApp.swift` for why those stay internal.
//
//  Dropped: `initializePlatformServices()` (OneSignal and AppCenter — P3-2), and
//  the Inter-App Audio background/foreground checks, which were already no-ops
//  under Catalyst upstream.

import UIKit
import SynthOneCore

@main
class AppDelegate: UIResponder, UIApplicationDelegate, S1LaunchURLProviding {

    var launchOptions: [UIApplication.LaunchOptionsKey: Any]?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        self.launchOptions = launchOptions


        // PORT: `UIApplication.shared.isIdleTimerDisabled = false`. The property
        // exists under Catalyst but does nothing — display sleep is the system's
        // business on macOS. See `Conductor.neverSleep`.

        // Global appearance
        let attributes = [NSAttributedString.Key.font: UIFont(name: "Avenir Next", size: 14.0)!,
                          NSAttributedString.Key.foregroundColor: UIColor.blue]
        UIBarButtonItem.appearance().setTitleTextAttributes(attributes, for: .normal)

        // Start Audio Engine
        SynthOneApp.start()

        // PORT: upstream creates the window here from `Bundle.main`'s
        // Main.storyboard. Ours is a scene-based Mac app — `SceneDelegate` builds
        // the window so it can also set the size restrictions and title bar (P3-6).

        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        SynthOneApp.stop()
    }

    /// TuneUp. Scene-based apps get URLs through `SceneDelegate` too; this is the
    /// pre-scene path and the one `applicationLaunchedWithURL()` backs up.
    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {

        // On launch the tunings panel does not exist yet, and the Tunings model
        // picks the URL up from `applicationLaunchedWithURL()` instead.
        guard SynthOneApp.open(url: url) else { return true }

        // if url is a file in Inbox remove it (i.e., Scala file)
        if url.isFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        return true
    }

    // MARK: - Menu bar (P3-6)

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        MenuBuilder.build(with: builder)
    }

    /// Stop every sounding note and reset the DSP. Reachable from the menu and ⌘.
    @objc func panic(_ sender: Any?) {
        SynthOneApp.panic()
    }

    /// The musical-typing items are documentation: the keys work whether or not
    /// anyone opens the menu.
    @objc func showMusicalTypingHelp(_ sender: Any?) {}

    // MARK: - Scenes

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }

    // MARK: - S1LaunchURLProviding

    func applicationLaunchedWithURL() -> URL? {
        let launchUrl = self.launchOptions?[.url] as? URL
        self.launchOptions = nil
        return launchUrl
    }
}
