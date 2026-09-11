// ADR-034. Injected into the DerivedData standalone with DYLD_INSERT_LIBRARIES. Measures every text input's
// legibility in the running Mac-idiom app: resolved colours (analytic) and the rendered glyph pixels
// (a render with the text against a render without it). Walks the live click paths, then every
// storyboard scene, first in the system appearance and then with the key window overridden to Light.
// Writes log.txt and PNGs to $S1WALK_OUT, then quits the app. Not part of any target.
//
// The app rewrites settings.json and tunings_v1.json in ~/Library/Application Support/SynthOne at
// launch (launch count, MIDI sources). Copy them first. Put them back afterwards only if nothing
// else has launched the app in the meantime; otherwise the copy overwrites that launch's version.
//
//   SDK=$(xcrun --sdk macosx --show-sdk-path)
//   xcrun clang -target arm64-apple-ios14.0-macabi -isysroot "$SDK" \
//       -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" \
//       -F "$SDK/System/iOSSupport/System/Library/Frameworks" -L "$SDK/System/iOSSupport/usr/lib" \
//       -fobjc-arc -dynamiclib -framework UIKit -framework Foundation -framework CoreGraphics \
//       -Wno-arc-performSelector-leaks -Wno-implicit-enum-enum-cast \
//       -o /tmp/walker.dylib Scripts/debug/appearance_walker.m
//   open -W -g -n --env DYLD_INSERT_LIBRARIES=/tmp/walker.dylib --env S1WALK_OUT=/tmp/walk \
//       DerivedData/Build/Products/Debug-maccatalyst/ArcadeRuins.app
//
// This works because the Debug build has no hardened runtime (codesign flags=0x2, adhoc). `open -g`
// keeps the app from taking focus, and the `timeout` command does not exist on this Mac.
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

typedef struct { CGFloat r, g, b, a; } RGBA;

static NSString *gOut;
static NSString *gMode = @"?";
static NSFileHandle *gLogHandle;
static NSMutableArray *gSteps;

static void Log(NSString *line) {
    NSData *d = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    [gLogHandle writeData:d];
    [gLogHandle synchronizeFile];
}

// MARK: colour

static RGBA ToRGBA(UIColor *c, UITraitCollection *t) {
    RGBA o = {0, 0, 0, 0};
    if (!c) return o;
    UIColor *res = t ? [c resolvedColorWithTraitCollection:t] : c;
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGColorRef m = CGColorCreateCopyByMatchingToColorSpace(srgb, kCGRenderingIntentDefault, res.CGColor, NULL);
    CGColorSpaceRelease(srgb);
    if (!m) { o.a = -1; return o; }   // pattern colour
    const CGFloat *comp = CGColorGetComponents(m);
    if (CGColorGetNumberOfComponents(m) >= 4) { o.r = comp[0]; o.g = comp[1]; o.b = comp[2]; o.a = comp[3]; }
    CGColorRelease(m);
    return o;
}

static RGBA Over(RGBA top, RGBA bottom) {
    RGBA o;
    o.a = top.a + bottom.a * (1 - top.a);
    if (o.a <= 0) { o.r = o.g = o.b = 0; return o; }
    o.r = (top.r * top.a + bottom.r * bottom.a * (1 - top.a)) / o.a;
    o.g = (top.g * top.a + bottom.g * bottom.a * (1 - top.a)) / o.a;
    o.b = (top.b * top.a + bottom.b * bottom.a * (1 - top.a)) / o.a;
    return o;
}

