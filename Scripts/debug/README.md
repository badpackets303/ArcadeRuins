# Debug drivers: the running app and plugin, driven without a mouse

These drivers date from 2026-09-10 (ADR-033, STATE.md Session 36). They exercise the **real**
Mac-idiom app, which the test bundle cannot: the tests run in the `.pad` idiom, with no
`NSApplication`. They are scratch-quality tools that worked, kept so the next session need not
rebuild them. Their outputs (logs, PNGs, JSON) go to `$DRIVER_OUT`, which defaults to
`/tmp/arcade-ruins-debug`.

| File | What it does | How to run it |
|---|---|---|
| `desktop_render.py` | Launches the **DerivedData** standalone under lldb and, after `RENDER_SETTLE` seconds (10), writes a PNG of the window in the standard dynamic range (the HDR path stalls in Metal under lldb). The desktop layout's acceptance tool since P6. | `DRIVER_OUT=/tmp/arcade-ruins-debug RENDER_TAG=desktop xcrun lldb -b -o "command script import Scripts/debug/desktop_render.py"`. `RENDER_ARGS="-S1Skin arcade"` launch arguments (a skin, `-S1ClassicLayout YES`); `RENDER_SELECT="Brice Beasley,0: "` selects table rows by label text (a factory bank, not the owner's); `RENDER_PRESS=Presets` presses buttons by title or accessibility label; `RENDER_SIZE=1680x1100` pins the window; `RENDER_SEGUE=SynthOneCore.Manager:SegueToAbout` performs a segue; `RENDER_PRESENTED=1` also renders the presented controller's view. |
| `standalone_driver.py` | Launches the **DerivedData** standalone under lldb, never `/Applications`. Dismisses the launch pop-up, opens Presets, then fires a preset-cell action or a segue. It reports any Objective-C exception with its reason and backtrace; otherwise it probes the presented editor and writes a PNG of the window. | `REPRO_ACTION=editPressed: xcrun lldb -b -o "command script import Scripts/debug/standalone_driver.py"`. Actions: `editPressed:`, `sharePressed:`, `favoritePressed:`, `duplicatePressed:`, or a segue such as `SegueToBankEdit`. `REPRO_RENDER_ONLY=1` just renders the window. `REPRO_TAG` names the outputs. |
| `scene_sweep.py` | Loads every scene of every compiled storyboard into the Mac-idiom window and records any exception, with the view classes each scene holds. This is how ADR-033's sweep was done. | `SWEEP_TAG=name xcrun lldb -b -o "command script import Scripts/debug/scene_sweep.py"` |
| `presethost.swift` | A minimal **out-of-process** host that selects a factory preset, a missing user preset and an empty-named user preset. It reproduces the user-preset crash (STATE.md → *Still open*). | `xcrun swiftc -O Scripts/debug/presethost.swift -o /tmp/presethost && /tmp/presethost` |
| `auhost.swift` | A minimal out-of-process host that shows the plugin's own window the way Logic does, without Logic. | `xcrun swiftc -O Scripts/debug/auhost.swift -o /tmp/auhost && /tmp/auhost` |
| `appearance_walker.m` | **No lldb.** A library injected into the DerivedData standalone (ADR-034, Session 37). It opens the preset editor, the bank editor and search along their click paths, then sweeps every scene, first in the system appearance and then with the window overridden to Light. For every text field and text view it records the resolved colours and the contrast of the glyphs actually drawn, and writes a PNG of each. Then it quits the app. | Compile it, then `open -W -g -n --env DYLD_INSERT_LIBRARIES=… --env S1WALK_OUT=/tmp/walk` the DerivedData app. The exact commands are in the file's header. `-g` keeps it from taking focus; it works because the Debug build has no hardened runtime. |

## Before running them

- **Nothing else may hold the same resources.** That means another copy of the app, a host, or another
  session building into `./DerivedData` or launching the app.
- **The standalone writes the owner's files.** It rewrites `settings.json` and `tunings_v1.json` in
  `~/Library/Application Support/SynthOne` on every launch, and actions such as the star rewrite a
  bank file. Back that folder up first and restore it afterwards, byte-compared, as Session 36 did.
- `sharePressed:` opens a real share sheet on screen.
- **A host loads whichever copy of the plugin macOS elects,** which in practice is `/Applications`, not
  DerivedData. That is true of `auhost`, `presethost` and Logic. Launching the DerivedData standalone
  re-registers its plugin with `pluginkit`, but instantiation still chose `/Applications`.
- **Never drive anything inside the owner's running Logic without asking.**

## Traps these drivers encode

CLAUDE.md records the first four as well.

- **Use Objective-C expressions only.** A Swift expression in a stopped `mach_msg` frame has no module
  context, so `UIKit` and `SynthOneCore` do not resolve.
- **Never call a variadic method such as `stringWithFormat:`.** lldb has no prototypes here, so the
  arguments land in the wrong place. Cast every message send's return value. Pass structs through an
  `objc_msgSend` cast to the right type, obtained with `dlsym`.
- **Give every local a unique prefix.** Names like `table`, `S` or `context` collide with symbols in
  loaded images, and the expression fails to compile.
- **A breakpoint callback does not run inside an expression.** lldb's own exception breakpoint
  interrupts the expression first. Read the exception where it stops, at `objc_exception_throw`, where
  it is in `$x0`.
- **Dismiss the launch pop-up first.** While a controller is presented, every other presentation is
  refused ("already presenting").
- **In async mode, poll `process.GetState()`; do not wait on events.** An attach never delivered its
  stop event (ADR-030).

## Not working yet

**Driving the plugin's interface under lldb inside `auhost`.** `UIWindow`'s window list came back empty
in the extension, so finding its view controllers needs another route. The attempt was not kept.
