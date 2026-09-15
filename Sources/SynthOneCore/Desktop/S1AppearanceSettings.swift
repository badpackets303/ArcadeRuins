//  Choosing the layout and the skin from Settings (P7-5, P7-6; ADR-049, ADR-050).
//
//  **New, not ported.** Both choices are user defaults read once at launch: the layout since P6
//  (`S1ClassicLayout`, ADR-045) and the skin since P7 (`S1Skin`, ADR-046). Until now the only
//  way to set either was the standalone's View menu or a `defaults write` — and **the plugin has
//  no menu bar**, so in a host the terminal was the only way, against a different container from
//  the app's. The owner ruled that out (2026-09-14).
//
//  The Settings popover is the one screen every product and every layout opens from its own
//  toolbar, so both pickers live here. This installs itself from `MIDISettingsViewController`
//  (one line there), rather than from the desktop layout, because the **classic** layout has to
//  carry it too: otherwise choosing Classic in the plugin would be a one-way trip, with no menu
//  to come back by.
//
//  Neither choice changes the running interface, as the View menu's do not: the layout is what
//  `SynthOneApp.makeRootViewController` builds at launch, and the skin is read while the desktop
//  layout moves the storyboard's controls into its sections. The note under the pickers says so,
//  in each product's own words.

import UIKit

final class S1AppearanceSettings: UIView {

    private let layoutPicker: S1SegmentedControl
    private let skinPicker: S1SegmentedControl
    private let skinRow = UIStackView()
    private let skinTitle = UILabel()
    private let note = UILabel()
    private let isHosted: Bool

    /// The layouts offered, in the picker's order.
    static let layouts: [S1Layout] = [.desktop, .classic]

    static func title(for layout: S1Layout) -> String {
        switch layout {
        case .desktop: return NSLocalizedString("Desktop", comment: "Layout name")
        case .classic: return NSLocalizedString("Classic", comment: "Layout name")
        }
    }

    /// What each product tells the owner about when a change lands. The standalone reopens on its
    /// own; a plugin's interface belongs to the host. **One line, always**: the block sits in a
    /// fixed gap under the buffer-size paragraph, and a second line runs into it.
    static func noteText(isHosted: Bool) -> String {
        isHosted
            ? NSLocalizedString("Applies the next time the host loads it.",
                                comment: "Appearance note, in a plugin host")
            : NSLocalizedString("Applies the next time Arcade Ruins opens.",
                                comment: "Appearance note, standalone")
    }

    /// The skin row's title. It carries the caveat when the classic layout is chosen, so the
    /// note stays one line and the block keeps its height.
    static func skinTitleText(skinsApply: Bool) -> String {
        skinsApply
            ? NSLocalizedString("SKIN", comment: "Settings section")
            : NSLocalizedString("SKIN · DESKTOP ONLY", comment: "Settings section, classic layout chosen")
    }

    /// Adds the pickers to the Settings scene, once, in the empty right column under the
    /// buffer-size note. The scene is a 600×382 freeform in both layouts.
    @discardableResult
    static func install(in settings: UIViewController) -> S1AppearanceSettings? {
        settings.loadViewIfNeeded()
        if let existing = installed(in: settings) { return existing }
        let view = S1AppearanceSettings(isHosted: Conductor.sharedInstance.isHosted)
        settings.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.trailingAnchor.constraint(equalTo: settings.view.trailingAnchor, constant: -24),
            view.bottomAnchor.constraint(equalTo: settings.view.bottomAnchor, constant: -16),
            view.widthAnchor.constraint(equalToConstant: 250)
        ])
        return view
    }

    static func installed(in settings: UIViewController) -> S1AppearanceSettings? {
        settings.isViewLoaded ? settings.view.subviews.compactMap { $0 as? S1AppearanceSettings }.first : nil
    }

    private init(isHosted: Bool) {
        self.isHosted = isHosted
        layoutPicker = S1SegmentedControl(titles: Self.layouts.map(S1AppearanceSettings.title(for:)))
        skinPicker = S1SegmentedControl(titles: S1SkinChoice.allCases.map(\.title))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        layoutPicker.selectedIndex = Self.layouts.firstIndex(of: S1Layout.current) ?? 0
        layoutPicker.heightAnchor.constraint(equalToConstant: 26).isActive = true
        layoutPicker.accessibilityLabel = NSLocalizedString("Layout", comment: "Accessibility")
        layoutPicker.onSelect = { [weak self] index in
            guard let layout = Self.layouts[safe: index] else { return }
            S1Layout.setCurrent(layout)
            self?.refresh()
        }

        skinPicker.selectedIndex = S1SkinChoice.allCases.firstIndex(of: S1SkinChoice.chosen) ?? 0
        skinPicker.heightAnchor.constraint(equalToConstant: 26).isActive = true
        skinPicker.accessibilityLabel = NSLocalizedString("Skin", comment: "Accessibility")
        skinPicker.onSelect = { index in
            guard let choice = S1SkinChoice.allCases[safe: index] else { return }
            S1SkinChoice.choose(choice)
        }

        note.font = S1DesktopTheme.font(11)
        note.textColor = UIColor(hex: 0x999999)
        note.textAlignment = .center
        note.numberOfLines = 0

        let column = UIStackView(arrangedSubviews: [
            Self.row(NSLocalizedString("LAYOUT", comment: "Settings section"), layoutPicker, title: UILabel()),
            Self.row(Self.skinTitleText(skinsApply: true), skinPicker, into: skinRow, title: skinTitle),
            note
        ])
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = 6
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: topAnchor),
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func row(_ title: String, _ picker: UIView,
                            into stack: UIStackView = UIStackView(), title label: UILabel) -> UIStackView {
        setTitle(title, on: label)
        label.textAlignment = .center
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 3
        [label, picker].forEach { stack.addArrangedSubview($0) }
        return stack
    }

    private static func setTitle(_ title: String, on label: UILabel) {
        label.attributedText = NSAttributedString(string: title, attributes: [
            .kern: 1.2, .font: S1DesktopTheme.font(12, weight: .demiBold), .foregroundColor: UIColor(hex: 0xd0d0d2)
        ])
    }

    /// The skin only dresses the desktop layout (ADR-046), so it dims when Classic is chosen —
    /// still readable, so the choice is visible, and the note says why.
    private func refresh() {
        let skinsApply = S1Layout.current == .desktop
        skinRow.alpha = skinsApply ? 1 : 0.5
        skinPicker.isUserInteractionEnabled = skinsApply
        Self.setTitle(Self.skinTitleText(skinsApply: skinsApply), on: skinTitle)
        note.text = Self.noteText(isHosted: isHosted)
    }

    // MARK: - For tests

    var selectedLayout: S1Layout? { Self.layouts[safe: layoutPicker.selectedIndex] }
    var selectedSkin: S1SkinChoice? { S1SkinChoice.allCases[safe: skinPicker.selectedIndex] }
    var skinPickerIsEnabled: Bool { skinPicker.isUserInteractionEnabled }
    var noteString: String? { note.text }
    var skinTitleString: String? { skinTitle.attributedText?.string }

    /// Choosing, as a click does: the picker's own path.
    func select(_ layout: S1Layout) {
        guard let index = Self.layouts.firstIndex(of: layout) else { return }
        layoutPicker.selectedIndex = index
        layoutPicker.onSelect?(index)
    }

    func select(_ skin: S1SkinChoice) {
        guard let index = S1SkinChoice.allCases.firstIndex(of: skin) else { return }
        skinPicker.selectedIndex = index
        skinPicker.onSelect?(index)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
