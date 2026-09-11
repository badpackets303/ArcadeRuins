//  P0-4 spike: the AU's view controller (extension principal class).
//  Deliberately loads its UI from a *storyboard* — that is the actual risk being
//  tested, since Synth One's UI is 12 storyboards.

import CoreAudioKit
import UIKit
import os.log

public final class SpikeAudioUnitViewController: AUViewController, AUAudioUnitFactory {

    private var audioUnit: SpikeAudioUnit?
    private var parameterObserverToken: AUParameterObserverToken?
    private var panel: SpikePanelViewController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        preferredContentSize = CGSize(width: 600, height: 180)
        embedStoryboardPanel()
        connectPanelIfReady()
    }

    // MARK: - AUAudioUnitFactory

    public func createAudioUnit(with componentDescription: AudioComponentDescription) throws -> AUAudioUnit {
        let unit = try SpikeAudioUnit(componentDescription: componentDescription, options: [])
        audioUnit = unit
        DispatchQueue.main.async { [weak self] in
            self?.connectPanelIfReady()
        }
        return unit
    }

    /// ADR-005 open question: can a sandboxed AU extension, ad-hoc signed with no
    /// Team ID, actually use an App Group container? P3-3 depends on the answer.
    static func appGroupIsWritable() -> Bool {
        let group = "group.com.badpackets303.SpikeAU"
        guard let url = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: group) else { return false }
        let probe = url.appendingPathComponent("p0-4-probe.txt")
        do {
            try "written by the AU extension".write(to: probe, atomically: true, encoding: .utf8)
            return (try? String(contentsOf: probe, encoding: .utf8)) != nil
        } catch {
            return false
        }
    }

    // MARK: - UI

    private func embedStoryboardPanel() {
        let bundle = Bundle(for: type(of: self))
        let storyboard = UIStoryboard(name: "MainInterface", bundle: bundle)
        guard let panel = storyboard.instantiateInitialViewController() as? SpikePanelViewController else {
            os_log("P0-4 STORYBOARD-FAIL", log: OSLog(subsystem: "com.badpackets303.SpikeAU", category: "spike"), type: .default)
            return
        }
        addChild(panel)
        panel.view.frame = view.bounds
        panel.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(panel.view)
        panel.didMove(toParent: self)
        self.panel = panel
        os_log("P0-4 STORYBOARD-OK subviews=%{public}d size=%{public}@ idiom=%{public}d",
               log: OSLog(subsystem: "com.badpackets303.SpikeAU", category: "spike"), type: .default,
               panel.view.subviews.count,
               NSCoder.string(for: panel.view.bounds.size),
               UIDevice.current.userInterfaceIdiom.rawValue)
    }

    private func connectPanelIfReady() {
        guard let audioUnit = audioUnit,
              let panel = panel,
              let tree = audioUnit.parameterTree,
              let gain = tree.parameter(withAddress: SpikeAudioUnit.ParameterAddress.gain.rawValue)
        else { return }

        panel.set(gain: gain.value)
        panel.onGainChanged = { value in gain.setValue(value, originator: self.parameterObserverToken) }

        if let ag = tree.parameter(withAddress: SpikeAudioUnit.ParameterAddress.appGroupWritable.rawValue) {
            ag.value = Self.appGroupIsWritable() ? 1.0 : 0.0
        }

        if let flag = tree.parameter(withAddress: SpikeAudioUnit.ParameterAddress.storyboardLoaded.rawValue) {
            flag.value = (panel.view.subviews.count >= 3) ? 1.0 : 0.0
        }

        parameterObserverToken = tree.token(byAddingParameterObserver: { [weak self] address, value in
            guard address == SpikeAudioUnit.ParameterAddress.gain.rawValue else { return }
            DispatchQueue.main.async { self?.panel?.set(gain: value) }
        })
    }
}
