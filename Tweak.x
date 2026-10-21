#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>
#import <math.h>
#import "Shared/NCPacks.h"
#import <notify.h>

// iOS 15 plus an experimental runtime-selected iOS 16/17 adapter. All rendering and settings changes run on the main thread.
static BOOL NCEnabled = YES, NCHideDate = NO, NCAnimated = YES, NCStillLowPower = NO, NCTint = NO;
static BOOL NCShowSeconds = NO;
static NSTimer *NCSecondsTimer;
static BOOL NCScreenOn = NO;
static int NCDisplayToken = -1;
static CGFloat NCScale = 1, NCSpacing = -2, NCOffset = 0, NCSpeed = 1;
static NSString *NCPack = @"Anime", *NCFormat = @"system", *NCColorHex = @"#FF9500";
static NSHashTable<UIView *> *NCViews;
static NSCache *NCImages;
static NSUInteger NCGeneration = 1;
static NSString *NCResolvedFolder;
static BOOL NCResolvedWanted;
static BOOL NCStarted = NO;
static CFTimeInterval NCEpoch = 0;
static char NCStateKey, NCGlyphKey, NCContentAlphaKey, NCDateAlphaKey;

@interface NCGlyph : NSObject
@property(nonatomic, copy) NSArray<UIImage *> *frames;
@property(nonatomic, copy) NSArray<NSNumber *> *keyTimes;
@property(nonatomic) NSTimeInterval duration;
@property(nonatomic) NSUInteger cost;
@end
@implementation NCGlyph
@end

@interface NCClockState : NSObject
@property(nonatomic, strong) UIView *overlay;
@property(nonatomic, strong) NSMutableArray<UIImageView *> *views;
@property(nonatomic, copy) NSString *signature;
@property(nonatomic) BOOL animated;
@end
@implementation NCClockState
@end

static id NCPref(NSString *key) {
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, CFSTR("com.ratnik00.nextclock")));
}
static BOOL NCBool(NSString *key, BOOL fallback) {
    id value = NCPref(key); return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}
