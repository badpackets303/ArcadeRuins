//  The desktop layout (P6, ADR-045).
//
//  **New, not ported.** `Manager` and its panels are loaded from the classic
//  storyboards exactly as before, so every control exists, is bound to its parameter,
//  answers MIDI learn and VoiceOver, and drives the same `Conductor`. This object then
//  builds the Mac window — toolbar, four rows of sections, a play bar, a status bar and a
//  preset browser that drops down from the toolbar — over `Manager`'s view, hides the
//  classic hierarchy, and **moves the
//  controls** out of the storyboard panels into the new sections. Nothing is rebound;
//  only where a control sits, how big it is drawn and what sits next to it changes.
//
//  The classic view stays loaded but hidden. Its containers still hold the panel views
//  (minus the controls), the keyboard and the wheels, which `Manager`'s callbacks and
//  the computer keyboard still talk to.
//
//  Layout is Auto Layout throughout; the window is fluid above
//  `S1DesktopTheme.minimumWindowSize`.

import UIKit

final class S1DesktopLayout: NSObject {

    unowned let manager: Manager

    /// Everything the layout draws, over the classic view.
    let root = UIView()

    // Regions
    let toolbar = S1GradientView(top: S1DesktopTheme.toolbarTop, bottom: S1DesktopTheme.toolbarBottom,
                                 hairline: S1DesktopTheme.hairline)
    /// The preset browser, dropped down from the toolbar's preset name (P8-0; it was a sidebar
    /// from P6-6 to P7). Hidden until asked for.
    let presetPanel = UIView()
    private let presetBackdrop = UIView()
    let editor = UIStackView()
    let playBar = S1GradientView(top: S1DesktopTheme.playBarTop, bottom: S1DesktopTheme.playBarBottom)
    let statusBar = UIView()
    let statusDivider = UIView()
    /// P7-9 (ADR-059): the painted window and the canvas the template's rectangles are fractions of.
    var templateCanvas: UIView?

    /// The controls moved out of each panel, so MIDI learn can still find them.
    private var movedControls: [ObjectIdentifier: [UIView]] = [:]

    /// The window the layout is designed at, and the smallest it lays out in.
    static var designWindowSize: CGSize { S1DesktopTheme.designSize }
    static var minimumWindowSize: CGSize { S1DesktopTheme.minimumWindowSize }

    /// Sections by name, for tests and later sessions.
    var sections: [String: S1SectionView] = [:]

    /// The skin the layout was built with (P7, ADR-046), and what it hung: for tests.
    let skin: S1Skin = S1Skins.current
    private(set) var toolbarArt: UIView?
    private(set) var panelArt: UIView?
    private(set) var backdropArt: UIView?
    private(set) var wordmark: UIView?

    /// Readouts that show a musical rate when tempo sync is on and Hz or seconds when it is
    /// off. They read the synth, not their knob, so they refresh on the parameters below.
    var rateCells: [S1ControlCell] = []

    /// The filter-type picker; drives and follows the classic `FilterTypeButton`.
    private(set) var filterPicker: S1SegmentedControl?

    // MARK: - Following parameters (P6-2)

    func parameterDidChange(_ parameter: S1Parameter, value: Double) {
        switch parameter {
        case .tempoSyncToArpRate, .arpRate, .lfo1Rate, .lfo2Rate, .delayTime, .autoPanFrequency:
            rateCells.forEach { $0.refresh() }
        case .filterType:
            let index = Int(value)
            if let picker = filterPicker, picker.selectedIndex != index, (0...2).contains(index) {
                picker.selectedIndex = index
            }
        default:
            break
        }
    }

    func dependentParameterDidChange(_ parameter: S1Parameter) {
        switch parameter {
        case .lfo1Rate, .lfo2Rate, .delayTime, .autoPanFrequency:
            rateCells.forEach { $0.refresh() }
        default:
            break
        }
    }

    /// The picker for the classic cycling button: the button keeps the binding and the
    /// accessibility value, the picker is what is seen and clicked.
    func makeFilterPicker(for button: FilterTypeButton) -> S1SegmentedControl {
        let picker = S1SegmentedControl(titles: [
            NSLocalizedString("Low", comment: "Low-pass filter"),
            NSLocalizedString("Band", comment: "Band-pass filter"),
            NSLocalizedString("High", comment: "High-pass filter")
        ])
        picker.selectedIndex = Int(button.value)
        picker.onSelect = { [weak button] index in
            guard let button else { return }
            button.value = Double(index)
            button.setValueCallback(Double(index))
        }
        picker.heightAnchor.constraint(equalToConstant: 18).isActive = true
        filterPicker = picker
        return picker
    }

