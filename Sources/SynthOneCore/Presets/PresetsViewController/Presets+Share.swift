//  Share for presets and banks: a share sheet in the standalone, a Save dialog in the plugin (ADR-044).
//
//  **New, not ported.** Upstream presents a `UIActivityViewController` from both Share buttons. On the
//  Mac, UIKit's bridge places that sheet relative to the window the presenting view is in. A plugin's
//  view lives in the host's window, not one of its own, so `_sceneViewRectFromUIWindowRect` fails an
//  assertion and the exception kills the plugin: three crash reports, 2026-09-10 and 2026-09-11, all in
//  `UINSShareSheetController`. It is thrown during UIKit's commit pass, after `present` has returned,
//  so it cannot be caught at the call. The plugin exports the same file through a Save dialog instead.

import UIKit

extension PresetsViewController {

    /// The controller that hands the file at `url` to the user.
    static func makeShareController(for url: URL, hosted: Bool) -> UIViewController {
        if hosted {
            return UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        }
        let activityViewController = UIActivityViewController(activityItems: [url],
                                                              applicationActivities: nil)
        activityViewController.excludedActivityTypes = [
            UIActivity.ActivityType.copyToPasteboard
        ]
        return activityViewController
    }

    /// Upstream's presentation, centred on the panel with no arrow, for whichever controller applies.
    func share(_ url: URL) {
        let controller = PresetsViewController.makeShareController(for: url, hosted: conductor.isHosted)

        if let popoverPresentationController = controller.popoverPresentationController {
            popoverPresentationController.sourceView = self.view
            popoverPresentationController.sourceRect = CGRect(x: self.view.bounds.midX,
                                                              y: self.view.bounds.midY,
                                                              width: 0, height: 0)
            popoverPresentationController.permittedArrowDirections = []
        }

        self.present(controller, animated: true, completion: nil)
    }
}
