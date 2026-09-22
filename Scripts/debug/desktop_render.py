# lldb driver (Scripts/debug/README.md): launch the DerivedData standalone, wait for it to settle,
# and write a PNG of its window — the desktop layout (P6, ADR-045) for visual sign-off.
#
# Differs from `standalone_driver.py`'s RENDER in one thing: the renderer format asks for the
# **standard** dynamic range. On a P3/HDR display the default format produced an extended-range
# image, and `UIImagePNGRepresentation` then went through ImageIO's HDR converter, which
# compiles a Metal shader and blocked the stopped process (2026-09-12).
#
#   DRIVER_OUT=/tmp/arcade-ruins-debug RENDER_TAG=desktop xcrun lldb -b -o "command script import Scripts/debug/desktop_render.py"
#
# Objective-C only, `ar`-prefixed locals, typed objc_msgSend for structs — see the README.
import lldb, os, time

SCRATCH = os.environ.get("DRIVER_OUT", "/tmp/arcade-ruins-debug")
os.makedirs(SCRATCH, exist_ok=True)
APP = os.path.expanduser("~/Developer/SynthOne/DerivedData/Build/Products/Debug-maccatalyst/"
                         "ArcadeRuins.app/Contents/MacOS/ArcadeRuins")
TAG = os.environ.get("RENDER_TAG", "desktop")
SETTLE = float(os.environ.get("RENDER_SETTLE", "10"))
OUT = os.path.join(SCRATCH, TAG)

WINDOW = """
id arApp = (id)[(id)NSClassFromString(@"UIApplication") sharedApplication];
id arScene = (id)[(id)[arApp connectedScenes] anyObject];
id arWindow = (id)[(id)[arScene windows] firstObject];
"""

# Every window of the scene, so a Catalyst sheet (its own window) can be rendered too.
WINDOWS = WINDOW + """
id arList = (id)[(id)NSClassFromString(@"NSMutableArray") array];
for (id arW in (id)[arScene windows]) {
    (void)[arList addObject:(id)[(id)[(id)[arW class] description] stringByAppendingString:(id)[@" " stringByAppendingString:(id)[(id)[arW rootViewController] description]]]];
}
(id)[arList componentsJoinedByString:@" | "]
"""

RENDER = WINDOW + """
typedef struct { double x, y, w, h; } ARRect;
typedef struct { double w, h; } ARSize;
void *arSend = (void *)dlsym((void *)-2, "objc_msgSend");
arWindow = (id)[(id)[arScene windows] objectAtIndex:(unsigned long)%d];
ARRect arBounds = ((ARRect (*)(id, SEL))arSend)(arWindow, @selector(bounds));
id arFormat = (id)[(id)NSClassFromString(@"UIGraphicsImageRendererFormat") defaultFormat];
(void)[arFormat setPreferredRange:(long)1];
(void)[arFormat setScale:(double)2.0];
id arRenderer = ((id (*)(id, SEL, ARSize, id))arSend)((id)[(id)NSClassFromString(@"UIGraphicsImageRenderer") alloc], @selector(initWithSize:format:), (ARSize){arBounds.w, arBounds.h}, arFormat);
id arLayer = (id)[arWindow layer];
id arImage = (id)[arRenderer imageWithActions:^(id arContext) { (void)[arLayer renderInContext:(void *)[arContext CGContext]]; }];
id arPNG = ((id (*)(id))dlsym((void *)-2, "UIImagePNGRepresentation"))(arImage);
(void)[arPNG writeToFile:@"%s" atomically:(BOOL)1];
(id)[(id)[@"window " stringByAppendingString:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithDouble:arBounds.w] description]] stringByAppendingString:(id)[@"x" stringByAppendingString:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithDouble:arBounds.h] description]]]
"""