static CGFloat Lin(CGFloat c) { c = MAX(0, MIN(1, c)); return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4); }
static CGFloat Lum(RGBA x) { return 0.2126 * Lin(x.r) + 0.7152 * Lin(x.g) + 0.0722 * Lin(x.b); }
static CGFloat Contrast(RGBA a, RGBA b) {
    CGFloat l1 = Lum(a), l2 = Lum(b);
    return (MAX(l1, l2) + 0.05) / (MIN(l1, l2) + 0.05);
}
static NSString *Hex(RGBA x) {
    if (x.a < 0) return @"pattern";
    return [NSString stringWithFormat:@"#%02X%02X%02X/%.2f", (int)lround(MAX(0, MIN(1, x.r)) * 255),
            (int)lround(MAX(0, MIN(1, x.g)) * 255), (int)lround(MAX(0, MIN(1, x.b)) * 255), x.a];
}

/// What is painted behind `v`: its superviews' backgrounds composited, over the window's.
static RGBA Behind(UIView *v) {
    NSMutableArray<UIView *> *chain = [NSMutableArray array];
    for (UIView *s = v.superview; s; s = s.superview) {
        [chain addObject:s];
        if (ToRGBA(s.backgroundColor, s.traitCollection).a >= 0.999) break;
    }
    RGBA acc = ToRGBA(UIColor.systemBackgroundColor, v.traitCollection);   // base if nothing is opaque
    for (UIView *s in chain.reverseObjectEnumerator) {
        RGBA c = ToRGBA(s.backgroundColor, s.traitCollection);
        if (c.a > 0) acc = Over(c, acc);
    }
    acc.a = 1;
    return acc;
}

// MARK: rendering

