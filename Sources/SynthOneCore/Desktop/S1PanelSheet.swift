//  A classic panel shown as a sheet over the desktop layout (P6, ADR-045).
//
//  **New, not ported.** Two of the classic panels are kept whole for now rather than
//  re-homed control by control: the preset browser (P6-6 re-homed it; P8-0 drops it down)
//  and the Tunings panel, whose list, Wilson pitch wheel and Scala import are one
//  storyboard scene that works exactly as it is.
//
//  The sheet *adopts* the panel while it is up. Presentation context follows view
//  controller containment, not the view tree: if the panel stayed a child of `Manager`,
//  its own popovers and editors would try to present from `Manager` — which is already
//  presenting this sheet — and UIKit would refuse them. So the panel becomes the sheet's
//  child on the way in and `Manager`'s child again on the way out.

import UIKit

final class S1PanelSheet: UIViewController {

    private let panel: UIViewController
    private unowned let owner: Manager
    private let panelSize: CGSize
    private let onDismiss: (() -> Void)?

    private static let barHeight: CGFloat = 36

    /// For tests: the one control that closes the sheet.
    private(set) var closeButton: UIButton?

    /// Escape and ⌘W close the sheet, as they close any Mac sheet.
    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closePressed)),
         UIKeyCommand(input: "w", modifierFlags: .command, action: #selector(closePressed))]
    }

    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    /// P6-5: in the plugin the sheet is an overlay inside the plugin's own view. A Catalyst
    /// form sheet is an AppKit sheet on the presenting view's window, and a plugin's view
    /// lives in the host's window — the same bridge that crashed Share (ADR-044). The classic
    /// panels' own modals are `overCurrentContext` for the same reason, and they work in Logic.
    let isOverlay: Bool

    init(title: String, panel: UIViewController, owner: Manager, onDismiss: (() -> Void)? = nil) {
        self.panel = panel
        self.owner = owner
        self.onDismiss = onDismiss
        panel.loadViewIfNeeded()
        panelSize = panel.view.bounds.size
        isOverlay = owner.conductor.isHosted
        super.init(nibName: nil, bundle: nil)
        self.title = title
        modalPresentationStyle = isOverlay ? .overCurrentContext : .formSheet
        preferredContentSize = CGSize(width: panelSize.width, height: panelSize.height + Self.barHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()

        // The card holds the bar and the panel. As a Mac sheet the card is the whole view; as an
        // overlay it is centred on a dimmed backdrop that fills the plugin's view.
        let card = UIView()
        card.backgroundColor = S1DesktopTheme.windowBackground
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        if isOverlay {
            view.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            card.layer.cornerRadius = 10
            card.layer.borderWidth = 1
            card.layer.borderColor = S1DesktopTheme.controlBorder.cgColor
            card.layer.masksToBounds = true
            NSLayoutConstraint.activate([
                card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                card.widthAnchor.constraint(equalToConstant: preferredContentSize.width),
                card.heightAnchor.constraint(equalToConstant: preferredContentSize.height)
            ])
        } else {
            view.backgroundColor = S1DesktopTheme.windowBackground
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: view.topAnchor),
                card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                card.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }

        let bar = S1GradientView(top: S1DesktopTheme.toolbarTop, bottom: S1DesktopTheme.toolbarBottom,
                                 hairline: S1DesktopTheme.sectionBorder)
        bar.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(bar)

        let titleLabel = UILabel()
        titleLabel.attributedText = NSAttributedString(string: (title ?? "").uppercased(), attributes: [
            .kern: 1.2, .font: S1DesktopTheme.font(13, weight: .demiBold), .foregroundColor: S1DesktopTheme.text
        ])
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(titleLabel)

        // A `.system` button drew nothing here under the Mac idiom (2026-09-12, seen by the
        // owner: "no controls"); the toolbar's `.custom` buttons draw, so this is one of those.
        let close = UIButton(type: .custom)
        close.setTitle(NSLocalizedString("Done", comment: "Close a sheet"), for: .normal)
        close.titleLabel?.font = S1DesktopTheme.font(13, weight: .medium)
        close.setTitleColor(S1DesktopTheme.text, for: .normal)
        close.setTitleColor(S1DesktopTheme.orange, for: .highlighted)
        close.useDesignedButtonAppearance()
        close.backgroundColor = S1DesktopTheme.controlFace
        close.layer.cornerRadius = 5
        close.layer.borderWidth = 1
        close.layer.borderColor = S1DesktopTheme.controlBorder.cgColor
        close.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        close.addTarget(self, action: #selector(closePressed), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.heightAnchor.constraint(equalToConstant: 24).isActive = true
        bar.addSubview(close)
        closeButton = close

        // Adopt the panel. If another sheet still holds it — the owner crashed the app on
        // 2026-09-12 in `addChild` here, from a second Presets press while the first sheet had
        // not handed the panel back — that sheet releases it first, and a panel that is mid-
        // presentation anywhere is not adopted at all.
        if let holder = panel.parent as? S1PanelSheet, holder !== self { holder.releasePanel() }
        if panel.parent != nil && panel.parent !== owner {
            panel.willMove(toParent: nil)
            panel.view.removeFromSuperview()
            panel.removeFromParent()
        } else if panel.parent === owner {
            panel.willMove(toParent: nil)
            panel.view.removeFromSuperview()
            panel.removeFromParent()
        }
        addChild(panel)
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(panel.view)
        panel.didMove(toParent: self)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: card.topAnchor),
            bar.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: Self.barHeight),
            titleLabel.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            close.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            panel.view.topAnchor.constraint(equalTo: bar.bottomAnchor),
            panel.view.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            panel.view.widthAnchor.constraint(equalToConstant: panelSize.width),
            panel.view.heightAnchor.constraint(equalToConstant: panelSize.height)
        ])
    }

    @objc private func closePressed() {
        dismiss(animated: true)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        releasePanel()
        onDismiss?()
    }

    /// Hands the panel back to `Manager`. Its view goes into the hidden classic container,
    /// where it lived before, so nothing else about it changes. Safe to call twice.
    func releasePanel() {
        guard panel.parent === self else { return }
        panel.willMove(toParent: nil)
        panel.view.removeFromSuperview()
        panel.removeFromParent()
        owner.addChild(panel)
        panel.view.translatesAutoresizingMaskIntoConstraints = true
        panel.view.frame = CGRect(origin: .zero, size: panelSize)
        owner.topContainerView.addSubview(panel.view)
        panel.didMove(toParent: owner)
    }
}
