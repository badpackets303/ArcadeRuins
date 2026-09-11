# lldb driver (Scripts/debug/README.md): launch the DerivedData standalone (NOT /Applications), open the Presets panel
# the way a click does (HeaderViewController.displayLabelTapped, the display label's tap
# target), fire a preset cell's own Edit action (PresetCell.editPressed: ->
# PresetsViewController.editPressed -> performSegue "SegueToEdit"), and capture any
# Objective-C exception that follows.
#
# Objective-C only, no module imports (a Swift expression in a mach_msg frame has no Swift
# context in this build), and no variadic messages: lldb has no prototypes, so
# stringWithFormat: arguments land in the wrong place.
#
#   REPRO_TAG=name xcrun lldb -b -o "command script import Scripts/debug/standalone_driver.py"
import lldb, os, time

# Outputs (logs, PNGs, JSON) go outside the repo.
SCRATCH = os.environ.get("DRIVER_OUT", "/tmp/arcade-ruins-debug")
os.makedirs(SCRATCH, exist_ok=True)
APP = os.path.expanduser("~/Developer/SynthOne/DerivedData/Build/Products/Debug-maccatalyst/"
                         "ArcadeRuins.app/Contents/MacOS/ArcadeRuins")
TAG = os.environ.get("REPRO_TAG", "repro")
# The PresetCell action to fire: editPressed:, sharePressed:, favoritePressed:, duplicatePressed:
ACTION = os.environ.get("REPRO_ACTION", "editPressed:")

# The selected preset cell's star, after the action: which image it shows.
STAR_PROBE = """
id arApp = (id)[(id)NSClassFromString(@"UIApplication") sharedApplication];
id arWindow = (id)[(id)[(id)[(id)[arApp connectedScenes] anyObject] windows] firstObject];
id arViews = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:arWindow];
id arParts = (id)[(id)NSClassFromString(@"NSMutableArray") array];
while ((unsigned long)[arViews count] > 0) {
    id arView = (id)[arViews firstObject];
    (void)[arViews removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[@"SynthOneCore.PresetCell" isEqual:(id)[(id)[arView class] description]] && (BOOL)[arView isSelected]) {
        (void)[arParts addObject:(id)[(id)[arView presetNameLabel] text]];
        (void)[arParts addObject:(id)[(id)[(id)[arView favoriteButton] currentImage] description]];
    }
    (void)[arViews addObjectsFromArray:(id)[arView subviews]];
}
(id)[arParts componentsJoinedByString:@" | "]
"""
OUT = os.path.join(SCRATCH, TAG)
CI = None

WINDOW = """
id app = (id)[(id)NSClassFromString(@"UIApplication") sharedApplication];
id scene = (id)[(id)[app connectedScenes] anyObject];
id window = (id)[(id)[scene windows] firstObject];
"""

def find_controller(class_name):
    return """
id queue = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:(id)[window rootViewController]];
id found = nil;
while ((unsigned long)[queue count] > 0) {
    id vc = (id)[queue firstObject];
    (void)[queue removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[@"%s" isEqual:(id)[(id)[vc class] description]]) { found = vc; break; }
    (void)[queue addObjectsFromArray:(id)[vc childViewControllers]];
}
""" % class_name

OPEN_PRESETS = WINDOW + find_controller("SynthOneCore.HeaderViewController") + """
(id)[found performSelector:@selector(displayLabelTapped)];
(id)[(id)[found class] description]
"""

PRESS_EDIT = WINDOW + """
id queue = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:(id)[window rootViewController]];
id presets = nil; unsigned long instances = 0;
while ((unsigned long)[queue count] > 0) {
    id vc = (id)[queue firstObject];
    (void)[queue removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[@"SynthOneCore.PresetsViewController" isEqual:(id)[(id)[vc class] description]]) {
        instances++;
        if (presets == nil || (id)[(id)[vc view] window] != nil) { presets = vc; }
    }
    (void)[queue addObjectsFromArray:(id)[vc childViewControllers]];
}
id views = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:window];
id cell = nil;
while ((unsigned long)[views count] > 0) {
    id v = (id)[views firstObject];
    (void)[views removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[@"SynthOneCore.PresetCell" isEqual:(id)[(id)[v class] description]]) { cell = v; break; }
    (void)[views addObjectsFromArray:(id)[v subviews]];
}
id parts = (id)[(id)NSClassFromString(@"NSMutableArray") array];
if ((BOOL)[@"%(action)s" hasPrefix:@"Segue"]) {
    (void)[presets performSegueWithIdentifier:@"%(action)s" sender:presets];
    (void)[parts addObject:@"performed %(action)s"];
} else if (cell != nil) {
    (id)[cell performSelector:(SEL)NSSelectorFromString(@"%(action)s") withObject:nil];
    (void)[parts addObject:@"fired PresetCell %(action)s"];
} else {
    (void)[presets performSegueWithIdentifier:@"SegueToEdit" sender:presets];
    (void)[parts addObject:@"no PresetCell on screen; performed SegueToEdit on the live PresetsViewController"];
}
(void)[parts addObject:(id)[@"PresetsViewController instances: " stringByAppendingString:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithUnsignedLong:instances] description]]];
(void)[parts addObject:(presets != nil ? (id)[presets description] : @"no PresetsViewController")];
(void)[parts addObject:((id)[(id)[presets view] window] != nil ? @"presets view in window" : @"presets view NOT in window")];
(id)[parts componentsJoinedByString:@" | "]
"""