static CGFloat NCFloat(NSString *key, CGFloat fallback, CGFloat minimum, CGFloat maximum) {
    id value = NCPref(key);
    double number = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    return isfinite(number) ? MAX(minimum, MIN(maximum, number)) : fallback;
}
static NSString *NCString(NSString *key, NSString *fallback) {
    id value = NCPref(key); return [value isKindOfClass:NSString.class] ? value : fallback;
}
static void NCLoadSettings(void) {
    CFPreferencesAppSynchronize(CFSTR("com.ratnik00.nextclock"));
    NCEnabled = NCBool(@"enabled", YES); NCHideDate = NCBool(@"hideDate", NO);
    NCShowSeconds = NCBool(@"showSeconds", NO);
    NCAnimated = ![NCString(@"animationStyle", @"animated") isEqual:@"static"];
    NCStillLowPower = NCBool(@"staticInLowPower", NO); NCTint = NCBool(@"colorFilterEnabled", NO);
    NCScale = NCFloat(@"clockScale", 1, .3, 2.5);
    NCSpacing = NCFloat(@"digitSpacing", -2, -25, 40);
    NCOffset = NCFloat(@"verticalOffset", 0, -120, 120);
    NCSpeed = NCFloat(@"animationSpeed", 1, .25, 3);
    NCPack = NCString(@"pack", @"Anime"); if (!NCValidIdentifier(NCPack)) NCPack = @"Anime";
    NCFormat = NCString(@"timeFormat", @"system");
    if (![@[@"system", @"12hour", @"24hour"] containsObject:NCFormat]) NCFormat = @"system";
    NCColorHex = NCString(@"tintColor", @"#FF9500");
    [NCImages removeAllObjects]; NCResolvedFolder = nil; NCGeneration++;
}
static BOOL NCWantsAnimation(void) {
    return NCAnimated && !(NCStillLowPower && NSProcessInfo.processInfo.lowPowerModeEnabled);
}
static UIColor *NCColor(void) {
    NSString *hex = [NCColorHex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int value = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (hex.length != 6 || ![scanner scanHexInt:&value] || !scanner.isAtEnd) value = 0xFF9500;
    return [UIColor colorWithRed:((value >> 16) & 255)/255.0 green:((value >> 8) & 255)/255.0
                           blue:(value & 255)/255.0 alpha:1];
}
static UIImage *NCTintedFrame(UIImage *image) {
    if (!NCTint) return image;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) { UIGraphicsEndImageContext(); return image; }
    CGRect rect = (CGRect){CGPointZero, image.size};
    CGContextTranslateCTM(context, 0, image.size.height); CGContextScaleCTM(context, 1, -1);
    CGContextDrawImage(context, rect, image.CGImage);
    CGContextClipToMask(context, rect, image.CGImage);
    CGContextSetBlendMode(context, kCGBlendModeColor);
    CGContextSetFillColorWithColor(context, NCColor().CGColor); CGContextFillRect(context, rect);
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext(); UIGraphicsEndImageContext();
    return result ?: image;
}
static NCGlyph *NCDecode(NSString *path, BOOL animate, NSUInteger budget) {
    NSString *key = [NSString stringWithFormat:@"%@|%d|%d|%@", path, animate, NCTint, NCColorHex];
    NCGlyph *cached = [NCImages objectForKey:key];
    if (cached) return cached.cost <= budget ? cached : nil;
    if (!NCImageValid(path, NO)) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return nil;
    size_t count = CGImageSourceGetCount(source);
    if (!count || count > 240) { CFRelease(source); return nil; }
    if (!animate) count = 1;
    NSMutableArray *frames = [NSMutableArray array], *durations = [NSMutableArray array];
    NSTimeInterval total = 0; NSUInteger cost = 0;
    for (size_t index = 0; index < count; index++) {
        @autoreleasepool {
            CGImageRef frame = CGImageSourceCreateImageAtIndex(source, index, NULL);
            if (!frame) { CFRelease(source); return nil; }
            NSUInteger bytes = CGImageGetBytesPerRow(frame) * CGImageGetHeight(frame);
            if (bytes > budget || cost > budget - bytes) {
                CGImageRelease(frame); CFRelease(source); return nil;
            }
            cost += bytes;
            UIImage *image = NCTintedFrame([UIImage imageWithCGImage:frame]); CGImageRelease(frame);
            [frames addObject:image];
            NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, index, NULL));
            NSDictionary *gif = props[(__bridge NSString *)kCGImagePropertyGIFDictionary];
            NSDictionary *png = props[(__bridge NSString *)kCGImagePropertyPNGDictionary];
            NSNumber *delay = gif[(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?:
                gif[(__bridge NSString *)kCGImagePropertyGIFDelayTime] ?:
                png[(__bridge NSString *)kCGImagePropertyAPNGUnclampedDelayTime] ?:
                png[(__bridge NSString *)kCGImagePropertyAPNGDelayTime];
            double seconds = delay.doubleValue;
            if (!isfinite(seconds) || seconds <= 0) seconds = .1;
            seconds = MAX(.01, seconds);
            if (!isfinite(total + seconds)) { CFRelease(source); return nil; }
            [durations addObject:@(seconds)]; total += seconds;
        }
    }
    CFRelease(source);
    NSMutableArray *times = [NSMutableArray array]; double elapsed = 0;
    for (NSNumber *duration in durations) { [times addObject:@(elapsed / total)]; elapsed += duration.doubleValue; }
    [times addObject:@1];
    NCGlyph *glyph = [NCGlyph new]; glyph.frames = frames; glyph.keyTimes = times; glyph.duration = total; glyph.cost = cost;
    [NCImages setObject:glyph forKey:key cost:cost]; return glyph;
}
static void NCClearView(UIImageView *view) {
    [view.layer removeAnimationForKey:@"NextClock.frames"]; view.image = nil;
    objc_setAssociatedObject(view, &NCGlyphKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void NCSetGlyph(UIImageView *view, NCGlyph *glyph, BOOL animate) {
    BOOL moving = animate && glyph.frames.count > 1;
    if (objc_getAssociatedObject(view, &NCGlyphKey) == glyph &&
        (!moving || [view.layer animationForKey:@"NextClock.frames"])) return;
    NCClearView(view); view.image = glyph.frames.firstObject;
    objc_setAssociatedObject(view, &NCGlyphKey, glyph, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!moving) return;
    NSMutableArray *contents = [NSMutableArray array];
    for (UIImage *frame in glyph.frames) [contents addObject:(__bridge id)frame.CGImage];
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
    animation.values = contents; animation.keyTimes = glyph.keyTimes;
    animation.calculationMode = kCAAnimationDiscrete; animation.duration = glyph.duration / NCSpeed;
    animation.repeatCount = HUGE_VALF; animation.removedOnCompletion = NO;
    if (!NCEpoch) NCEpoch = CACurrentMediaTime();
    animation.beginTime = [view.layer convertTime:NCEpoch fromLayer:nil];
    [view.layer addAnimation:animation forKey:@"NextClock.frames"];
}
static NSString *NCFolder(BOOL wanted) {
    if (NCResolvedFolder && NCResolvedWanted == wanted) return NCResolvedFolder;
    NSArray *variants = wanted ? @[@"animated", @"static"] : @[@"static", @"animated"];
    NSArray *ids = [NCPack isEqual:@"Anime"] ? @[@"Anime"] : @[NCPack, @"Anime"];
    NCResolvedFolder = nil; NCResolvedWanted = wanted;
    for (NSString *identifier in ids) {
        for (NSString *root in @[NCUserRoot(), NCBuiltinRoot()]) {
            for (NSString *variant in variants) {
                NSString *folder = [[root stringByAppendingPathComponent:identifier] stringByAppendingPathComponent:variant];
                if (NCCompleteVariant(folder, NO)) { NCResolvedFolder = folder; return folder; }
            }
        }
    }
    return nil;
}
static NSString *NCTime(NSDate *date) {
    static NSDateFormatter *formatter;
    if (!formatter) {
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    }
    BOOL use24 = ![NCFormat isEqual:@"12hour"];
    if ([NCFormat isEqual:@"system"]) {
        NSString *pattern = [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:NSLocale.currentLocale];
        use24 = [pattern containsString:@"H"] || [pattern containsString:@"k"];
    }
    formatter.dateFormat = NCShowSeconds
        ? (use24 ? @"HH:mm:ss" : @"h:mm:ss")
        : (use24 ? @"HH:mm" : @"h:mm");
    formatter.timeZone = NSTimeZone.localTimeZone; return [formatter stringFromDate:date];
}
static void NCRefreshViews(void) {
    for (UIView *view in NCViews.allObjects) {
        [view setNeedsLayout];
    }
}

static BOOL NCHasVisibleClock(void) {
    for (UIView *view in NCViews.allObjects) {
        NCClockState *state = objc_getAssociatedObject(view, &NCStateKey);
        if (!view.window || !state.overlay || state.overlay.hidden) continue;

        BOOL visible = YES;

        for (UIView *parent = view; parent; parent = parent.superview) {
            if (parent.hidden || parent.alpha <= 0.01) {
                visible = NO;
                break;
            }
        }

        if (visible) return YES;
    }

    return NO;
}

static void NCUpdateSecondsTimer(void) {
    BOOL shouldRun =
        NCEnabled &&
        NCShowSeconds &&
        NCScreenOn &&
        NCHasVisibleClock();

    if (!shouldRun) {
        [NCSecondsTimer invalidate];
        NCSecondsTimer = nil;
        return;
    }

    if (NCSecondsTimer) return;

    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSDate *nextSecond =
        [NSDate dateWithTimeIntervalSince1970:floor(now) + 1.0];

    NCSecondsTimer = [[NSTimer alloc]
        initWithFireDate:nextSecond
        interval:1.0
        repeats:YES
        block:^(NSTimer *timer) {
            if (!NCEnabled || !NCShowSeconds ||
                !NCScreenOn || !NCHasVisibleClock()) {
                [timer invalidate];
                NCSecondsTimer = nil;
                return;
            }

            NCRefreshViews();
        }];

    NCSecondsTimer.tolerance = 0.02;

    [NSRunLoop.mainRunLoop
        addTimer:NCSecondsTimer
        forMode:NSRunLoopCommonModes];
}
static void NCPreferencesChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NCLoadSettings();
        NCUpdateSecondsTimer();
        NCRefreshViews();
    });
}

