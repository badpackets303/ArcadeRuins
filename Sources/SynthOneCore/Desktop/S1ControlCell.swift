//  A control with its name and its value, as the desktop layout shows every knob
//  (P6, ADR-045).
//
//  **New, not ported.** The classic panels name a knob with a storyboard label and show
//  its value only in the header's display strip, one parameter at a time. On a desktop
//  the expectation is a readout under every knob. The readout is driven by the same
//  value the binding sets — `Knob.valueDidChange` fires for a drag, a MIDI change, a
//  preset load and host automation alike — so it can never disagree with the sound.

import UIKit

/// How a parameter's value reads under its knob.
enum S1ValueFormat {

    case decimal
    case integer(unit: String)
    case percent
    case hertz
    case seconds
    case semitones
    case decibels
    case custom((Double) -> String)

    func string(for value: Double) -> String {
        switch self {
        case .decimal:
            return String(format: "%.2f", value)
        case .integer(let unit):
            return unit.isEmpty ? String(format: "%.0f", value) : String(format: "%.0f %@", value, unit)
        case .percent:
            return String(format: "%.0f%%", value * 100)
        case .hertz:
            if value >= 1_000 { return String(format: "%.2f kHz", value / 1_000) }
            if value >= 100 { return String(format: "%.0f Hz", value) }
            return String(format: "%.1f Hz", value)
        case .seconds:
            if value >= 1 { return String(format: "%.2f s", value) }
            return String(format: "%.0f ms", value * 1_000)
        case .semitones:
            let v = Int(value.rounded())
            return v == 0 ? "0 st" : String(format: "%+d st", v)
        case .decibels:
            return String(format: "%.1f dB", value)
        case .custom(let f):
            return f(value)
        }
    }
}

final class S1ControlCell: UIStackView {

    let control: UIView
    let titleLabel = UILabel()
    let valueLabel = UILabel()
    private let format: S1ValueFormat?

    /// `size` is the control's drawn size. A knob draws to its bounds, so this is the
    /// knob's diameter; the classic storyboards used 60–96 points, the desktop layout
    /// 28–54.
    init(control: UIView, title: String, size: CGSize, format: S1ValueFormat? = nil) {
        self.control = control
        self.format = format
        super.init(frame: .zero)
        axis = .vertical
        alignment = .center
        spacing = 3
        translatesAutoresizingMaskIntoConstraints = false

        control.translatesAutoresizingMaskIntoConstraints = false
        control.removeConstraints(control.constraints.filter { $0.firstItem === control && $0.secondItem == nil })
        NSLayoutConstraint.activate([
            control.widthAnchor.constraint(equalToConstant: size.width),
            control.heightAnchor.constraint(equalToConstant: size.height)
        ])
        addArrangedSubview(control)

        titleLabel.text = title
        titleLabel.font = S1DesktopTheme.font(12)
        titleLabel.textColor = S1DesktopTheme.label
        titleLabel.textAlignment = .center
        addArrangedSubview(titleLabel)

        valueLabel.font = S1DesktopTheme.font(11)
        valueLabel.textColor = S1DesktopTheme.value
        valueLabel.textAlignment = .center
        if format != nil {
            addArrangedSubview(valueLabel)
        }

        if let knob = control as? Knob {
            knob.drawsDesktopStyle = true
            knob.valueDidChange = { [weak self] _ in self?.refresh() }
        }
        if let toggle = control as? ToggleButton {
            toggle.drawsAsSwitch = true
        }
        refresh()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func refresh() {
        guard let format, let knob = control as? Knob else { return }
        valueLabel.text = format.string(for: knob.value)
    }
}

/// A switch with its name beside it, for the toggles that sit in a column or a header.
final class S1SwitchCell: UIStackView {

    init(toggle: ToggleButton, title: String) {
        super.init(frame: .zero)
        axis = .horizontal
        alignment = .center
        spacing = 6
        translatesAutoresizingMaskIntoConstraints = false

        toggle.drawsAsSwitch = true
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.removeConstraints(toggle.constraints.filter { $0.firstItem === toggle && $0.secondItem == nil })
        NSLayoutConstraint.activate([
            toggle.widthAnchor.constraint(equalToConstant: 28),
            toggle.heightAnchor.constraint(equalToConstant: 16)
        ])
        addArrangedSubview(toggle)

        let label = UILabel()
        label.text = title
        label.font = S1DesktopTheme.font(12)
        label.textColor = S1DesktopTheme.label
        addArrangedSubview(label)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// A vertical stack of switch cells.
final class S1SwitchColumn: UIStackView {

    init(_ cells: [S1SwitchCell]) {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .leading
        spacing = 8
        translatesAutoresizingMaskIntoConstraints = false
        cells.forEach { addArrangedSubview($0) }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