PRESENTED = WINDOW + """
id top = (id)[window rootViewController];
while ((id)[top presentedViewController] != nil) { top = (id)[top presentedViewController]; }
id parts = (id)[(id)NSClassFromString(@"NSMutableArray") array];
(void)[parts addObject:(id)[top description]];
(void)[parts addObject:((id)[(id)[top view] window] != nil ? @"its view is in a window" : @"its view is NOT in a window")];
(id)[parts componentsJoinedByString:@" | "]
"""

# Whatever is already presented at launch (a user would dismiss it before opening Presets).
DISMISS = WINDOW + """
id root = (id)[window rootViewController];
id top = (id)[root presentedViewController];
id parts = (id)[(id)NSClassFromString(@"NSMutableArray") array];
if (top == nil) {
    (void)[parts addObject:@"nothing presented"];
} else {
    (void)[parts addObject:(id)[top description]];
    (void)[parts addObject:((id)[top title] ?: @"(no title)")];
    if ((BOOL)[top respondsToSelector:@selector(message)]) { (void)[parts addObject:((id)[top message] ?: @"(no message)")]; }
    (void)[root dismissViewControllerAnimated:(BOOL)0 completion:nil];
    (void)[parts addObject:@"dismissed"];
}
(id)[parts componentsJoinedByString:@" | "]
"""

# After the fix: the bank list in the presented editor, as the running Mac-idiom app has it.
# Read-only. Save is never pressed — it would move a preset in the owner's own bank files.
BANK_PROBE = WINDOW + """
id arTop = (id)[window rootViewController];
while ((id)[arTop presentedViewController] != nil) { arTop = (id)[arTop presentedViewController]; }
id arViews = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:(id)[arTop view]];
id arTable = nil;
while ((unsigned long)[arViews count] > 0) {
    id arView = (id)[arViews firstObject];
    (void)[arViews removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[@"BankTableView" isEqual:(id)[arView accessibilityIdentifier]]) { arTable = arView; break; }
    (void)[arViews addObjectsFromArray:(id)[arView subviews]];
}
id arParts = (id)[(id)NSClassFromString(@"NSMutableArray") array];
if (arTable == nil) {
    (void)[arParts addObject:@"no BankTableView in the presented controller"];
} else {
    (void)[arParts addObject:(id)[(id)[arTable class] description]];
    (void)[arParts addObject:((id)[arTable window] != nil ? @"in window" : @"NOT in window")];
    (void)[arParts addObject:(id)[@"rows " stringByAppendingString:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithLong:(long)[(id)[arTable dataSource] tableView:arTable numberOfRowsInSection:(long)0]] description]]];
    id arSelected = (id)[arTable indexPathForSelectedRow];
    (void)[arParts addObject:(id)[@"selected row " stringByAppendingString:(arSelected != nil ? (id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithLong:(long)[arSelected row]] description] : @"none")]];
    id arCells = (id)[arTable visibleCells];
    for (unsigned long arIndex = 0; arIndex < (unsigned long)[arCells count]; arIndex++) {
        id arText = (id)[(id)[(id)[arCells objectAtIndex:arIndex] textLabel] text];
        (void)[arParts addObject:(id)[@"visible: " stringByAppendingString:(arText ?: @"(nil)")]];
    }
}
(id)[arParts componentsJoinedByString:@" | "]
"""