# Optional: press a button by its title or accessibility label before rendering (RENDER_PRESS=Presets).
PRESS = WINDOW + """
id arViews = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:arWindow];
id arTopVC = (id)[arWindow rootViewController];
while ((id)[arTopVC presentedViewController] != nil) { arTopVC = (id)[arTopVC presentedViewController]; (void)[arViews addObject:(id)[arTopVC view]]; }
id arHit = nil;
while ((unsigned long)[arViews count] > 0) {
    id arView = (id)[arViews firstObject];
    (void)[arViews removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[arView isKindOfClass:(id)NSClassFromString(@"UIButton")]
        && ((BOOL)[@"%s" isEqual:(id)[arView currentTitle]] || (BOOL)[@"%s" isEqual:(id)[arView accessibilityLabel]])) { arHit = arView; break; }
    (void)[arViews addObjectsFromArray:(id)[arView subviews]];
}
if (arHit != nil) { (void)[arHit sendActionsForControlEvents:(unsigned long)64]; }
(id)(arHit != nil ? @"pressed" : @"no such button")
"""

# A Catalyst sheet is its own NSWindow, hosted by AppKit, so it is not among the scene's
# UIWindows. Render every NSWindow's content view instead (RENDER_NSWINDOWS=1).
NSWINDOWS = """
typedef struct { double x, y, w, h; } ARRect;
typedef struct { double w, h; } ARSize;
void *arSend = (void *)dlsym((void *)-2, "objc_msgSend");
id arNSApp = (id)[(id)NSClassFromString(@"NSApplication") sharedApplication];
id arList = (id)[(id)NSClassFromString(@"NSMutableArray") array];
unsigned long arIndex = 0;
for (id arNSWindow in (id)[arNSApp windows]) {
    id arContent = (id)[arNSWindow contentView];
    ARRect arFrame = ((ARRect (*)(id, SEL))arSend)(arNSWindow, @selector(frame));
    ARRect arBounds = ((ARRect (*)(id, SEL))arSend)(arContent, @selector(bounds));
    id arFormat = (id)[(id)NSClassFromString(@"UIGraphicsImageRendererFormat") defaultFormat];
    (void)[arFormat setPreferredRange:(long)1];
    (void)[arFormat setScale:(double)2.0];
    id arRenderer = ((id (*)(id, SEL, ARSize, id))arSend)((id)[(id)NSClassFromString(@"UIGraphicsImageRenderer") alloc], @selector(initWithSize:format:), (ARSize){arBounds.w, arBounds.h}, arFormat);
    id arLayer = (id)[arContent layer];
    id arImage = (id)[arRenderer imageWithActions:^(id arContext) { if (arLayer != nil) { (void)[arLayer renderInContext:(void *)[arContext CGContext]]; } }];
    id arPNG = ((id (*)(id))dlsym((void *)-2, "UIImagePNGRepresentation"))(arImage);
    id arPath = (id)[@"%s" stringByAppendingString:(id)[(id)[@"-ns" stringByAppendingString:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithUnsignedLong:arIndex] description]] stringByAppendingString:@".png"]];
    (void)[arPNG writeToFile:arPath atomically:(BOOL)1];
    (void)[arList addObject:(id)[(id)[(id)[(id)[arNSWindow class] description] stringByAppendingString:@" "] stringByAppendingString:(id)[(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithDouble:arFrame.w] description] stringByAppendingString:(id)[@"x" stringByAppendingString:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithDouble:arFrame.h] description]]]] stringByAppendingString:(id)[@" visible=" stringByAppendingString:((BOOL)[arNSWindow isVisible] ? @"yes" : @"no")]]];
    arIndex++;
}
(id)[arList componentsJoinedByString:@" | "]
"""