    /// The toolbar's preset name; clicking it drops the browser down.
    private(set) var presetField = UIView()
    private(set) var presetFieldButton = S1ActionButton(type: .custom)
    private(set) var tuningButton = UIButton(type: .custom)

    // MARK: - Install

    /// Builds the desktop layout over a loaded `Manager`. Call after the storyboards
    /// have been instantiated and `Manager.viewDidLoad` has run, which loads every panel.
    @discardableResult
    static func install(into manager: Manager) -> S1DesktopLayout {
        manager.loadViewIfNeeded()
        let layout = S1DesktopLayout(manager: manager)
        manager.desktopLayout = layout
        layout.build()
        return layout
    }

    private init(manager: Manager) {
        self.manager = manager
        super.init()
    }

    // MARK: - Shell

    private func build() {
        let host = manager.view!
        host.backgroundColor = S1DesktopTheme.windowBackground

        // P6-4: the layout is dark by design — every colour here is a fixed dark grey — so the
        // interface never follows a Light system appearance. `SceneDelegate` pins the window
        // too, for the sheets and popovers presented from it. ADR-034's per-field Light pins
        // in the editors are unaffected: they are set on the fields themselves.
        manager.overrideUserInterfaceStyle = .dark

        // The classic hierarchy stays, hidden. Its controls are about to be moved out.
        for subview in host.subviews { subview.isHidden = true }

        // The storyboard's constraints were written for 1024×768 — the root view's own size,
        // the containers and the keyboard strip — and a 1440-wide window cannot satisfy them,
        // which logged a page of "unable to simultaneously satisfy constraints" at every launch
        // (P6-1). Hidden views need no layout, so every constraint that involves the hidden
        // hierarchy is deactivated. `Manager`'s keyboard callbacks still set constants on
        // their outlets; a constant on an inactive constraint is harmless.
        NSLayoutConstraint.deactivate(host.constraints)
        for subview in host.subviews { deactivateConstraints(in: subview) }

        root.translatesAutoresizingMaskIntoConstraints = false
        root.backgroundColor = S1DesktopTheme.windowBackground
        host.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: host.topAnchor),
            root.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])

        // P7-4: the skin's art under everything (the play bar and status bar may be translucent)
        if let art = skin.makeBackdropArt() {
            art.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(art)
            NSLayoutConstraint.activate([
                art.topAnchor.constraint(equalTo: root.topAnchor),
                art.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                art.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                art.bottomAnchor.constraint(equalTo: root.bottomAnchor)
            ])
            backdropArt = art
        }

        for region in [toolbar, editor, playBar, statusBar] as [UIView] {
            region.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(region)
        }
        statusBar.backgroundColor = S1DesktopTheme.statusBarBackground

        editor.axis = .vertical
        editor.spacing = S1DesktopTheme.rowGap
        editor.isLayoutMarginsRelativeArrangement = true
        editor.layoutMargins = UIEdgeInsets(top: S1DesktopTheme.editorPadding, left: S1DesktopTheme.editorPadding,
                                            bottom: S1DesktopTheme.editorPadding, right: S1DesktopTheme.editorPadding)

        statusDivider.backgroundColor = S1DesktopTheme.sectionBorder
        statusDivider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(statusDivider)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: S1DesktopTheme.toolbarHeight),

            editor.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            editor.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            editor.bottomAnchor.constraint(equalTo: playBar.topAnchor),

            playBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            playBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            playBar.bottomAnchor.constraint(equalTo: statusDivider.topAnchor),
            playBar.heightAnchor.constraint(equalToConstant: S1DesktopTheme.playBarHeight),

            statusDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusDivider.heightAnchor.constraint(equalToConstant: 1),
            statusDivider.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: S1DesktopTheme.statusBarHeight)
        ])

        buildToolbar()
        buildRows()
        buildPlayBar()
        buildStatusBar()
        if let template = skin.template { applyTemplate(template) }   // P7-9
        buildPresetPanel()   // last: it floats over the rows
    }

    private func deactivateConstraints(in view: UIView) {
        NSLayoutConstraint.deactivate(view.constraints)
        for subview in view.subviews { deactivateConstraints(in: subview) }
    }

    // MARK: - Toolbar

    var header: HeaderViewController? {
        manager.children.first { $0 is HeaderViewController } as? HeaderViewController
    }

    private func buildToolbar() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: S1DesktopTheme.trafficLightAllowance),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor)
        ])

        // P7: the skin's art sits behind the controls
        if let art = skin.makeToolbarArt() {
            art.translatesAutoresizingMaskIntoConstraints = false
            toolbar.insertSubview(art, at: 0)
            NSLayoutConstraint.activate([
                art.topAnchor.constraint(equalTo: toolbar.topAnchor),
                art.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor),
                art.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor),
                art.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -1)
            ])
            toolbarArt = art
        }

        // Wordmark: the owner's artwork, the header's own image — or the skin's own.
        let wordmark: UIView
        if let neon = skin.makeWordmark() {
            wordmark = neon
        } else {
            let image = UIImageView(image: UIImage.synthOne("s1_logo"))
            image.contentMode = .scaleAspectFit
            wordmark = image
        }
        sized(wordmark, width: skin.dress.wordmarkSize.width, height: skin.dress.wordmarkSize.height)   // P7-4: the skin's frame
        stack.addArrangedSubview(wordmark)
        self.wordmark = wordmark
        stack.addArrangedSubview(flexibleSpace())

        // Preset navigator: previous · display strip · next · dice · save
        guard let header else { return }
        let previous = toolbarButton(systemImage: "chevron.left") { [weak header] in header?.previousPresetPressed(UIButton()) }
        let next = toolbarButton(systemImage: "chevron.right") { [weak header] in header?.nextPresetPressed(UIButton()) }

        let display = header.displayLabel!
        move(display, into: nil)
        display.font = S1DesktopTheme.font(15, weight: .medium)
        display.textColor = S1DesktopTheme.text
        display.textAlignment = .center
        display.backgroundColor = .clear
        let field = fieldContainer(display, width: 340, height: 30)
        presetField = field

        // P8-0: the name is the way into the preset browser. A chevron says so; a clear button
        // over the whole field takes the click (the label itself is the classic outlet, left alone).
        let chevron = UILabel()
        chevron.text = "▾"
        chevron.font = S1DesktopTheme.font(15, weight: .medium)
        chevron.textColor = S1DesktopTheme.dim
        chevron.translatesAutoresizingMaskIntoConstraints = false
        field.addSubview(chevron)
        let trigger = presetFieldButton
        trigger.useDesignedButtonAppearance()
        trigger.accessibilityLabel = NSLocalizedString("Presets", comment: "Open the preset browser")
        trigger.accessibilityHint = NSLocalizedString("Opens the preset browser", comment: "Accessibility hint")
        trigger.action = { [weak self] in self?.togglePresetPanel() }
        trigger.translatesAutoresizingMaskIntoConstraints = false
        field.addSubview(trigger)
        NSLayoutConstraint.activate([
            chevron.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -9),
            chevron.centerYAnchor.constraint(equalTo: field.centerYAnchor, constant: -1),
            trigger.topAnchor.constraint(equalTo: field.topAnchor),
            trigger.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            trigger.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            trigger.bottomAnchor.constraint(equalTo: field.bottomAnchor)
        ])

        let navigator = UIStackView(arrangedSubviews: [previous, field, next])
        navigator.axis = .horizontal
        navigator.alignment = .center
        navigator.spacing = 2
        stack.addArrangedSubview(navigator)

        let dice = header.diceButton!
        move(dice, into: nil)
        sized(dice, width: 28, height: 28)
        stack.addArrangedSubview(dice)

        let save = header.saveButton!
        move(save, into: nil)
        restyle(button: save, width: 56)
        stack.addArrangedSubview(save)

        // The scope. `Conductor` owns the plot; the generators panel put it in a container.
        // In the plugin it is fed from the render thread's ring (ADR-028), so it shows there too.
        if let plot = manager.conductor.audioPlotter {
            move(plot, into: nil)
            sized(plot, width: 110, height: 28)
            plot.layer.cornerRadius = 4
            plot.backgroundColor = S1DesktopTheme.fieldBackground
            stack.addArrangedSubview(plot)
        }

        stack.addArrangedSubview(flexibleSpace())

        // Record (standalone only; the plugin's host records), Panic, About, Settings, Presets.
        let generators = manager.generatorsPanel
        if !manager.conductor.isHosted, let record = generators.recordButton, let status = generators.recordStatus {
            move(record, into: nil)
            move(status, into: nil)
            sized(record, width: 22, height: 22)
            status.font = S1DesktopTheme.font(12)
            status.textColor = S1DesktopTheme.label
            let recordStack = UIStackView(arrangedSubviews: [record, status])
            recordStack.axis = .horizontal
            recordStack.alignment = .center
            recordStack.spacing = 4
            stack.addArrangedSubview(recordStack)
            remember(record, from: generators)
        }
        for button in [header.panicButton!, header.aboutButton!] {
            move(button, into: nil)
            restyle(button: button, width: 56)
            stack.addArrangedSubview(button)
        }
        let settings = manager.midiButton!
        move(settings, into: nil)
        restyle(button: settings, width: 70)
        stack.addArrangedSubview(settings)

        // Web, Apps, More and the dev button do not travel: marketing links and a
        // developer panel have no place on the desktop toolbar.
    }

    /// A second press while a sheet is up closes it; nothing is presented over a sheet.
    private func dismissSheetIfUp() -> Bool {
        guard let presented = manager.presentedViewController else { return false }
        presented.dismiss(animated: true)
        return true
    }

    @objc private func tuningPressed() {
        if dismissSheetIfUp() { return }
        let panel = manager.tuningsPanel
        panel.loadViewIfNeeded()
        panel.leftNavButton?.isHidden = true
        panel.rightNavButton?.isHidden = true
        let sheet = S1PanelSheet(title: NSLocalizedString("Tunings", comment: "Sheet title"),
                                 panel: panel, owner: manager) { [weak self] in self?.refreshTuningButton() }
        manager.present(sheet, animated: true)
    }

    // MARK: - The preset browser (P6-6 as a sidebar; P8-0 as a drop-down)

    private(set) var isPresetPanelVisible = false
    private var searchButton: UIButton?

    /// The classic preset panel, re-homed as a column: search, the category and bank list, the
    /// presets of the selection, the selected preset's category and notes, and the buttons.
    /// Every table, cell and button is the storyboard's, with its data source, delegate and
    /// callbacks; only its place, size and dress change. The column sits in a card that drops
    /// down from the toolbar's preset name, over the rows, and closes on a click anywhere else.
    private func buildPresetPanel() {
        presetBackdrop.translatesAutoresizingMaskIntoConstraints = false
        presetBackdrop.backgroundColor = .clear
        presetBackdrop.isHidden = true
        presetBackdrop.accessibilityLabel = NSLocalizedString("Close the preset browser", comment: "Accessibility")
        let close = S1ActionButton(type: .custom)
        close.action = { [weak self] in self?.setPresetPanelVisible(false) }
        close.translatesAutoresizingMaskIntoConstraints = false
        presetBackdrop.addSubview(close)
        root.addSubview(presetBackdrop)

        presetPanel.translatesAutoresizingMaskIntoConstraints = false
        presetPanel.backgroundColor = S1DesktopTheme.panelBackground
        presetPanel.layer.cornerRadius = 10
        presetPanel.layer.borderWidth = 1
        presetPanel.layer.borderColor = S1DesktopTheme.controlBorder.cgColor
        presetPanel.layer.shadowColor = UIColor.black.cgColor
        presetPanel.layer.shadowOpacity = 0.6
        presetPanel.layer.shadowRadius = 14
        presetPanel.layer.shadowOffset = CGSize(width: 0, height: 6)
        presetPanel.isHidden = true
        presetPanel.alpha = 0
        root.addSubview(presetPanel)

        let height = presetPanel.heightAnchor.constraint(equalToConstant: S1DesktopTheme.presetPanelHeight)
        height.priority = .defaultHigh   // a short window shortens the panel
        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: presetBackdrop.topAnchor),
            close.leadingAnchor.constraint(equalTo: presetBackdrop.leadingAnchor),
            close.trailingAnchor.constraint(equalTo: presetBackdrop.trailingAnchor),
            close.bottomAnchor.constraint(equalTo: presetBackdrop.bottomAnchor),
            presetBackdrop.topAnchor.constraint(equalTo: root.topAnchor),
            presetBackdrop.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            presetBackdrop.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            presetBackdrop.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            // P7-9: a template's header is taller than the toolbar, so the card hangs from the name itself
            presetPanel.topAnchor.constraint(equalTo: skin.template == nil ? toolbar.bottomAnchor : presetField.bottomAnchor,
                                             constant: skin.template == nil ? 4 : 10),
            presetPanel.centerXAnchor.constraint(equalTo: presetField.centerXAnchor),
            presetPanel.widthAnchor.constraint(equalToConstant: S1DesktopTheme.presetPanelWidth),
            height,
            presetPanel.bottomAnchor.constraint(lessThanOrEqualTo: playBar.topAnchor, constant: -8)
        ])

        let presets = manager.presetsViewController
        presets.loadViewIfNeeded()
        guard let categories = presets.children.first(where: { $0 is PresetsCategoriesViewController }) as? PresetsCategoriesViewController else {
            return
        }
        categories.loadViewIfNeeded()
        // The classic panel wires this in `viewDidAppear`, which a hidden panel never gets.
        categories.categoryDelegate = presets
        presets.rowHeight = 30
        PresetCell.centresContentVertically = true
        // The category cell's label is 22 points tall between the content view's 8-point
        // margins: 38 is the shortest row that satisfies the storyboard's constraints.
        categories.rowHeight = 38

        // P7: the skin's art sits behind the column
        if let art = skin.makePanelArt() {
            art.translatesAutoresizingMaskIntoConstraints = false
            art.layer.cornerRadius = 10
            art.layer.masksToBounds = true
            presetPanel.addSubview(art)
            NSLayoutConstraint.activate([
                art.topAnchor.constraint(equalTo: presetPanel.topAnchor),
                art.leadingAnchor.constraint(equalTo: presetPanel.leadingAnchor),
                art.trailingAnchor.constraint(equalTo: presetPanel.trailingAnchor),
                art.bottomAnchor.constraint(equalTo: presetPanel.bottomAnchor)
            ])
            panelArt = art
        }

        let column = UIStackView()
        column.axis = .vertical
        column.spacing = 8
        column.isLayoutMarginsRelativeArrangement = true
        column.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 10, right: 12)
        column.translatesAutoresizingMaskIntoConstraints = false
        presetPanel.addSubview(column)
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: presetPanel.topAnchor),
            column.leadingAnchor.constraint(equalTo: presetPanel.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: presetPanel.trailingAnchor),
            column.bottomAnchor.constraint(equalTo: presetPanel.bottomAnchor)
        ])

        // Header: PRESETS, and the New Bank button
        let title = UILabel()
        title.attributedText = NSAttributedString(string: "PRESETS", attributes: [
            .kern: 1.2, .font: S1DesktopTheme.font(11, weight: .demiBold), .foregroundColor: S1DesktopTheme.dim
        ])
        let newBank = presets.newBankButton!
        move(newBank, into: nil)
        restyle(button: newBank, width: 26)
        newBank.setTitle("+", for: .normal)
        newBank.titleLabel?.font = S1DesktopTheme.font(15, weight: .medium)
        newBank.accessibilityLabel = NSLocalizedString("New Bank", comment: "Sidebar button")
        let header = UIStackView(arrangedSubviews: [title, flexibleSpace(), newBank])
        header.axis = .horizontal
        header.alignment = .center
        column.addArrangedSubview(header)

        // Search: the classic button, dressed as a field
        let search = presets.searchtoolButton!
        move(search, into: nil)
        search.setTitle(NSLocalizedString("Search presets…   ⌘F", comment: "Sidebar search"), for: .normal)
        search.titleLabel?.font = S1DesktopTheme.font(12)
        search.setTitleColor(S1DesktopTheme.dim, for: .normal)
        search.contentHorizontalAlignment = .left
        search.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        search.backgroundColor = S1DesktopTheme.fieldBackground
        search.layer.cornerRadius = 6
        search.layer.borderWidth = 1
        search.layer.borderColor = S1DesktopTheme.sectionBorder.cgColor
        search.heightAnchor.constraint(equalToConstant: 26).isActive = true
        column.addArrangedSubview(search)
        searchButton = search

        // Categories and banks
        let banks = categories.categoryTableView!
        move(banks, into: nil)
        dress(table: banks)
        banks.heightAnchor.constraint(equalToConstant: 228).isActive = true   // six rows
        column.addArrangedSubview(framed(banks))

        // The presets of the selection: takes the height
        let list = presets.tableView!
        move(list, into: nil)
        dress(table: list)
        list.setContentHuggingPriority(.defaultLow, for: .vertical)
        list.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        column.addArrangedSubview(framed(list))

        // The selected preset: category and notes (the notes are editable, as in the classic panel)
        let category = presets.categoryLabel!
        move(category, into: nil)
        category.font = S1DesktopTheme.font(11)
        category.textColor = S1DesktopTheme.dim
        let notes = presets.presetDescriptionField!
        move(notes, into: nil)
        notes.font = S1DesktopTheme.font(11)
        notes.textColor = S1DesktopTheme.label
        notes.backgroundColor = S1DesktopTheme.fieldBackground
        notes.layer.cornerRadius = 4
        notes.layer.borderWidth = 1
        notes.layer.borderColor = S1DesktopTheme.sectionBorder.cgColor
        notes.heightAnchor.constraint(equalToConstant: 52).isActive = true
        column.addArrangedSubview(category)
        column.addArrangedSubview(notes)

        // Buttons: New · Import · Reorder · Import Bank. (`doneEditingButton` is hidden and unused
        // in the classic panel too — Reorder itself becomes the Done button while reordering.)
        func small(_ button: UIButton, _ text: String) -> UIButton {
            move(button, into: nil)
            button.titleLabel?.font = S1DesktopTheme.font(12, weight: .medium)
            button.setTitleColor(S1DesktopTheme.text, for: .normal)
            button.layer.cornerRadius = 5
            button.layer.borderWidth = 1
            button.layer.borderColor = S1DesktopTheme.controlBorder.cgColor
            button.backgroundColor = S1DesktopTheme.controlFace
            button.heightAnchor.constraint(equalToConstant: 24).isActive = true
            button.setTitle(text, for: .normal)
            return button
        }
        let reorder = small(presets.reorderButton, "Reorder")
        let grid = UIStackView(arrangedSubviews: [
            UIStackView(arrangedSubviews: [small(presets.newButton, "New"), small(presets.importButton, "Import")]),
            UIStackView(arrangedSubviews: [reorder, small(presets.importBankButton, "Import Bank")])
        ])
        // The classic callback retitles Reorder "I'M DONE!" in black while the list is in
        // reorder mode, which is unreadable on the desktop button face; keep the behaviour,
        // change the words and the colour after it has run.
        let classicReorder = presets.reorderButton.setValueCallback
        presets.reorderButton.setValueCallback = { [weak presets, weak reorder] value in
            classicReorder(value)
            guard let presets, let reorder else { return }
            reorder.setTitle(presets.tableView.isEditing ? NSLocalizedString("Done", comment: "End reordering")
                                                        : NSLocalizedString("Reorder", comment: "Sidebar button"), for: .normal)
            reorder.setTitleColor(presets.tableView.isEditing ? S1DesktopTheme.orange : S1DesktopTheme.text, for: .normal)
        }
        for line in grid.arrangedSubviews.compactMap({ $0 as? UIStackView }) {
            line.axis = .horizontal
            line.distribution = .fillEqually
            line.spacing = 6
        }
        grid.axis = .vertical
        grid.spacing = 6
        column.addArrangedSubview(grid)

        // ⌘F searches, ⌥⌘P opens or closes the browser and Escape closes it, from anywhere in the window.
        manager.addKeyCommand(UIKeyCommand(input: "f", modifierFlags: .command, action: #selector(Manager.desktopSearchPresets(_:))))
        manager.addKeyCommand(UIKeyCommand(input: "p", modifierFlags: [.command, .alternate], action: #selector(Manager.desktopTogglePresets(_:))))
        manager.addKeyCommand(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(Manager.desktopClosePresets(_:))))
    }

    /// P7: a skin may put a screen bezel round a list. The table keeps its own size.
    private func framed(_ table: UITableView) -> UIView {
        guard let accent = skin.frameAccent else { return table }
        let frame = S1CRTFrame(content: table, accent: accent)
        frame.setContentHuggingPriority(table.contentHuggingPriority(for: .vertical), for: .vertical)
        frame.setContentCompressionResistancePriority(table.contentCompressionResistancePriority(for: .vertical), for: .vertical)
        return frame
    }

    private func dress(table: UITableView) {
        table.backgroundColor = S1DesktopTheme.fieldBackground
        table.layer.cornerRadius = 6
        table.layer.borderWidth = 1
        table.layer.borderColor = S1DesktopTheme.sectionBorder.cgColor
        table.layer.masksToBounds = true
        table.separatorColor = S1DesktopTheme.sectionBorder
        table.showsVerticalScrollIndicator = true
    }

    /// Opens the classic search screen, which presents over the window. The drop-down closes
    /// first: the search's card sits over everything, and a chosen preset shows in the toolbar.
    func searchPresets() {
        setPresetPanelVisible(false, animated: false)
        searchButton?.sendActions(for: .touchUpInside)
    }

    /// Drops the preset browser down from the toolbar, or puts it away.
    func togglePresetPanel() {
        setPresetPanelVisible(!isPresetPanelVisible)
    }

    func setPresetPanelVisible(_ visible: Bool, animated: Bool = true) {
        guard visible != isPresetPanelVisible else { return }
        isPresetPanelVisible = visible
        presetBackdrop.isHidden = !visible
        if visible {
            presetPanel.isHidden = false
            root.bringSubviewToFront(presetBackdrop)
            root.bringSubviewToFront(presetPanel)
            manager.view.layoutIfNeeded()
        }
        let changes = { self.presetPanel.alpha = visible ? 1 : 0 }
        let done: (Bool) -> Void = { _ in if !visible { self.presetPanel.isHidden = true } }
        if animated {
            UIView.animate(withDuration: 0.15, animations: changes, completion: done)
        } else {
            changes(); done(true)
        }
    }

    // MARK: - Play bar

    private func buildPlayBar() {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        playBar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: playBar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: playBar.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: playBar.centerYAnchor)
        ])

        for button in [manager.holdButton!, manager.monoButton!, manager.midiLearnToggle!] as [UIButton] {
            move(button, into: nil)
            restyle(button: button, width: button === manager.midiLearnToggle ? 84 : 52)
            stack.addArrangedSubview(button)
        }
        for (stepper, title) in [(manager.transposeStepper!, "Transpose"), (manager.octaveStepper!, "Octave")] as [(UIView, String)] {
            move(stepper, into: nil)
            sized(stepper, width: 96, height: 26)
            let caption = UILabel()
            caption.text = title
            caption.font = S1DesktopTheme.font(12)
            caption.textColor = S1DesktopTheme.dim
            let pair = UIStackView(arrangedSubviews: [caption, stepper])
            pair.axis = .horizontal
            pair.alignment = .center
            pair.spacing = 4
            stack.addArrangedSubview(pair)
        }
        let wheels = manager.modWheelSettings!
        move(wheels, into: nil)
        restyle(button: wheels, width: 60)
        stack.addArrangedSubview(wheels)

        let typing = UILabel()
        typing.text = NSLocalizedString("Musical typing on: A–K play, Z/X octave, C/V velocity", comment: "Play bar hint")
        typing.font = S1DesktopTheme.font(11)
        typing.textColor = S1DesktopTheme.dim
        stack.addArrangedSubview(typing)

        stack.addArrangedSubview(flexibleSpace())
        // The on-screen keyboard has no place in this layout (owner, 2026-09-12). Its
        // settings button goes with it; Bluetooth pairing was never ours (P3-4).
        manager.configKeyboardButton?.isHidden = true
    }

    // MARK: - Status bar

    private func buildStatusBar() {
        tuningButton = plainButton(title: "", width: 0)
        tuningButton.contentEdgeInsets = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        tuningButton.addTarget(self, action: #selector(tuningPressed), for: .touchUpInside)
        tuningButton.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(tuningButton)
        refreshTuningButton()

        let hint = UILabel()
        hint.text = NSLocalizedString("Drag a knob, or scroll over it · ⌥ for fine · double‑click resets", comment: "Status bar hint")
        hint.font = S1DesktopTheme.font(11)
        hint.textColor = S1DesktopTheme.dim
        hint.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(hint)

        NSLayoutConstraint.activate([
            tuningButton.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 8),
            tuningButton.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            tuningButton.heightAnchor.constraint(equalToConstant: 20),
            hint.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            hint.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
    }

    func refreshTuningButton() {
        // The Tunings panel loads its model lazily; before it has, the default is what plays.
        let name = manager.tuningsPanel.isViewLoaded ? manager.tuningsPanel.tuningModel.tuningName : Tuning.defaultName
        let text = NSMutableAttributedString(string: NSLocalizedString("Tuning  ", comment: "Status bar"), attributes: [
            .font: S1DesktopTheme.font(11), .foregroundColor: S1DesktopTheme.dim
        ])
        text.append(NSAttributedString(string: name, attributes: [
            .font: S1DesktopTheme.font(11, weight: .medium), .foregroundColor: S1DesktopTheme.label
        ]))
        tuningButton.setAttributedTitle(text, for: .normal)
    }

    // MARK: - Classic screens presented over the layout (P6-7)

    /// The classic full-window presentations, and the card each gets. About is a 1024×768
    /// scene that sat in the window's top-left corner; the preset and bank editors are small
    /// scenes that floated near the top; Search stretched to the whole window. Each is now a
    /// centred card over a dimmed backdrop, at its own size. The popovers (Settings, Wheels)
    /// are left alone: they anchor to their buttons and are the right shape already.
    static let cardSizes: [String: CGSize] = [
        "SegueToAbout": CGSize(width: 1_024, height: 768),
        "SegueToEdit": CGSize(width: 560, height: 336),
        "SegueToBankEdit": CGSize(width: 512, height: 299),
        "SegueToSearch": CGSize(width: 640, height: 337)   // the scene's own height: its table does not stretch
    ]

    /// Called from `prepare(for:)` in `Manager` and `PresetsViewController`. Replaces the
    /// destination's view with a backdrop holding the original view in a centred card; the
    /// controller's outlets still point into the original view.
    @discardableResult
    func dressPresented(_ controller: UIViewController, segue identifier: String?) -> UIView? {
        guard let identifier, let size = Self.cardSizes[identifier] else { return nil }
        controller.loadViewIfNeeded()
        guard let content = controller.view, content.superview == nil, content.tag != Self.dressedTag else { return nil }

        let backdrop = UIView()
        backdrop.tag = Self.dressedTag   // the controller's view from now on: never wrapped twice
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        let card = UIView()
        card.backgroundColor = S1DesktopTheme.windowBackground
        card.layer.cornerRadius = 10
        card.layer.borderWidth = 1
        card.layer.borderColor = S1DesktopTheme.controlBorder.cgColor
        card.layer.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false
        card.tag = Self.dressedTag
        backdrop.addSubview(card)
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: size.width),
            card.heightAnchor.constraint(equalToConstant: size.height),
            content.topAnchor.constraint(equalTo: card.topAnchor),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor)
        ])
        controller.view = backdrop
        controller.modalPresentationStyle = .overCurrentContext
        setPresetPanelVisible(false, animated: false)
        return card
    }

    static let dressedTag = 0x5155_4454   // "QUDT", marks a card so a view is never wrapped twice

    // MARK: - Moving controls

    /// Takes a storyboard control out of its panel. The stack or cell it joins sizes it.
    func move(_ view: UIView, into container: UIView?) {
        view.removeFromSuperview()
        view.isHidden = false
        view.translatesAutoresizingMaskIntoConstraints = false
        container?.addSubview(view)
    }

    /// Records a moved control against the panel it came from, for MIDI learn.
    func remember(_ view: UIView, from panel: UIViewController) {
        movedControls[ObjectIdentifier(panel), default: []].append(view)
    }

    /// The controls `Manager` should offer MIDI learn for this panel, now that they are
    /// no longer subviews of the panel's view.
    func controlViews(of panel: UIViewController) -> [UIView]? {
        movedControls[ObjectIdentifier(panel)]
    }

    // MARK: - Small helpers

    func sized(_ view: UIView, width: CGFloat, height: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: height)
        ])
    }

    func flexibleSpace() -> UIView {
        let space = UIView()
        space.setContentHuggingPriority(.defaultLow - 10, for: .horizontal)
        space.setContentCompressionResistancePriority(.defaultLow - 10, for: .horizontal)
        return space
    }

    /// A storyboard button in the desktop's button dress.
    func restyle(button: UIButton, width: CGFloat) {
        button.titleLabel?.font = S1DesktopTheme.font(12, weight: .medium)
        button.setTitleColor(S1DesktopTheme.text, for: .normal)
        button.layer.cornerRadius = 5
        button.layer.borderWidth = 1
        button.layer.borderColor = S1DesktopTheme.controlBorder.cgColor
        button.backgroundColor = S1DesktopTheme.controlFace
        sized(button, width: width, height: 24)
    }

    func plainButton(title: String, width: CGFloat) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.useDesignedButtonAppearance()
        button.setTitleColor(S1DesktopTheme.text, for: .normal)
        button.setTitleColor(S1DesktopTheme.orange, for: .highlighted)
        button.titleLabel?.font = S1DesktopTheme.font(12, weight: .medium)
        button.layer.cornerRadius = 5
        button.layer.borderWidth = 1
        button.layer.borderColor = S1DesktopTheme.controlBorder.cgColor
        button.backgroundColor = S1DesktopTheme.controlFace
        button.translatesAutoresizingMaskIntoConstraints = false
        if width > 0 { sized(button, width: width, height: 24) }
        return button
    }

    private func toolbarButton(systemImage: String, action: @escaping () -> Void) -> UIButton {
        let button = S1ActionButton(type: .custom)
        button.useDesignedButtonAppearance()
        button.setImage(UIImage(systemName: systemImage), for: .normal)
        button.tintColor = S1DesktopTheme.label
        button.action = action
        sized(button, width: 28, height: 28)
        return button
    }

    private func fieldContainer(_ content: UIView, width: CGFloat, height: CGFloat) -> UIView {
        let field = UIView()
        field.backgroundColor = S1DesktopTheme.fieldBackground
        field.layer.cornerRadius = 7
        field.layer.borderWidth = 1
        field.layer.borderColor = S1DesktopTheme.sectionBorder.cgColor
        field.translatesAutoresizingMaskIntoConstraints = false
        field.addSubview(content)
        content.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.widthAnchor.constraint(equalToConstant: width),
            field.heightAnchor.constraint(equalToConstant: height),
            content.leadingAnchor.constraint(equalTo: field.leadingAnchor, constant: 8),
            content.trailingAnchor.constraint(equalTo: field.trailingAnchor, constant: -8),
            content.centerYAnchor.constraint(equalTo: field.centerYAnchor)
        ])
        return field
    }
}

/// A button whose action is a closure, for the few toolbar buttons that are ours.
final class S1ActionButton: UIButton {
    var action: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        addTarget(self, action: #selector(fire), for: .touchUpInside)
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addTarget(self, action: #selector(fire), for: .touchUpInside)
    }
    @objc private func fire() { action?() }
}
