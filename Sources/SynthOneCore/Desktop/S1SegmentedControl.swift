//  A segmented picker in the desktop dress (P6-2, ADR-045).
//
//  **New, not ported.** The classic filter-type control is a button that cycles Low →
//  Band → High. On a desktop a three-way choice is a segmented control. This one is
//  drawn to match the sections rather than as the Mac's native control, which would sit
//  in the header as the only piece of system chrome. It drives, and follows, the
//  classic `FilterTypeButton`, which keeps the binding.

import UIKit

final class S1SegmentedControl: UIView {

    private let buttons: [UIButton]
    private let stack = UIStackView()

    var onSelect: ((Int) -> Void)?

    var selectedIndex: Int = 0 {
        didSet { updateSelection() }
    }

    init(titles: [String]) {
        buttons = titles.map { title in
            let button = UIButton(type: .custom)
            button.useDesignedButtonAppearance()
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = S1DesktopTheme.font(11, weight: .medium)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
            button.layer.cornerRadius = 4
            return button
        }
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = S1DesktopTheme.fieldBackground
        layer.cornerRadius = 5
        layer.borderWidth = 1
        layer.borderColor = S1Skins.current.palette.wellBorder.cgColor

        stack.axis = .horizontal
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
        ])
        for (index, button) in buttons.enumerated() {
            button.tag = index
            button.addTarget(self, action: #selector(pressed(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func pressed(_ sender: UIButton) {
        guard sender.tag != selectedIndex else { return }
        selectedIndex = sender.tag
        onSelect?(sender.tag)
    }

    fileprivate func updateSelection() {
        // P7-4: the selected face and the frame follow the section's accent under a skin that
        // names one; the accent is known once the picker is in its section's header.
        let face = S1DesktopStyle.segmentFace(accent: s1Accent)
        layer.borderColor = face.border.cgColor
        for (index, button) in buttons.enumerated() {
            let on = index == selectedIndex
            button.backgroundColor = on ? face.face : .clear
            button.setTitleColor(on ? S1DesktopTheme.text : S1DesktopTheme.label, for: .normal)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { updateSelection() }
    }
}

extension S1SegmentedControl: S1PowerAware {
    /// P7-12 (ADR-062): the selection may have moved while the zone was dark.
    func powerDidReturn() { updateSelection() }
}