# The presented view controller's view, wherever AppKit hosts it (RENDER_PRESENTED=1).
PRESENTED = WINDOW + """
typedef struct { double x, y, w, h; } ARRect;
typedef struct { double w, h; } ARSize;
void *arSend = (void *)dlsym((void *)-2, "objc_msgSend");
id arTop = (id)[arWindow rootViewController];
while ((id)[arTop presentedViewController] != nil) { arTop = (id)[arTop presentedViewController]; }
id arView = (id)[arTop view];
ARRect arBounds = ((ARRect (*)(id, SEL))arSend)(arView, @selector(bounds));
id arFormat = (id)[(id)NSClassFromString(@"UIGraphicsImageRendererFormat") defaultFormat];
(void)[arFormat setPreferredRange:(long)1];
(void)[arFormat setScale:(double)2.0];
id arRenderer = ((id (*)(id, SEL, ARSize, id))arSend)((id)[(id)NSClassFromString(@"UIGraphicsImageRenderer") alloc], @selector(initWithSize:format:), (ARSize){arBounds.w > 0 ? arBounds.w : 1, arBounds.h > 0 ? arBounds.h : 1}, arFormat);
id arLayer = (id)[arView layer];
id arImage = (id)[arRenderer imageWithActions:^(id arContext) { (void)[arLayer renderInContext:(void *)[arContext CGContext]]; }];
id arPNG = ((id (*)(id))dlsym((void *)-2, "UIImagePNGRepresentation"))(arImage);
(void)[arPNG writeToFile:@"%s" atomically:(BOOL)1];
(id)[(id)[(id)[arTop description] stringByAppendingString:@" "] stringByAppendingString:(id)[(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithDouble:arBounds.w] description] stringByAppendingString:(id)[@"x" stringByAppendingString:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithDouble:arBounds.h] description]]]]
"""

# Optional: ask the scene for a window size before rendering (RENDER_SIZE=1680x1100).
# The same trick SceneDelegate uses (ADR-042): pin the scene's minimum and maximum to the size,
# and macOS resizes the window to it.
RESIZE = WINDOW + """
typedef struct { double w, h; } ARSize;
void *arSend = (void *)dlsym((void *)-2, "objc_msgSend");
id arRestrictions = (id)[arScene sizeRestrictions];
((void (*)(id, SEL, ARSize))arSend)(arRestrictions, @selector(setMinimumSize:), (ARSize){%s, %s});
((void (*)(id, SEL, ARSize))arSend)(arRestrictions, @selector(setMaximumSize:), (ARSize){%s, %s});
(id)@"pinned"
"""

# Optional: select a table row by the text of a label in it, in any UITableView of the window
# (RENDER_SELECT=BankA,Synthwave 1974 — one row per item, 2 s apart). Each table is walked through
# its data source, the row is selected (scrolled to the middle) and its delegate told, so a preset
# sidebar row loads the preset. P6-8: README renders show a factory bank, not the owner's banks.
SELECT = WINDOW + """
id arViews = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:arWindow];
id arTables = (id)[(id)NSClassFromString(@"NSMutableArray") array];
while ((unsigned long)[arViews count] > 0) {
    id arView = (id)[arViews firstObject];
    (void)[arViews removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[arView isKindOfClass:(id)NSClassFromString(@"UITableView")]) { (void)[arTables addObject:arView]; }
    (void)[arViews addObjectsFromArray:(id)[arView subviews]];
}
id arResult = @"no such row";
for (id arTable in arTables) {
    id arSource = (id)[arTable dataSource];
    long arRows = (long)[arSource tableView:arTable numberOfRowsInSection:(long)0];
    for (long arRow = 0; arRow < arRows && (BOOL)[arResult isEqual:@"no such row"]; arRow++) {
        id arPath = (id)[(id)NSClassFromString(@"NSIndexPath") indexPathForRow:arRow inSection:(long)0];
        id arCell = (id)[arSource tableView:arTable cellForRowAtIndexPath:arPath];
        id arQueue = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:arCell];
        while ((unsigned long)[arQueue count] > 0) {
            id arSub = (id)[arQueue firstObject];
            (void)[arQueue removeObjectAtIndex:(unsigned long)0];
            if ((BOOL)[arSub isKindOfClass:(id)NSClassFromString(@"UILabel")] && (id)[arSub text] != nil
                && (BOOL)[(id)[arSub text] containsString:@"%s"]) {
                (void)[arTable selectRowAtIndexPath:arPath animated:(BOOL)0 scrollPosition:(long)2];
                (void)[(id)[arTable delegate] tableView:arTable didSelectRowAtIndexPath:arPath];
                arResult = (id)[@"selected " stringByAppendingString:(id)[arSub text]];
                break;
            }
            (void)[arQueue addObjectsFromArray:(id)[arSub subviews]];
        }
    }
    if (!(BOOL)[arResult isEqual:@"no such row"]) { break; }
}
(id)arResult
"""