static void NCRespring(CFNotificationCenterRef c, void *o, CFStringRef n, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
}
static void NCStart(void) {
    if (NCStarted) return; NCStarted = YES;
    NCViews = [NSHashTable weakObjectsHashTable]; NCImages = [NSCache new]; NCImages.totalCostLimit = 36 * 1024 * 1024;
    NCLoadSettings();
    uint32_t result = notify_register_dispatch(
        "com.apple.iokit.hid.displayStatus",
        &NCDisplayToken,
        dispatch_get_main_queue(),
        ^(int token) {
            uint64_t state = 0;

            if (notify_get_state(token, &state) == NOTIFY_STATUS_OK) {
                NCScreenOn = state != 0;
            } else {
                NCScreenOn = NO;
            }

            NCUpdateSecondsTimer();

            if (NCScreenOn) {
                NCRefreshViews();
            }
        }
    );

    if (result == NOTIFY_STATUS_OK) {
        uint64_t state = 0;

        if (notify_get_state(NCDisplayToken, &state) ==
            NOTIFY_STATUS_OK) {
            NCScreenOn = state != 0;
        }
    } else {
        NSLog(@"[NextClock] Cannot observe display state: %u",
              (unsigned int)result);
    }
    CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
    CFNotificationCenterAddObserver(center, NULL, NCPreferencesChanged, CFSTR("com.ratnik00.nextclock/preferenceschanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(center, NULL, NCRespring, CFSTR("com.ratnik00.nextclock/respring"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    [NSNotificationCenter.defaultCenter addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NCResolvedFolder = nil; NCGeneration++; [NCImages removeAllObjects]; NCRefreshViews();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [NCImages removeAllObjects]; }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSSystemTimeZoneDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { NCGeneration++; NCRefreshViews(); }];
}

@interface SBFLockScreenDateView : UIView
- (NSDate *)date;
- (void)setDate:(NSDate *)date;
@end

static BOOL NCStatusSubtitleVisible(UIView *clockView) {
    Class subtitleClass =
        NSClassFromString(@"SBFLockScreenDateSubtitleView");

    Class dateClass =
        NSClassFromString(@"SBFLockScreenDateSubtitleDateView");

    for (UIView *view in clockView.subviews) {
        BOOL isSubtitle =
            subtitleClass && [view isKindOfClass:subtitleClass];

        BOOL isDate =
            dateClass && [view isKindOfClass:dateClass];

        if (isSubtitle && !isDate &&
            !view.hidden && view.alpha > 0.01) {
            return YES;
        }
    }

    return NO;
}

static void NCLayoutClock(UIView *self, UIView *timeLabel, UIView *dateLabel, NSDate *providedDate) {
    NCStart();
     [NCViews addObject:self];
    NCUpdateSecondsTimer();
    NCClockState *state = objc_getAssociatedObject(self, &NCStateKey);
    if (!timeLabel || timeLabel.hidden) {
        state.overlay.hidden = YES; state.signature = nil;
        for (UIImageView *view in state.views) NCClearView(view);
        return;
    }
    NSNumber *savedTimeAlpha = objc_getAssociatedObject(self, &NCContentAlphaKey);
    CGFloat systemTimeAlpha = savedTimeAlpha ? savedTimeAlpha.doubleValue : 1;
    NSNumber *savedDateAlpha =
        objc_getAssociatedObject(self, &NCDateAlphaKey);

    CGFloat systemDateAlpha =
        savedDateAlpha ? savedDateAlpha.doubleValue : dateLabel.alpha;

    if (dateLabel && !savedDateAlpha) {
        objc_setAssociatedObject(
            self,
            &NCDateAlphaKey,
            @(systemDateAlpha),
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    }

    dateLabel.alpha =
    NCEnabled && (NCHideDate || NCStatusSubtitleVisible(self)) ? 0 : systemDateAlpha;
    if (NCEnabled && NCStatusSubtitleVisible(self)) {
        timeLabel.alpha = 0;
        dateLabel.alpha = 0;
        state.overlay.hidden = YES;
        state.signature = nil;
        for (UIImageView *view in state.views) NCClearView(view);
        return;
    }
    if (!NCEnabled) {
        timeLabel.alpha = systemTimeAlpha; state.overlay.hidden = YES; state.signature = nil;
        for (UIImageView *view in state.views) NCClearView(view);
        return;
    }
    BOOL wanted = NCWantsAnimation();
    NSDate *date = NCShowSeconds
        ? NSDate.date
        : providedDate;

    NSString *time = NCTime(date ?: NSDate.date);
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%lu|%d", time,
        NSStringFromCGRect(timeLabel.frame), NSStringFromCGRect(self.bounds), (unsigned long)NCGeneration, wanted];
    if (state && [state.signature isEqual:signature] && !state.overlay.hidden) {
        // Core Animation can discard animations while the lock screen is detached.
        for (UIImageView *view in state.views) {
            NCGlyph *glyph = objc_getAssociatedObject(view, &NCGlyphKey);
            if (!view.hidden && glyph) NCSetGlyph(view, glyph, state.animated);
        }
        timeLabel.alpha = 0; return;
    }
    NSString *folder = NCFolder(wanted);
    NSMutableArray<NCGlyph *> *glyphs = [NSMutableArray array];
    NSMutableDictionary<NSString *, NCGlyph *> *loaded = [NSMutableDictionary dictionary];
    // Bound the decoded frames retained by one clock row, including animated packs.
    NSUInteger remainingBytes = 48 * 1024 * 1024;
    for (NSUInteger i = 0; folder && i < time.length; i++) {
        NSString *symbol = [time substringWithRange:NSMakeRange(i, 1)];
        NSString *name = [symbol isEqual:@":"] ? @"colon" : symbol;
        NSString *path = NCGlyphPath(folder, name);
        NCGlyph *glyph = path ? loaded[path] : nil;
        if (!glyph && path) {
            glyph = NCDecode(path, wanted, remainingBytes);
            if (glyph) { loaded[path] = glyph; remainingBytes -= glyph.cost; }
        }
        if (!glyph) { [glyphs removeAllObjects]; break; } [glyphs addObject:glyph];
    }
    if (!glyphs.count) {
        timeLabel.alpha = systemTimeAlpha; state.overlay.hidden = YES; state.signature = nil;
        for (UIImageView *view in state.views) NCClearView(view);
        return;
    }
    if (!state) {
        state = [NCClockState new]; state.overlay = [UIView new]; state.overlay.userInteractionEnabled = NO;
        state.views = [NSMutableArray array];
        objc_setAssociatedObject(self, &NCStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (state.overlay.superview != self) [self addSubview:state.overlay];
    state.overlay.frame = self.bounds; state.overlay.hidden = NO;
    NSNumber *systemAlpha = objc_getAssociatedObject(self, &NCContentAlphaKey);
    state.overlay.alpha = systemAlpha ? systemAlpha.doubleValue : 1;
    while (state.views.count < glyphs.count) {
        UIImageView *view = [UIImageView new]; view.contentMode = UIViewContentModeScaleAspectFit; view.userInteractionEnabled = NO;
        [state.overlay addSubview:view]; [state.views addObject:view];
    }
    for (NSUInteger i = glyphs.count; i < state.views.count; i++) { state.views[i].hidden = YES; NCClearView(state.views[i]); }
    CGFloat aspectSum = 0;
    for (NCGlyph *glyph in glyphs) { UIImage *first = glyph.frames.firstObject; aspectSum += first.size.width / first.size.height; }
    CGRect rect = [self convertRect:timeLabel.bounds fromView:timeLabel];
    CGFloat height = rect.size.height * NCScale, gaps = NCSpacing * (glyphs.count - 1);
    CGFloat widthLimit = MAX(0, self.bounds.size.width - 32);
    if (aspectSum <= 0 || widthLimit - gaps <= 0 || height <= 0) {
        state.overlay.hidden = YES; timeLabel.alpha = systemTimeAlpha; state.signature = nil;
        for (UIImageView *view in state.views) NCClearView(view); return;
    }
    // Keep the full row inside the screen on iOS 15, even with wide custom artwork.
    height = MIN(height, (widthLimit - gaps) / aspectSum);
    CGFloat width = height * aspectSum + gaps;
    CGFloat x = CGRectGetMidX(rect) - width / 2, y = CGRectGetMidY(rect) - height / 2 + NCOffset;
    for (NSUInteger i = 0; i < glyphs.count; i++) {
        UIImageView *view = state.views[i]; UIImage *first = glyphs[i].frames.firstObject;
        CGFloat glyphWidth = height * first.size.width / first.size.height;
        view.hidden = NO; view.frame = CGRectMake(x - self.bounds.origin.x, y - self.bounds.origin.y, glyphWidth, height);
        NCSetGlyph(view, glyphs[i], wanted); x += glyphWidth + NCSpacing;
    }
    timeLabel.alpha = 0; state.signature = signature; state.animated = wanted;
    NCUpdateSecondsTimer();
}

%group NCLegacyClock
%hook SBFLockScreenDateView
- (void)layoutSubviews {
    %orig;
    UIView *timeLabel = nil, *dateLabel = nil;
    Class timeClass = NSClassFromString(@"SBUILegibilityLabel"), dateClass = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
    for (UIView *view in self.subviews) {
        if (timeClass && [view isKindOfClass:timeClass]) timeLabel = view;
        if (dateClass && [view isKindOfClass:dateClass]) dateLabel = view;
    }
    NCLayoutClock(self, timeLabel, dateLabel, self.date);
}
- (void)setDate:(NSDate *)date {
    %orig;
    [self setNeedsLayout];
}
    - (void)didMoveToWindow {
        %orig;

        NCClockState *state =
            objc_getAssociatedObject(self, &NCStateKey);

        if (!self.window) {
            for (UIImageView *view in state.views) {
                NCClearView(view);
            }

            state.signature = nil;
        } else {
            [self setNeedsLayout];
        }

        NCUpdateSecondsTimer();
    }
%end
%end
// Follow the system clock's visibility during the battery presentation.
// Keep this hook separate: private methods may differ between iOS versions.
%group NCSystemClockVisibility
%hook SBFLockScreenDateView
- (void)setContentAlpha:(CGFloat)alpha withSubtitleVisible:(BOOL)subtitleVisible {
    objc_setAssociatedObject(self, &NCContentAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
    Class dateClass =
        NSClassFromString(@"SBFLockScreenDateSubtitleDateView");

    CGFloat systemDateAlpha = subtitleVisible ? alpha : 0;

    objc_setAssociatedObject(
        self,
        &NCDateAlphaKey,
        @(systemDateAlpha),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    for (UIView *view in self.subviews) {
        if (dateClass && [view isKindOfClass:dateClass]) {
            view.alpha =
                NCEnabled && (NCHideDate || NCStatusSubtitleVisible(self)) ? 0 : systemDateAlpha;
        }
    }
    NCClockState *state =
        objc_getAssociatedObject(self, &NCStateKey);
    // Runs in the system's animation transaction, including the return to the clock.
    state.overlay.alpha = NCEnabled && NCStatusSubtitleVisible(self) ? 0 : alpha;
    [self setNeedsLayout];
    // The original setter may make the text visible again. Our overlay replaces it.
    if (NCEnabled && state.overlay && !state.overlay.hidden) {
        Class timeClass = NSClassFromString(@"SBUILegibilityLabel");
        for (UIView *view in self.subviews) {
            if (timeClass && [view isKindOfClass:timeClass]) view.alpha = 0;
        }
    }
}
%end
%end

@interface SBFLockScreenDateSubtitleView : UIView
@end

static void NCSubtitleChanged(UIView *view) {
    Class dateClass = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
    if (dateClass && [view isKindOfClass:dateClass]) return;
    NCRefreshViews();
}

%group NCStatusSubtitleUpdates
%hook SBFLockScreenDateSubtitleView
- (void)setAlpha:(CGFloat)alpha {
    BOOL changed = self.alpha != alpha;
    %orig;
    if (changed) NCSubtitleChanged(self);
}
- (void)setHidden:(BOOL)hidden {
    BOOL changed = self.hidden != hidden;
    %orig;
    if (changed) NCSubtitleChanged(self);
}
- (void)didMoveToSuperview {
    %orig;
    NCSubtitleChanged(self);
}
%end
%end


// Experimental adapter: selector names verified only against an upstream iOS 18
// class dump. Runtime availability checks do not establish iOS 16/17 compatibility.
static char NCModernDisplayDateKey;
static char NCModernSuppressTimeKey;
@interface CSProminentDisplayView : UIView
- (UIView *)timeView;
- (UIView *)subtitleView;
- (UIView *)transientSubtitleView;
@end

static void NCCompatibilitySnapshot(UIView *host) {
    static BOOL captured = NO;
    if (captured) return;
    captured = YES;
    NSMutableString *report = [NSMutableString stringWithFormat:@"NextClock 1.1.0~beta2 (experimental)\niOS: %@\n", UIDevice.currentDevice.systemVersion];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:host];
    for (NSUInteger i = 0; i < queue.count && i < 120; i++) {
        UIView *view = queue[i];
        [report appendFormat:@"%@ frame=%@ alpha=%.2f hidden=%d\n", NSStringFromClass(view.class), NSStringFromCGRect(view.frame), view.alpha, view.hidden];
        if (queue.count < 120) [queue addObjectsFromArray:view.subviews];
    }
    NSString *snapshot = report.copy;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [snapshot writeToFile:@"/var/mobile/Library/NextClock-compatibility.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
}
%group NCModernClock
%hook CSProminentDisplayView
- (void)layoutSubviews {
    // Allow the renderer to restore stock content on every fallback path.
    UIView *previousTime = self.timeView;
    if ([previousTime isKindOfClass:UIView.class]) {
        objc_setAssociatedObject(previousTime, &NCModernSuppressTimeKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
    NCCompatibilitySnapshot(self);
    UIView *time = self.timeView;
    if (![time isKindOfClass:UIView.class] || ![time isDescendantOfView:self]) return;
    UIView *subtitle = self.subtitleView;
    Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
    UIView *date = dateClass && [subtitle isKindOfClass:dateClass] ? subtitle : nil;
    UIView *transient = nil;

    if ([self respondsToSelector:@selector(transientSubtitleView)]) {
        transient = self.transientSubtitleView;
    }

    BOOL transientVisible =
        [transient isKindOfClass:UIView.class] &&
        transient.superview &&
        !transient.hidden &&
        transient.alpha > 0.01;

    BOOL statusVisible =
        subtitle && !date &&
        !subtitle.hidden && subtitle.alpha > 0.01;

    if (NCEnabled && (transientVisible || statusVisible)) {
        NCClockState *state =
            objc_getAssociatedObject(self, &NCStateKey);

        // Preserve the date's original alpha before hiding it.
        if (date &&
            !objc_getAssociatedObject(self, &NCDateAlphaKey)) {
            objc_setAssociatedObject(
                self,
                &NCDateAlphaKey,
                @(date.alpha),
                OBJC_ASSOCIATION_RETAIN_NONATOMIC
            );
        }

        objc_setAssociatedObject(time, &NCModernSuppressTimeKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        time.alpha = 0;
        date.alpha = 0;
        state.overlay.hidden = YES;
        state.signature = nil;

        for (UIImageView *image in state.views) {
            NCClearView(image);
        }

        NCUpdateSecondsTimer();
        return;
    }
    NSDate *displayDate =
        objc_getAssociatedObject(self, &NCModernDisplayDateKey);

    NCLayoutClock(self, time, date, displayDate ?: [NSDate date]);
    NCClockState *rendered = objc_getAssociatedObject(self, &NCStateKey);
    BOOL replacingTime = NCEnabled && rendered.overlay &&
        rendered.overlay.superview == self && !rendered.overlay.hidden;
    objc_setAssociatedObject(time, &NCModernSuppressTimeKey,
                             replacingTime ? @YES : nil,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (replacingTime) time.alpha = 0;
}
- (void)setDisplayDate:(NSDate *)date {
    objc_setAssociatedObject(
        self,
        &NCModernDisplayDateKey,
        date,
        OBJC_ASSOCIATION_COPY_NONATOMIC
    );

    %orig;
    [self setNeedsLayout];
}
- (void)didMoveToWindow {
    %orig;
    NCClockState *state = objc_getAssociatedObject(self, &NCStateKey);
    if (!self.window) {
        for (UIImageView *image in state.views) NCClearView(image);
        state.signature = nil;
    } else [self setNeedsLayout];
    NCUpdateSecondsTimer();
}
%end
%end

// The system can restore the time view's alpha outside its host's layout,
// for example while switching wallpapers or expanding music artwork.
// Only suppress instances explicitly owned by an active NextClock renderer.
@interface CSProminentTimeView : UIView
@end

%group NCModernTimeVisibility
%hook CSProminentTimeView
- (void)setAlpha:(CGFloat)alpha {
    BOOL suppress = NCEnabled &&
        [objc_getAssociatedObject(self, &NCModernSuppressTimeKey) boolValue];
    %orig(suppress ? 0 : alpha);
}
- (void)layoutSubviews {
    %orig;
    if (NCEnabled &&
        [objc_getAssociatedObject(self, &NCModernSuppressTimeKey) boolValue]) {
        self.alpha = 0;
    }
}
%end
%end

// Re-evaluate the overlay when transient system subtitles change.
%group NCModernSubtitleUpdates
%hook CSProminentDisplayView
- (void)setSubtitleAlpha:(CGFloat)alpha {
    %orig;
    [self setNeedsLayout];
}
- (void)setTransientSubtitleView:(UIView *)view {
    %orig;
    [self setNeedsLayout];
}
%end
%end

%ctor {
    @autoreleasepool {
        Class modernClass = NSClassFromString(@"CSProminentDisplayView");
        BOOL modern = UIDevice.currentDevice.systemVersion.doubleValue >= 16 && modernClass &&
            class_getInstanceMethod(modernClass, @selector(timeView)) &&
            class_getInstanceMethod(modernClass, @selector(subtitleView)) &&
            class_getInstanceMethod(modernClass, @selector(setDisplayDate:));
        Class legacyClass = NSClassFromString(@"SBFLockScreenDateView");
        BOOL legacy = legacyClass && class_getInstanceMethod(legacyClass, @selector(date)) &&
            class_getInstanceMethod(legacyClass, @selector(setDate:));
        NSMutableString *startupReport = [NSMutableString stringWithFormat:
            @"NextClock 1.1.0~beta2 (experimental)\niOS: %@\nAdapter: %@\n",
            UIDevice.currentDevice.systemVersion, modern ? @"prominent (untested)" : (legacy ? @"legacy" : @"none; required classes unavailable")];
        for (NSString *name in @[@"SBFLockScreenDateView", @"CSProminentDisplayView", @"CSProminentTimeView", @"CSProminentSubtitleDateView"]) {
            [startupReport appendFormat:@"%@: %@\n", name, NSClassFromString(name) ? @"present" : @"absent"];
        }
        [startupReport appendString:@"\nModern adapter methods:\n"];

        for (NSString *name in @[
            @"timeView",
            @"subtitleView",
            @"displayDate",
            @"setDisplayDate:"
        ]) {
            SEL selector = NSSelectorFromString(name);
            Method method = modernClass
                ? class_getInstanceMethod(modernClass, selector)
                : NULL;

            [startupReport appendFormat:@"%@: %@\n",
                name, method ? @"present" : @"absent"];
        }

        [startupReport appendString:@"\nAvailable instance methods:\n"];

        if (modernClass) {
            unsigned int count = 0;
            Method *methods = class_copyMethodList(modernClass, &count);

            for (unsigned int i = 0; i < count; i++) {
                [startupReport appendFormat:@"%@\n",
                    NSStringFromSelector(method_getName(methods[i]))];
            }

            free(methods);
        }
        [startupReport writeToFile:@"/var/mobile/Library/NextClock-compatibility.txt"
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        if (modern) {
            %init(NCModernClock);
            Class modernTimeClass = NSClassFromString(@"CSProminentTimeView");
            if (modernTimeClass && [modernTimeClass isSubclassOfClass:UIView.class] &&
                class_getInstanceMethod(modernTimeClass, @selector(setAlpha:)) &&
                class_getInstanceMethod(modernTimeClass, @selector(layoutSubviews))) {
                %init(NCModernTimeVisibility);
            }
            BOOL subtitleUpdatesAvailable =
                class_getInstanceMethod(modernClass, @selector(setSubtitleAlpha:)) &&
                class_getInstanceMethod(modernClass, @selector(setTransientSubtitleView:));
            if (subtitleUpdatesAvailable) {
                %init(NCModernSubtitleUpdates);
            }
            NSLog(@"[NextClock] Experimental modern adapter selected; runtime testing required");
        } else if (legacy) {
            %init(NCLegacyClock);
        } else {
            NSLog(@"[NextClock] No compatible clock adapter; keeping system clock");
        }
        if (!modern && legacy && NSClassFromString(@"SBFLockScreenDateSubtitleView")) {
            %init(NCStatusSubtitleUpdates);
        }
        Class dateClass = NSClassFromString(@"SBFLockScreenDateView");
        SEL selector = @selector(setContentAlpha:withSubtitleVisible:);
        if (!modern && legacy && class_getInstanceMethod(dateClass, selector)) {
            %init(NCSystemClockVisibility);
        } else {
            NSLog(@"[NextClock] System clock visibility method unavailable on this iOS version");
        }
    }
}
