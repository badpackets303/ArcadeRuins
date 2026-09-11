//
//  AudioRecorder.swift
//  AudioKitSynthOne
//
//  Created by Matthias Frick on 08/11/2019.
//  Copyright © 2019 AudioKit. All rights reserved.
//
//  P2-3 port. Same shape, same call sites (`toggleRecord(value:)`, the two
//  delegates, the timer-driven view updates). Three changes, all marked PORT:
//  `AKNodeRecorder` -> `S1NodeRecorder`, `AKAudioFile` -> `URL`, and the
//  `exportAsynchronously` step is gone because the recorder writes WAV directly.

import Foundation
import AVFoundation

public enum RecorderState: Int {
    // Upstream's capitalisation. P2-3 lower-cased these for house style and P3-1
    // put them back: `GeneratorsPanelController` reads them, and an avoidable
    // rename is an avoidable diff (ADR-009).
    case Idle = 0
    case Recording = 1
    case Exporting = 2
}

/// PORT: upstream passes an `AKAudioFile`. The one call site
/// (`Manager.didFinishRecording`) uses nothing but `file.url`, so this hands over
/// the URL and `AKAudioFile` never has to be ported at all.
public protocol AudioRecorderFileDelegate: AnyObject {
    func didFinishRecording(url: URL)
}

public protocol AudioRecorderViewDelegate: AnyObject {
    func updateRecorderView(state: RecorderState, time: Double?)
}

public class AudioRecorder {

    public var node: AVAudioNode? {
        didSet { nodeRecorder.node = node }
    }

    public let nodeRecorder = S1NodeRecorder()
    public weak var fileDelegate: AudioRecorderFileDelegate?
    public weak var viewDelegate: AudioRecorderViewDelegate?

    /// Timer to update the view on recording progress
    public var viewTimer: Timer?

    /// Where recordings are written. Temporary on purpose — a recording's
    /// destination is the share sheet, not the app's own storage. If that changes,
    /// it changes at P3-3 along with everything else about where files live.
    /// Where recordings are written.
    ///
    /// PORT (P4-6): upstream used the temporary directory, which is right on iOS —
    /// you record, the share sheet opens, and the file goes wherever you send it. On
    /// a Mac the expectation is a file you can find in Finder, and the system is free
    /// to reap anything left in `temporaryDirectory`.
    public var directory: URL = AudioRecorder.defaultRecordingsDirectory

    /// `~/Music/Arcade Ruins`, created on demand.
    ///
    /// Falls back to the temporary directory rather than failing: losing a recording
    /// to a reaped temp file is bad, and refusing to record at all is worse.
    public static var defaultRecordingsDirectory: URL {
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        guard let directory = music?.appendingPathComponent("Arcade Ruins") else {
            return FileManager.default.temporaryDirectory
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            AKLog("could not create \(directory.path): \(error) — recording to the temporary directory")
            return FileManager.default.temporaryDirectory
        }
    }

    /// PORT: upstream defaults this to `AudioKit.output`. There is no global
    /// engine any more (ADR-014), so the caller says which node to tap.
    public init(node: AVAudioNode? = nil) {
        self.node = node
        nodeRecorder.node = node
    }

    public func toggleRecord(value: Double) {
        let shouldRecord = value == 1

        if nodeRecorder.isRecording && !shouldRecord {
            let url = nodeRecorder.stop()
            viewTimer?.invalidate()
            AKLog("recorded file at: \(url?.path ?? "nil")")

            // PORT: upstream hands off to `AKAudioFile.exportAsynchronously`, which
            // transcoded to WAV and called back on completion. `S1NodeRecorder`
            // already wrote a WAV, so there is nothing to export and the
            // `.exporting` state is over as soon as it began. The state is still
            // published so the UI's three-way switch is unchanged.
            viewDelegate?.updateRecorderView(state: .Exporting, time: 0)
            if let url = url {
                DispatchQueue.main.async {
                    self.fileDelegate?.didFinishRecording(url: url)
                    self.updateView()
                }
            } else {
                updateView()
            }
        } else {
            do {
                try nodeRecorder.reset()
                try nodeRecorder.record(to: directory
                    .appendingPathComponent(createDateFileName())
                    .appendingPathExtension("wav"))
                viewTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true, block: { [weak self] _ in
                    self?.updateView()
                })
            } catch let error as NSError {
                AKLog(error.description)
            }
        }
    }

    private func updateView() {
        let state: RecorderState = nodeRecorder.isRecording ? .Recording : .Idle
        viewDelegate?.updateRecorderView(state: state, time: nodeRecorder.recordedDuration)
    }

    // Use Date and Time as Filename
    private func createDateFileName() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return dateFormatter.string(from: Date())
    }
}
