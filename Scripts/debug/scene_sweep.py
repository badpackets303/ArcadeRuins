# lldb driver (Scripts/debug/README.md): the Mac-idiom sweep, run in the real Optimize-for-Mac standalone (DerivedData
# build, NOT /Applications).
#
# Every scene of every compiled storyboard in SynthOneCore.framework is instantiated by the
# identifiers the storyboard itself records (Info.plist -> UIViewControllerIdentifiersToNibNames),
# its view loaded, added *hidden* to the key window, laid out, and removed. UIKit's Mac-idiom
# thrower is breakpointed: each hit logs the view class and UIKit's own reason and then
# `thread return`s, so one offender does not end the walk. Which views are refused is UIKit's
# answer at runtime, not a list of class names.
#
# lldb has no prototypes for these messages: never call a variadic method (stringWithFormat:)
# from an expression here — its arguments are passed in the wrong place.
#
#   SWEEP_TAG=name xcrun lldb -b -o "command script import Scripts/debug/scene_sweep.py"
import lldb, os, time, json, plistlib, glob

# Outputs (logs, PNGs, JSON) go outside the repo.
SCRATCH = os.environ.get("DRIVER_OUT", "/tmp/arcade-ruins-debug")
os.makedirs(SCRATCH, exist_ok=True)
PRODUCTS = os.path.expanduser("~/Developer/SynthOne/DerivedData/Build/Products/Debug-maccatalyst")
APP = os.path.join(PRODUCTS, "ArcadeRuins.app/Contents/MacOS/ArcadeRuins")
STORYBOARDS = os.path.join(PRODUCTS, "SynthOneCore.framework/Versions/A/Resources/Base.lproj")
TAG = os.environ.get("SWEEP_TAG", "sweep")
OUT = os.path.join(SCRATCH, TAG)
HITS = []
CURRENT = {"scene": "(before walk)"}

# Two scenes are Manager itself. A second Manager re-runs MIDI and engine setup; the live root
# Manager is already in the window, and got there without an exception.
SKIP = {("Main", "ParentViewController"), ("Main", "iPhoneParentVC")}

WINDOW = """
id app = (id)[(id)NSClassFromString(@"UIApplication") sharedApplication];
id scene = (id)[(id)[app connectedScenes] anyObject];
id window = (id)[(id)[scene windows] firstObject];
"""

WALK_SCENE = WINDOW + """
id bundle = (id)[(id)NSClassFromString(@"NSBundle") bundleForClass:(Class)NSClassFromString(@"SynthOneCore.Manager")];
id sb = (id)[(id)NSClassFromString(@"UIStoryboard") storyboardWithName:@"%(storyboard)s" bundle:bundle];
id vc = (id)[sb instantiateViewControllerWithIdentifier:@"%(identifier)s"];
id root = (id)[vc view];
(void)[root setHidden:(BOOL)1];
(void)[window addSubview:root];
(void)[root layoutIfNeeded];
id classes = (id)[(id)NSClassFromString(@"NSMutableSet") set];
id queue = (id)[(id)NSClassFromString(@"NSMutableArray") arrayWithObject:root];
unsigned long count = 0;
while ((unsigned long)[queue count] > 0) {
    id v = (id)[queue firstObject];
    (void)[queue removeObjectAtIndex:(unsigned long)0];
    count++;
    (void)[classes addObject:(id)[(id)[v class] description]];
    (void)[queue addObjectsFromArray:(id)[v subviews]];
}
(void)[root removeFromSuperview];
id parts = (id)[(id)NSClassFromString(@"NSMutableArray") array];
(void)[parts addObject:(id)[(id)[vc class] description]];
(void)[parts addObject:(id)[(id)[(id)NSClassFromString(@"NSNumber") numberWithUnsignedLong:count] description]];
(void)[parts addObject:(id)[(id)[(id)[classes allObjects] sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@","]];
(id)[parts componentsJoinedByString:@" | "]
"""

def log(msg):
    print("[sweep] " + msg, flush=True)

def pump(listener, process, seconds, until=None):
    end = time.time() + seconds
    ev = lldb.SBEvent()
    while time.time() < end:
        if until and process.GetState() in until:
            return True
        listener.WaitForEvent(1, ev)
    return bool(until) and process.GetState() in until

CI = None

def command(text):
    ret = lldb.SBCommandReturnObject()
    CI.HandleCommand(text, ret)
    return ((ret.GetOutput() or "") + (ret.GetError() or "")).strip()