# The bank table's geometry as the running app lays it out: whether rows have the intended height.
GEOMETRY = WINDOW + """
typedef struct { double x, y, w, h; } ARRect;
typedef struct { double w, h; } ARSize;
typedef struct { double top, left, bottom, right; } ARInsets;
id arTop = (id)[window rootViewController];
while ((id)[arTop presentedViewController] != nil) { arTop = (id)[arTop presentedViewController]; }
id arViews = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:(id)[arTop view]];
id arTable = nil;
while ((unsigned long)[arViews count] > 0) {
    id arView = (id)[arViews firstObject];
    (void)[arViews removeObjectAtIndex:(unsigned long)0];
    if ((BOOL)[@"BankTableView" isEqual:(id)[arView accessibilityIdentifier]]) { arTable = arView; break; }
    (void)[arViews addObjectsFromArray:(id)[arView subviews]];
}
void *arSend = (void *)dlsym((void *)-2, "objc_msgSend");
id (*arRectString)(ARRect) = (id (*)(ARRect))dlsym((void *)-2, "NSStringFromCGRect");
id (*arSizeString)(ARSize) = (id (*)(ARSize))dlsym((void *)-2, "NSStringFromCGSize");
id (*arInsetString)(ARInsets) = (id (*)(ARInsets))dlsym((void *)-2, "NSStringFromUIEdgeInsets");
id arRow0 = (id)[(id)NSClassFromString(@"NSIndexPath") indexPathForRow:(long)0 inSection:(long)0];
id arRow1 = (id)[(id)NSClassFromString(@"NSIndexPath") indexPathForRow:(long)1 inSection:(long)0];
ARRect arTableBounds = ((ARRect (*)(id, SEL))arSend)(arTable, @selector(bounds));
id arParts = (id)[(id)NSClassFromString(@"NSMutableArray") array];
(void)[arParts addObject:(id)[@"frame " stringByAppendingString:arRectString(((ARRect (*)(id, SEL))arSend)(arTable, @selector(frame)))]];
(void)[arParts addObject:(id)[@"bounds " stringByAppendingString:arRectString(arTableBounds)]];
(void)[arParts addObject:(id)[@"in window " stringByAppendingString:arRectString(((ARRect (*)(id, SEL, ARRect, id))arSend)(arTable, @selector(convertRect:toView:), arTableBounds, nil))]];
(void)[arParts addObject:(id)[@"contentSize " stringByAppendingString:arSizeString(((ARSize (*)(id, SEL))arSend)(arTable, @selector(contentSize)))]];
(void)[arParts addObject:(id)[@"contentInset " stringByAppendingString:arInsetString(((ARInsets (*)(id, SEL))arSend)(arTable, @selector(contentInset)))]];
(void)[arParts addObject:(id)[@"contentOffset " stringByAppendingString:arSizeString(((ARSize (*)(id, SEL))arSend)(arTable, @selector(contentOffset)))]];
(void)[arParts addObject:(id)[@"adjustedContentInset " stringByAppendingString:arInsetString(((ARInsets (*)(id, SEL))arSend)(arTable, @selector(adjustedContentInset)))]];
(void)[arParts addObject:(id)[@"rowHeight " stringByAppendingString:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithDouble:((double (*)(id, SEL))arSend)(arTable, @selector(rowHeight))] description]]];
(void)[arParts addObject:(id)[@"row0 " stringByAppendingString:arRectString(((ARRect (*)(id, SEL, id))arSend)(arTable, @selector(rectForRowAtIndexPath:), arRow0))]];
(void)[arParts addObject:(id)[@"row1 " stringByAppendingString:arRectString(((ARRect (*)(id, SEL, id))arSend)(arTable, @selector(rectForRowAtIndexPath:), arRow1))]];
(void)[arParts addObject:(id)[@"clipsToBounds " stringByAppendingString:((BOOL)[arTable clipsToBounds] ? @"yes" : @"no")]];
(id)[arParts componentsJoinedByString:@" | "]
"""

# A PNG of the window with the editor open, for the owner's visual sign-off. Struct arguments go
# through a typed objc_msgSend, since lldb has no prototypes here. Every local carries an `ar`
# prefix: short names like `table`, `S` or `context` collide with symbols in loaded images.
RENDER = WINDOW + """
typedef struct { double x, y, w, h; } ARRect;
typedef struct { double w, h; } ARSize;
void *arSend = (void *)dlsym((void *)-2, "objc_msgSend");
ARRect arBounds = ((ARRect (*)(id, SEL))arSend)(window, @selector(bounds));
id arRenderer = ((id (*)(id, SEL, ARSize))arSend)((id)[(id)NSClassFromString(@"UIGraphicsImageRenderer") alloc], @selector(initWithSize:), (ARSize){arBounds.w, arBounds.h});
id arLayer = (id)[window layer];
id arImage = (id)[arRenderer imageWithActions:^(id arContext) { (void)[arLayer renderInContext:(void *)[arContext CGContext]]; }];
id arPNG = ((id (*)(id))dlsym((void *)-2, "UIImagePNGRepresentation"))(arImage);
(void)[arPNG writeToFile:@"%s" atomically:(BOOL)1];
(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithUnsignedLong:(unsigned long)[arPNG length]] description]
"""

