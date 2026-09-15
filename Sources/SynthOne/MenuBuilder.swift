//  The macOS menu bar (P3-6).
//
//  **New, not ported** — an iPad app has no menu bar. Catalyst gives every app a
//  default one full of items a synthesiser has no use for (Format, most of Edit,
//  a New Window command that would open a second synth), so the work is as much
//  removing as adding.
//
//  Commands are routed to the first responder, which is `Manager` while the synth
//  has focus. That is the same responder that handles computer-keyboard notes
//  (P3-5), so nothing new has to be plumbed.

import UIKit
import SynthOneCore

enum MenuBuilder {

    static func build(with builder: UIMenuBuilder) {
        guard builder.system == .main else { return }

        // A synth has no documents, no text formatting, and exactly one window.
        builder.remove(menu: .format)
        builder.remove(menu: .newScene)
        builder.remove(menu: .openRecent)
        builder.remove(menu: .toolbar)
        // `.sidebar` needs Catalyst 15; our floor is 14 (iOS 14 / macOS 11) and it is
        // not worth raising for one empty menu.
        if #available(macCatalyst 15.0, *) { builder.remove(menu: .sidebar) }
        builder.remove(menu: .spelling)
        builder.remove(menu: .substitutions)
        builder.remove(menu: .transformations)
        builder.remove(menu: .speech)
        // A synth has nothing to find; the item's ⌘F is Search Presets (P8-0, and the
        // `_UIMenuBuilderError` logged at every launch since P6-6).
        builder.remove(menu: .find)

        builder.insertSibling(panicMenu(), afterMenu: .standardEdit)
        builder.insertChild(keyboardMenu(), atStartOfMenu: .view)
        builder.insertChild(layoutMenu(), atStartOfMenu: .view)
        builder.insertChild(skinMenu(), atStartOfMenu: .view)
        builder.insertChild(sidebarMenu(), atStartOfMenu: .view)
    }

    /// P6-6, P8-0: the preset browser. Both reach `Manager` through the responder chain; the
    /// selectors are `Manager`'s own, named here because `Manager` is internal to the framework.
    private static func sidebarMenu() -> UIMenu {
        let toggle = UIKeyCommand(title: NSLocalizedString("Preset Browser", comment: "View menu"),
                                  action: NSSelectorFromString("desktopTogglePresets:"),
                                  input: "p", modifierFlags: [.command, .alternate])
        let search = UIKeyCommand(title: NSLocalizedString("Search Presets…", comment: "View menu"),
                                  action: NSSelectorFromString("desktopSearchPresets:"),
                                  input: "f", modifierFlags: .command)
        return UIMenu(title: "", identifier: UIMenu.Identifier("com.badpackets303.SynthOne.sidebar"),
                      options: .displayInline, children: [toggle, search])
    }

    /// P7 (ADR-046): View ▸ Skin ▸ Studio | Arcade. The chosen one is checked by
    /// `AppDelegate.validate(_:)`; the change applies at the next launch.
    private static func skinMenu() -> UIMenu {
        let items = S1SkinChoice.allCases.map { choice in
            UICommand(title: choice.title, action: #selector(AppDelegate.chooseSkin(_:)), propertyList: choice.rawValue)
        }
        let skin = UIMenu(title: NSLocalizedString("Skin", comment: "View menu"),
                          identifier: UIMenu.Identifier("com.badpackets303.SynthOne.skin.choices"), children: items)
        return UIMenu(title: "", identifier: UIMenu.Identifier("com.badpackets303.SynthOne.skin"),
                      options: .displayInline, children: [skin])
    }

    /// P6 (ADR-045): the classic iPad layout stays available. The item's check mark is
    /// kept current by `AppDelegate.validate(_:)`; the change applies at the next launch.
    private static func layoutMenu() -> UIMenu {
        let classic = UICommand(title: NSLocalizedString("Classic Layout", comment: "View menu"),
                                action: #selector(AppDelegate.toggleClassicLayout(_:)))
        return UIMenu(title: "", identifier: UIMenu.Identifier("com.badpackets303.SynthOne.layout"),
                      options: .displayInline, children: [classic])
    }

    /// Panic is the one command a synth genuinely needs at the menu level: notes
    /// stuck on from a MIDI cable pulled mid-note, or a crashed host, and the only
    /// escape is a hard reset. ⌘. is what the rest of the platform uses for "stop".
    private static func panicMenu() -> UIMenu {
        let panic = UIKeyCommand(title: NSLocalizedString("Panic", comment: "Stop all notes"),
                                 action: #selector(AppDelegate.panic(_:)),
                                 input: ".",
                                 modifierFlags: .command)
        return UIMenu(title: "", identifier: UIMenu.Identifier("com.badpackets303.SynthOne.panic"),
                      options: .displayInline, children: [panic])
    }

    /// The typed-keyboard octave and velocity controls, discoverable rather than
    /// folklore. The keys themselves are handled in `Manager+ComputerKeyboard`;
    /// these are here so a new user can find out they exist.
    private static func keyboardMenu() -> UIMenu {
        let items = [
            ("Octave Down", "z"), ("Octave Up", "x"),
            ("Velocity Down", "c"), ("Velocity Up", "v")
        ].map { title, key in
            UICommand(title: NSLocalizedString(title, comment: "Musical typing"),
                      action: #selector(AppDelegate.showMusicalTypingHelp(_:)),
                      propertyList: key)
        }
        return UIMenu(title: NSLocalizedString("Musical Typing", comment: "Menu title"),
                      identifier: UIMenu.Identifier("com.badpackets303.SynthOne.typing"),
                      children: items)
    }
}
