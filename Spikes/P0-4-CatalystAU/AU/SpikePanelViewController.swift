//  P0-4 spike: storyboard-backed panel. Stands in for a Synth One panel controller.

import UIKit

public final class SpikePanelViewController: UIViewController {

    @IBOutlet private weak var gainSlider: UISlider!
    @IBOutlet private weak var valueLabel: UILabel!

    var onGainChanged: ((Float) -> Void)?

    public override func viewDidLoad() {
        super.viewDidLoad()
        updateLabel(gainSlider?.value ?? 0)
    }

    func set(gain: Float) {
        gainSlider?.value = gain
        updateLabel(gain)
    }

    @IBAction private func gainChanged(_ sender: UISlider) {
        updateLabel(sender.value)
        onGainChanged?(sender.value)
    }

    private func updateLabel(_ value: Float) {
        valueLabel?.text = String(format: "Gain %.2f", value)
    }
}