static NSMutableData *Render(UIView *v, RGBA base, BOOL hierarchy, size_t *w, size_t *h) {
    CGFloat scale = 2;
    *w = (size_t)ceil(v.bounds.size.width * scale);
    *h = (size_t)ceil(v.bounds.size.height * scale);
    if (*w == 0 || *h == 0) return nil;
    NSMutableData *px = [NSMutableData dataWithLength:*w * *h * 4];
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef ctx = CGBitmapContextCreate(px.mutableBytes, *w, *h, 8, *w * 4, srgb, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(srgb);
    CGContextSetRGBFillColor(ctx, base.r, base.g, base.b, 1);
    CGContextFillRect(ctx, CGRectMake(0, 0, *w, *h));
    CGContextTranslateCTM(ctx, 0, *h);
    CGContextScaleCTM(ctx, scale, -scale);
    if (hierarchy) {
        UIGraphicsPushContext(ctx);
        [v drawViewHierarchyInRect:v.bounds afterScreenUpdates:YES];
        UIGraphicsPopContext();
    } else {
        [v.layer renderInContext:ctx];
    }
    CGContextRelease(ctx);
    return px;
}

static void SavePNG(NSData *px, size_t w, size_t h, NSString *name) {
    CGColorSpaceRef srgb = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGDataProviderRef p = CGDataProviderCreateWithCFData((__bridge CFDataRef)px);
    CGImageRef img = CGImageCreate(w, h, 8, 32, w * 4, srgb, kCGImageAlphaPremultipliedLast, p, NULL, NO, kCGRenderingIntentDefault);
    NSData *png = UIImagePNGRepresentation([UIImage imageWithCGImage:img]);
    [png writeToFile:[gOut stringByAppendingPathComponent:name] atomically:YES];
    CGImageRelease(img); CGDataProviderRelease(p); CGColorSpaceRelease(srgb);
}

static NSString *Safe(NSString *s) {
    NSCharacterSet *bad = [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    return [[s componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
}

// MARK: measuring one input

static BOOL IsInput(UIView *v) {
    return [v isKindOfClass:UITextField.class] || [v isKindOfClass:UITextView.class];
}

static BOOL HiddenInScene(UIView *v, UIView *sceneRoot) {
    for (UIView *s = v; s && s != sceneRoot.superview; s = s.superview) {
        if (s.hidden || s.alpha < 0.01) return YES;
    }
    return NO;
}

static void Measure(UIView *v, NSString *scene, UIView *sceneRoot, BOOL live) {
    UITraitCollection *t = v.traitCollection;
    NSString *style = t.userInterfaceStyle == UIUserInterfaceStyleDark ? @"dark" : (t.userInterfaceStyle == UIUserInterfaceStyleLight ? @"light" : @"unspec");
    RGBA behind = Behind(v);
    RGBA ownBg = ToRGBA(v.backgroundColor, t);
    RGBA fieldBg = ownBg.a > 0 ? Over(ownBg, behind) : behind;
    fieldBg.a = 1;

    UIColor *textColor = [(id)v textColor];
    RGBA fg = ToRGBA(textColor, t);
    NSAttributedString *as = [(id)v attributedText];
    NSMutableOrderedSet *attrFg = [NSMutableOrderedSet orderedSet];
    __block BOOL missingAttr = NO;
    if (as.length) {
        [as enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, as.length) options:0
                    usingBlock:^(id value, NSRange range, BOOL *stop) {
            if (value) [attrFg addObject:Hex(ToRGBA(value, t))]; else missingAttr = YES;
        }];
    }
    RGBA fgOver = Over(fg, fieldBg);
    CGFloat analytic = textColor ? Contrast(fgOver, fieldBg) : -1;

    // Pixels: with text against without.
    BOOL isField = [v isKindOfClass:UITextField.class];
    NSString *origText = [(id)v text];
    NSAttributedString *origAttr = [as copy];
    NSString *probe = origText.length ? nil : @"Probe Name Ag";
    if (probe) [(id)v setText:probe];
    [v layoutIfNeeded];
    size_t w, h, w2, h2;
    NSMutableData *with = Render(v, behind, live, &w, &h);
    [(id)v setText:@""];
    [v layoutIfNeeded];
    NSMutableData *without = Render(v, behind, live, &w2, &h2);
    if (isField) [(id)v setText:origText]; else [(id)v setAttributedText:origAttr];
    [v layoutIfNeeded];

    NSUInteger changed = 0; CGFloat maxC = 0; NSMutableArray *cs = [NSMutableArray array];
    RGBA inkMax = {0}, bgAtMax = {0};
    if (with && without && w == w2 && h == h2) {
        const uint8_t *a = with.bytes, *b = without.bytes;
        for (size_t i = 0; i < w * h; i++) {
            const uint8_t *pa = a + i * 4, *pb = b + i * 4;
            int d = MAX(abs(pa[0] - pb[0]), MAX(abs(pa[1] - pb[1]), abs(pa[2] - pb[2])));
            if (d <= 8) continue;
            changed++;
            RGBA ca = {pa[0] / 255.0, pa[1] / 255.0, pa[2] / 255.0, 1}, cb = {pb[0] / 255.0, pb[1] / 255.0, pb[2] / 255.0, 1};
            CGFloat c = Contrast(ca, cb);
            [cs addObject:@(c)];
            if (c > maxC) { maxC = c; inkMax = ca; bgAtMax = cb; }
        }
    }
    [cs sortUsingSelector:@selector(compare:)];
    CGFloat p90 = cs.count ? [cs[(NSUInteger)(cs.count * 0.9)] doubleValue] : 0;

    NSString *base = Safe([NSString stringWithFormat:@"%@_%@_%@", gMode, scene, NSStringFromClass(v.class)]);
    if (with) SavePNG(with, w, h, [base stringByAppendingString:@".png"]);

    NSString *ident = v.accessibilityIdentifier ?: @"";
    Log([NSString stringWithFormat:
         @"INPUT\tmode=%@\tscene=%@\tclass=%@\tid=%@\tframe=%@\tstyle=%@\thiddenInScene=%d\teditable=%d\tfirstResponder=%d\t"
         @"textColor=%@ (%@)\tattrFg=%@%@\townBg=%@\tbehind=%@\tfieldBg=%@\tanalyticContrast=%.2f\t"
         @"pixelsChanged=%lu\tinkContrastMax=%.2f\tinkContrastP90=%.2f\tink=%@\tinkBg=%@\tprobe=%d\tpng=%@",
         gMode, scene, NSStringFromClass(v.class), ident, NSStringFromCGRect(v.frame), style,
         HiddenInScene(v, sceneRoot), isField ? [(UITextField *)v isEnabled] : [(UITextView *)v isEditable], v.isFirstResponder,
         Hex(fg), textColor ? [[textColor description] substringToIndex:MIN(60, textColor.description.length)] : @"nil",
         [attrFg.array componentsJoinedByString:@","], missingAttr ? @"+absent" : @"",
         Hex(ownBg), Hex(behind), Hex(fieldBg), analytic,
         (unsigned long)changed, maxC, p90, Hex(inkMax), Hex(bgAtMax), probe != nil, base]);
}

static void MeasureAll(UIView *root, NSString *scene, BOOL live) {
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    NSMutableArray *found = [NSMutableArray array];
    while (stack.count) {
        UIView *v = stack.lastObject; [stack removeLastObject];
        if (IsInput(v)) [found addObject:v];
        [stack addObjectsFromArray:v.subviews];
    }
    for (UIView *v in found) {
        @try { Measure(v, scene, root, live); }
        @catch (NSException *e) { Log([NSString stringWithFormat:@"EXC measuring %@ in %@: %@", v.class, scene, e.reason]); }
    }
    if (!found.count) Log([NSString stringWithFormat:@"NOINPUT\tmode=%@\tscene=%@", gMode, scene]);
}

// MARK: finding things

static UIWindow *KeyWindow(void) {
    UIWindow *fallback = nil;
    for (UIScene *sc in UIApplication.sharedApplication.connectedScenes) {
        if (![sc isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *w in ((UIWindowScene *)sc).windows) {
            if (w.isKeyWindow) return w;
            if (w.rootViewController && !fallback) fallback = w;
        }
    }
    return fallback;
}

static UIViewController *FindVC(UIViewController *vc, Class cls) {
    if (!vc) return nil;
    if ([vc isKindOfClass:cls]) return vc;
    for (UIViewController *c in vc.childViewControllers) {
        UIViewController *f = FindVC(c, cls);
        if (f) return f;
    }
    return nil;
}

static UIView *FindVisibleView(UIView *v, Class cls) {
    if ([v isKindOfClass:cls] && v.window && !v.hidden) return v;
    for (UIView *s in v.subviews) {
        if (s.hidden) continue;
        UIView *f = FindVisibleView(s, cls);
        if (f) return f;
    }
    return nil;
}

static UIViewController *Manager(void) { return FindVC(KeyWindow().rootViewController, NSClassFromString(@"SynthOneCore.Manager")); }

static void CollectVCs(UIViewController *vc, Class cls, NSMutableArray *out) {
    if (!vc) return;
    if ([vc isKindOfClass:cls]) [out addObject:vc];
    for (UIViewController *c in vc.childViewControllers) CollectVCs(c, cls, out);
}

/// The Presets panel that is on screen, if any; otherwise the Manager's first.
static UIViewController *Presets(void) {
    NSMutableArray *all = [NSMutableArray array];
    CollectVCs(Manager(), NSClassFromString(@"SynthOneCore.PresetsViewController"), all);
    for (UIViewController *vc in all) if (vc.isViewLoaded && vc.view.window) return vc;
    return all.firstObject;
}

static UIViewController *TopPresented(void) {
    UIViewController *vc = KeyWindow().rootViewController, *top = nil;
    while (vc.presentedViewController) { top = vc.presentedViewController; vc = top; }
    return top;
}

static void DismissAll(void) {
    UIViewController *root = KeyWindow().rootViewController;
    if (root.presentedViewController) {
        Log([NSString stringWithFormat:@"DISMISS\t%@", NSStringFromClass(TopPresented().class)]);
        [root dismissViewControllerAnimated:NO completion:nil];
    }
}

static void Step(void (^b)(void)) { [gSteps addObject:[b copy]]; }

static void Next(void) {
    if (!gSteps.count) return;
    void (^b)(void) = gSteps.firstObject;
    [gSteps removeObjectAtIndex:0];
    @try { b(); } @catch (NSException *e) { Log([NSString stringWithFormat:@"EXC step (%@): %@ %@", gMode, e.name, e.reason]); }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ Next(); });
}

static void MeasurePresented(NSString *label) {
    UIViewController *p = TopPresented();
    Log([NSString stringWithFormat:@"PRESENTED\tmode=%@\t%@\t%@\twindow=%@", gMode, label, p ? NSStringFromClass(p.class) : @"nil",
         p.view.window ? NSStringFromClass(p.view.window.class) : @"none"]);
    if (!p) return;
    MeasureAll(p.view, label, YES);
    size_t w, h;
    NSMutableData *px = Render(p.view, Behind(p.view), YES, &w, &h);
    if (px) SavePNG(px, w, h, [Safe([NSString stringWithFormat:@"%@_%@_whole", gMode, label]) stringByAppendingString:@".png"]);
}

static UITextField *PresentedField(void) {
    UIViewController *p = TopPresented();
    return (UITextField *)FindVisibleView(p.view, UITextField.class);
}

static void AddModeSteps(NSString *mode, UIUserInterfaceStyle override) {
    Step(^{
        gMode = mode;
        UIWindow *win = KeyWindow();
        win.overrideUserInterfaceStyle = override;
        Log([NSString stringWithFormat:@"MODE\t%@\twindowOverride=%ld\twindowStyle=%ld\tidiom=%ld\tsystemStyle(screen)=%ld",
             mode, (long)override, (long)win.traitCollection.userInterfaceStyle,
             (long)win.traitCollection.userInterfaceIdiom, (long)win.windowScene.screen.traitCollection.userInterfaceStyle]);
        DismissAll();
    });
    Step(^{
        UIViewController *presets = Presets();
        if (presets.view.window) { Log(@"PRESETS already displayed"); return; }
        UIViewController *header = FindVC(Manager(), NSClassFromString(@"SynthOneCore.HeaderViewController"));
        Log([NSString stringWithFormat:@"TAP displayLabelTapped on %@", header]);
        [header performSelector:@selector(displayLabelTapped)];
    });
    // Preset editor, along the click path: a preset cell's Edit button.
    Step(^{
        UIView *cell = FindVisibleView(KeyWindow(), NSClassFromString(@"SynthOneCore.PresetCell"));
        Log([NSString stringWithFormat:@"TAP PresetCell editPressed: %@ (presets in window: %d)", cell ? @"found" : @"NOT FOUND",
             Presets().view.window != nil]);
        [cell performSelector:@selector(editPressed:) withObject:nil];
    });
    Step(^{
        if (!TopPresented()) { Log(@"SEGUE SegueToEdit (cell path presented nothing)"); [Presets() performSegueWithIdentifier:@"SegueToEdit" sender:Presets()]; }
    });
    Step(^{ MeasurePresented(@"live_PresetEditor"); });
    Step(^{ UITextField *f = PresentedField(); Log([NSString stringWithFormat:@"FOCUS %d", [f becomeFirstResponder]]); });
    Step(^{ MeasurePresented(@"live_PresetEditor_editing"); [PresentedField() resignFirstResponder]; });
    Step(^{ DismissAll(); });
    // Bank editor, along the click path: a category cell's Edit button.
    Step(^{
        UIView *cell = FindVisibleView(Presets().view, NSClassFromString(@"SynthOneCore.CategoryCell"));
        Log([NSString stringWithFormat:@"TAP CategoryCell editPressed: %@", cell ? @"found" : @"NOT FOUND"]);
        [cell performSelector:@selector(editPressed:) withObject:nil];
    });
    Step(^{
        if (!TopPresented()) { Log(@"SEGUE SegueToBankEdit (cell path presented nothing)"); [Presets() performSegueWithIdentifier:@"SegueToBankEdit" sender:Presets()]; }
    });
    Step(^{ MeasurePresented(@"live_BankEditor"); });
    Step(^{ UITextField *f = PresentedField(); Log([NSString stringWithFormat:@"FOCUS %d", [f becomeFirstResponder]]); });
    Step(^{ MeasurePresented(@"live_BankEditor_editing"); [PresentedField() resignFirstResponder]; });
    Step(^{ DismissAll(); });
    // Search: what searchtoolButton's callback does.
    Step(^{ Log(@"SEGUE SegueToSearch"); [Presets() performSegueWithIdentifier:@"SegueToSearch" sender:nil]; });
    Step(^{ MeasurePresented(@"live_Search"); });
    Step(^{ DismissAll(); });
    // The live Presets panel (its description text view).
    Step(^{ MeasureAll(Presets().view, @"live_PresetsPanel", YES); });
    // Every storyboard scene, as ADR-033's sweep: loaded, added to the window, laid out.
    Step(^{
        UIWindow *win = KeyWindow();
        NSBundle *fw = [NSBundle bundleForClass:NSClassFromString(@"SynthOneCore.Manager")];
        NSArray *paths = [[fw pathsForResourcesOfType:@"storyboardc" inDirectory:nil]
                          sortedArrayUsingSelector:@selector(compare:)];
        NSUInteger scenes = 0;
        for (NSString *path in paths) {
            NSString *name = path.lastPathComponent.stringByDeletingPathExtension;
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathComponent:@"Info.plist"]];
            NSDictionary *ids = info[@"UIViewControllerIdentifiersToNibNames"];
            UIStoryboard *sb = [UIStoryboard storyboardWithName:name bundle:fw];
            for (NSString *ident in [ids.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
                if ([name isEqualToString:@"Main"] && ([ident isEqualToString:@"ParentViewController"] || [ident isEqualToString:@"iPhoneParentVC"])) continue;
                NSString *scene = [NSString stringWithFormat:@"%@/%@", name, ident];
                @try {
                    UIViewController *vc = [sb instantiateViewControllerWithIdentifier:ident];
                    [vc loadViewIfNeeded];
                    CGRect f = vc.view.frame;
                    vc.view.frame = CGRectMake(-4000, -4000, MAX(f.size.width, 1), MAX(f.size.height, 1));
                    [win addSubview:vc.view];
                    [vc.view layoutIfNeeded];
                    MeasureAll(vc.view, scene, NO);
                    [vc.view removeFromSuperview];
                    scenes++;
                } @catch (NSException *e) {
                    Log([NSString stringWithFormat:@"EXC scene %@: %@", scene, e.reason]);
                }
            }
        }
        Log([NSString stringWithFormat:@"SWEPT\tmode=%@\tstoryboards=%lu\tscenes=%lu", gMode, (unsigned long)paths.count, (unsigned long)scenes]);
    });
}

__attribute__((constructor)) static void S1WalkInit(void) {
    const char *out = getenv("S1WALK_OUT");
    if (!out) return;
    gOut = [NSString stringWithUTF8String:out];
    [[NSFileManager defaultManager] createDirectoryAtPath:gOut withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *logPath = [gOut stringByAppendingPathComponent:@"log.txt"];
    [[NSFileManager defaultManager] createFileAtPath:logPath contents:nil attributes:nil];
    gLogHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    gSteps = [NSMutableArray array];

    AddModeSteps(@"system", UIUserInterfaceStyleUnspecified);
    AddModeSteps(@"lightOverride", UIUserInterfaceStyleLight);
    Step(^{
        KeyWindow().overrideUserInterfaceStyle = UIUserInterfaceStyleUnspecified;
        DismissAll();
        Log(@"DONE");
        [@"done" writeToFile:[gOut stringByAppendingPathComponent:@"DONE"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
        exit(0);
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Log([NSString stringWithFormat:@"START\tmanager=%@\tpresented=%@", Manager(), TopPresented()]);
        Next();
    });
}