# Optional: perform a segue on the first view controller of a class, e.g.
# RENDER_SEGUE=SynthOneCore.PresetsViewController:SegueToEdit, then render the presented view.
SEGUE = WINDOW + """
id arQueue = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:(id)[arWindow rootViewController]];
id arFound = nil;
while ((unsigned long)[arQueue count] > 0) {
    id arVC = (id)[arQueue firstObject];
    (void)[arQueue removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[@"%s" isEqual:(id)[(id)[arVC class] description]]) { arFound = arVC; break; }
    (void)[arQueue addObjectsFromArray:(id)[arVC childViewControllers]];
}
if (arFound != nil) { (void)[arFound performSegueWithIdentifier:@"%s" sender:arFound]; }
(id)(arFound != nil ? @"performed" : @"no such view controller")
"""

# Optional: write the frame of every visible Swift-class view of the window, in window points,
# one per line — "Class x y w h" (RENDER_FRAMES=1 -> <tag>.frames.txt). X3-1 (ADR-083):
# Scripts/check-layout-spec.sh holds the layout specification to these, measured in the running app.
FRAMES = WINDOW + """
typedef struct { double x, y, w, h; } ARRect;
void *arSend = (void *)dlsym((void *)-2, "objc_msgSend");
id arViews = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:arWindow];
id arLines = (id)[(id)NSClassFromString(@"NSMutableString") string];
unsigned long arCount = 0;
while ((unsigned long)[arViews count] > 0) {
    id arView = (id)[arViews firstObject];
    (void)[arViews removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[arView isHidden] || (double)[arView alpha] == 0.0) { continue; }
    (void)[arViews addObjectsFromArray:(id)[arView subviews]];
    id arName = (id)[(id)[arView class] description];
    if (!(BOOL)[arName containsString:@"."]) { continue; }
    ARRect arBounds = ((ARRect (*)(id, SEL))arSend)(arView, @selector(bounds));
    ARRect arFrame = ((ARRect (*)(id, SEL, ARRect, id))arSend)(arView, @selector(convertRect:toView:), arBounds, (id)nil);
    (void)[arLines appendString:arName];
    double arParts[4] = { arFrame.x, arFrame.y, arFrame.w, arFrame.h };
    for (int arPart = 0; arPart < 4; arPart++) {
        (void)[arLines appendString:@" "];
        (void)[arLines appendString:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithDouble:arParts[arPart]] description]];
    }
    (void)[arLines appendString:@"\\n"];
    arCount++;
}
(void)[arLines writeToFile:@"%s" atomically:(BOOL)1 encoding:(unsigned long)4 error:(void *)0];
(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithUnsignedLong:arCount] description]
"""

def log(msg):
    print("[render] " + msg, flush=True)

def pump(listener, process, seconds, until=None):
    end = time.time() + seconds
    ev = lldb.SBEvent()
    while time.time() < end:
        if until and process.GetState() in until:
            return True
        listener.WaitForEvent(1, ev)
    return bool(until) and process.GetState() in until

def evaluate(process, expression):
    frame = process.GetSelectedThread().GetFrameAtIndex(0)
    options = lldb.SBExpressionOptions()
    options.SetLanguage(lldb.eLanguageTypeObjC_plus_plus)
    options.SetIgnoreBreakpoints(True)
    options.SetTimeoutInMicroSeconds(120 * 1000 * 1000)
    value = frame.EvaluateExpression(expression, options)
    if value.GetError().Fail():
        return "ERROR " + value.GetError().GetCString()
    return value.GetObjectDescription() or value.GetSummary() or value.GetValue() or "(no value)"