# A user breakpoint callback does not run inside an expression: lldb's own ObjC exception
# breakpoint interrupts the expression first. So the exception is read where it stops —
# objc_exception_throw, with the NSException in x0 — and then the expression is unwound.
def evaluate(process, expr):
    thread = process.GetThreadAtIndex(0)
    process.SetSelectedThread(thread)
    options = lldb.SBExpressionOptions()
    options.SetLanguage(lldb.eLanguageTypeObjC_plus_plus)
    options.SetTimeoutInMicroSeconds(60 * 1000 * 1000)
    options.SetTryAllThreads(False)
    options.SetIgnoreBreakpoints(True)
    options.SetUnwindOnError(False)
    value = thread.GetFrameAtIndex(0).EvaluateExpression(expr, options)
    if value.GetError().Fail():
        message = "ERROR " + value.GetError().GetCString().strip()
        if "interrupted" in message:
            stopped = process.GetSelectedThread()
            frames = [str(stopped.GetFrameAtIndex(i).GetFunctionName())
                      for i in range(min(8, stopped.GetNumFrames()))]
            hit = {"scene": CURRENT["scene"], "name": command("po (id)[(id)$x0 name]"),
                   "reason": command("po (id)[(id)$x0 reason]"), "frames": frames}
            HITS.append(hit)
            message += "\n    EXCEPTION " + json.dumps(hit)
            stopped.UnwindInnermostExpression()
        return message
    return value.GetObjectDescription() or value.GetValue() or value.GetSummary() or "(no value)"

def on_unsupported(frame, bp_loc, internal_dict):
    options = lldb.SBExpressionOptions()
    options.SetLanguage(lldb.eLanguageTypeObjC_plus_plus)
    options.SetIgnoreBreakpoints(True)
    options.SetTimeoutInMicroSeconds(10 * 1000 * 1000)
    view = frame.EvaluateExpression("(id)[(id)[(id)$x0 class] description]", options).GetObjectDescription()
    reason = frame.EvaluateExpression("(id)$x2", options).GetObjectDescription()
    thread = frame.GetThread()
    callers = [thread.GetFrameAtIndex(i).GetFunctionName() for i in range(1, min(6, thread.GetNumFrames()))]
    hit = {"scene": CURRENT["scene"], "view": view, "reason": reason, "callers": callers}
    HITS.append(hit)
    log("HIT " + json.dumps(hit))
    thread.ReturnFromFrame(frame, lldb.SBValue())   # skip the throw; keep walking
    return False

def scenes_on_disk():
    scenes = []
    for path in sorted(glob.glob(os.path.join(STORYBOARDS, "*.storyboardc"))):
        with open(os.path.join(path, "Info.plist"), "rb") as f:
            info = plistlib.load(f)
        name = os.path.splitext(os.path.basename(path))[0]
        scenes += [(name, identifier) for identifier in info["UIViewControllerIdentifiersToNibNames"]]
    # iPhone scenes last: neither product loads them (Conductor.device is never .phone).
    return sorted(scenes, key=lambda s: (s[1].startswith("iPhone"), s))

def __lldb_init_module(debugger, internal_dict):
    scenes = scenes_on_disk()
    log("%d scenes in %d storyboards, from %s" % (len(scenes), len({s[0] for s in scenes}), STORYBOARDS))

    global CI
    debugger.SetAsync(True)
    CI = debugger.GetCommandInterpreter()
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
    process.Stop()
    if not pump(listener, process, 15, until=[lldb.eStateStopped]):
        log("could not stop"); process.Kill(); return

    # UIKit's own record of which classes carry Mac-idiom restrictions — context, not the test.
    found = target.FindGlobalFunctions("UICatalystMacIdiomUnsupported_Internal", 0, lldb.eMatchTypeRegex)
    names = sorted({found.GetContextAtIndex(i).GetSymbol().GetName() for i in range(found.GetSize())})
    with open(OUT + ".categories.txt", "w") as f:
        f.write("\n".join(names) + "\n")
    log("UIKit symbols in UICatalystMacIdiomUnsupported_Internal categories: %d (written to %s.categories.txt)" % (len(names), TAG))

    log("trait collection: " + evaluate(process, WINDOW + "(id)[(id)[scene traitCollection] description]"))

    walked = 0
    for storyboard, identifier in scenes:
        if (storyboard, identifier) in SKIP:
            log("skip %s/%s (Manager; already live in the window)" % (storyboard, identifier)); continue
        CURRENT["scene"] = "%s/%s" % (storyboard, identifier)
        result = evaluate(process, WALK_SCENE % {"storyboard": storyboard, "identifier": identifier})
        log("%s -> %s" % (CURRENT["scene"], result))
        if process.GetState() != lldb.eStateStopped:
            log("process state changed to %d; stopping walk" % process.GetState()); break
        walked += 1

    log("walked %d scenes; %d Mac-idiom hits" % (walked, len(HITS)))
    with open(OUT + ".hits.json", "w") as f:
        json.dump(HITS, f, indent=2)
    process.Kill()
    log("killed")