def log(msg):
    print("[repro] " + msg, flush=True)

def pump(listener, process, seconds, until=None):
    end = time.time() + seconds
    ev = lldb.SBEvent()
    while time.time() < end:
        if until and process.GetState() in until:
            return True
        listener.WaitForEvent(1, ev)
    return bool(until) and process.GetState() in until

def stop(listener, process):
    process.Stop()
    return pump(listener, process, 15, until=[lldb.eStateStopped])

def resume(listener, process):
    process.Continue()
    pump(listener, process, 3, until=[lldb.eStateRunning])

def command(ci, text):
    ret = lldb.SBCommandReturnObject()
    ci.HandleCommand(text, ret)
    return (ret.GetOutput() or "") + (ret.GetError() or "")

def evaluate(process, expr):
    thread = process.GetThreadAtIndex(0)
    process.SetSelectedThread(thread)
    options = lldb.SBExpressionOptions()
    options.SetLanguage(lldb.eLanguageTypeObjC_plus_plus)
    options.SetTimeoutInMicroSeconds(60 * 1000 * 1000)
    options.SetTryAllThreads(False)
    options.SetIgnoreBreakpoints(True)
    options.SetUnwindOnError(False)   # on a trap, keep the frames so the backtrace can be read
    value = thread.GetFrameAtIndex(0).EvaluateExpression(expr, options)
    if value.GetError().Fail():
        message = "ERROR " + value.GetError().GetCString()
        if "interrupted" in message and CI is not None:
            message += "\n" + command(CI, "thread backtrace -c 30")
            thread.UnwindInnermostExpression()
        return message
    return value.GetObjectDescription() or value.GetValue() or value.GetSummary() or "(no value)"

def __lldb_init_module(debugger, internal_dict):
    global CI
    debugger.SetAsync(True)
    CI = ci = debugger.GetCommandInterpreter()
    listener = debugger.GetListener()
    target = debugger.CreateTarget(APP)
    info = lldb.SBLaunchInfo([])
    info.AddOpenFileAction(1, OUT + ".stdout", False, True)
    info.AddOpenFileAction(2, OUT + ".stderr", False, True)
    error = lldb.SBError()
    process = target.Launch(info, error)
    if error.Fail():
        log("launch failed: " + error.GetCString()); return
    log("launched pid %d from %s" % (process.GetProcessID(), APP))
    pump(listener, process, 12)

    if not stop(listener, process):
        log("could not stop the process"); process.Kill(); return
    log("trait collection -> " + evaluate(process, WINDOW + "(id)[(id)[scene traitCollection] description]"))
    log("already presented -> " + evaluate(process, DISMISS))
    resume(listener, process)
    pump(listener, process, 2)
    stop(listener, process)
    if os.environ.get("REPRO_RENDER_ONLY"):
        log("render bytes -> " + evaluate(process, RENDER % (OUT + ".png")))
        process.Kill(); log("killed"); return
    log("open presets -> " + evaluate(process, OPEN_PRESETS))
    resume(listener, process)
    pump(listener, process, 3)

    stop(listener, process)
    target.BreakpointCreateByName("objc_exception_throw")
    log("%s -> %s" % (ACTION, evaluate(process, PRESS_EDIT % {"action": ACTION})))
    resume(listener, process)

    stopped = pump(listener, process, 20, until=[lldb.eStateStopped, lldb.eStateExited, lldb.eStateCrashed])
    if not stopped:
        log("NO EXCEPTION within 20 s")
        if stop(listener, process):
            log("topmost presented -> " + evaluate(process, PRESENTED))
            log("selected cell star -> " + evaluate(process, STAR_PROBE))
            log("bank list -> " + evaluate(process, BANK_PROBE))
            log("geometry -> " + evaluate(process, GEOMETRY))
            log("render bytes -> " + evaluate(process, RENDER % (OUT + ".png")))
        process.Kill(); log("killed"); return

    for thread in process:
        if thread.GetStopReason() in (lldb.eStopReasonBreakpoint, lldb.eStopReasonException):
            process.SetSelectedThread(thread)
            log("stopped: thread #%d %s" % (thread.GetIndexID(), thread.GetStopDescription(200)))
            log("name:   " + command(ci, "po (id)[(id)$x0 name]").strip())
            log("reason: " + command(ci, "po (id)[(id)$x0 reason]").strip())
            log(command(ci, "thread backtrace -c 24"))
            break
    process.Kill()
    log("killed")