def __lldb_init_module(debugger, internal_dict):
    debugger.SetAsync(True)
    listener = debugger.GetListener()
    target = debugger.CreateTarget(APP)
    # RENDER_ARGS="-S1Skin arcade" passes launch arguments; UserDefaults reads `-Key value`
    # pairs from them, so a skin or layout can be rendered without touching the owner's defaults.
    info = lldb.SBLaunchInfo(os.environ.get("RENDER_ARGS", "").split())
    info.AddOpenFileAction(1, OUT + ".stdout", False, True)
    info.AddOpenFileAction(2, OUT + ".stderr", False, True)
    error = lldb.SBError()
    process = target.Launch(info, error)
    if error.Fail():
        log("launch failed: " + error.GetCString()); return
    log("launched pid %d" % process.GetProcessID())
    pump(listener, process, SETTLE)
    process.Stop()
    if not pump(listener, process, 15, until=[lldb.eStateStopped]):
        log("could not stop the process"); process.Kill(); return
    size = os.environ.get("RENDER_SIZE")
    if size:
        w, h = size.lower().split("x")
        log("resize %sx%s -> %s" % (w, h, evaluate(process, RESIZE % (w, h, w, h))))
        process.Continue()
        pump(listener, process, 3)
        process.Stop()
        pump(listener, process, 15, until=[lldb.eStateStopped])
    for select in [p for p in os.environ.get("RENDER_SELECT", "").split(",") if p]:
        log("select %s -> %s" % (select, evaluate(process, SELECT % select)))
        process.Continue()
        pump(listener, process, 2)
        if process.GetState() in (lldb.eStateExited, lldb.eStateCrashed):
            log("the process died after selecting %s" % select); return
        process.Stop()
        pump(listener, process, 15, until=[lldb.eStateStopped])
    segue = os.environ.get("RENDER_SEGUE")
    if segue:
        cls, ident = segue.split(":")
        log("segue %s on %s -> %s" % (ident, cls, evaluate(process, SEGUE % (cls, ident))))
        process.Continue()
        pump(listener, process, 3)
        if process.GetState() in (lldb.eStateExited, lldb.eStateCrashed):
            log("the process died after the segue"); return
        process.Stop()
        pump(listener, process, 15, until=[lldb.eStateStopped])
    # RENDER_PRESS=Presets,Done,Presets presses each in turn, 2 s apart, searching the window and
    # any presented view for a UIButton with that title. An exception stops the run and is logged.
    for press in [p for p in os.environ.get("RENDER_PRESS", "").split(",") if p]:
        log("press %s -> %s" % (press, evaluate(process, PRESS % (press, press))))
        process.Continue()
        pump(listener, process, 2)
        if process.GetState() in (lldb.eStateExited, lldb.eStateCrashed):
            log("the process died after pressing %s" % press); return
        process.Stop()
        pump(listener, process, 15, until=[lldb.eStateStopped])
    windows = evaluate(process, WINDOWS)
    log("windows -> " + windows)
    count = max(1, windows.count(" | ") + 1)
    for index in range(count):
        suffix = "" if index == 0 else "-%d" % index
        log("render %d -> %s" % (index, evaluate(process, RENDER % (index, OUT + suffix + ".png"))))
    if os.environ.get("RENDER_FRAMES"):
        log("frames -> %s views in %s" % (evaluate(process, FRAMES % (OUT + ".frames.txt")), OUT + ".frames.txt"))
    if os.environ.get("RENDER_PRESENTED"):
        log("presented -> " + evaluate(process, PRESENTED % (OUT + "-presented.png")))
    if os.environ.get("RENDER_NSWINDOWS"):
        log("nswindows -> " + evaluate(process, NSWINDOWS % OUT))
    process.Kill()
    log("killed")
