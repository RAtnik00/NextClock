#import <CommonCrypto/CommonDigest.h>
#import <unistd.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>
#import <math.h>
#import "Shared/NCPacks.h"
#import "Shared/NCWallpaperPacks.h"
#import "Shared/NCVersion.h"
#import "Shared/NCLayoutSafety.h"
#import "Shared/NCFavorites.h"
#import "Shared/NCDateFont.h"
#import "Shared/NCModernContext.h"
#import <notify.h>

// Legacy date-view adapter (iOS 12-15) and experimental iOS 16/17 adapter.
// iOS 12-14 rootful builds require device testing. UI changes run on main.
static BOOL NCEnabled = YES, NCHideDate = NO, NCAnimated = YES, NCStillLowPower = NO, NCTint = NO;
static BOOL NCShowSeconds = NO;
static NSDictionary *NCDateStyle;
static NSTimer *NCSecondsTimer;
static BOOL NCScreenOn = NO;
static int NCDisplayToken = -1;
static CGFloat NCScale = 1, NCSpacing = -2, NCOffset = 0, NCSpeed = 1;
static NSString *NCPack = @"Anime", *NCFormat = @"system", *NCColorHex = @"#FF9500";
static NSHashTable<UIView *> *NCViews;
static NSCache *NCImages;
static NSDictionary *NCWallpaperBindings;
static NSUInteger NCGeneration = 1;
static NSString *NCResolvedFolder;
static BOOL NCResolvedWanted;
static BOOL NCStarted = NO;
static CFTimeInterval NCEpoch = 0;
static char NCStateKey, NCGlyphKey, NCContentAlphaKey, NCDateAlphaKey;
static char NCLegacyTimeSuppressionKey;

@interface NCGlyph : NSObject
@property(nonatomic, copy) NSArray<UIImage *> *frames;
@property(nonatomic, copy) NSArray<NSNumber *> *keyTimes;
@property(nonatomic) NSTimeInterval duration;
@property(nonatomic) NSUInteger cost;
@end
@implementation NCGlyph
@end

static void NCCycleFavorite(void);
static BOOL NCFavoriteGestureEnabled;

@interface NCClockState : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIView *overlay;
@property(nonatomic, strong) NSMutableArray<UIImageView *> *views;
@property(nonatomic, copy) NSString *signature;
@property(nonatomic) BOOL animated;
@property(nonatomic,strong) UITapGestureRecognizer *favoriteTap;
@end
@implementation NCClockState
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (!NCEnabled || !NCFavoriteGestureEnabled || self.overlay.hidden || self.overlay.alpha<=.01 || !self.overlay.window) return NO;
    for (UIView *v=self.overlay;v;v=v.superview) if (v.hidden || v.alpha<=.01) return NO;
    CGPoint point=[touch locationInView:self.overlay];
    for (UIImageView *digit in self.views) if (!digit.hidden && CGRectContainsPoint(digit.frame,point)) return YES;
    return NO;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
- (void)cycleFavorite:(UITapGestureRecognizer *)gesture {
    if (gesture.state==UIGestureRecognizerStateRecognized && NCEnabled && NCFavoriteGestureEnabled && !self.overlay.hidden) NCCycleFavorite();
}
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
    NCDateStyle=NCNormalizeDateStyle(@{@"dateFontDesign":NCString(@"dateFontDesign",@"system"),@"dateFontScale":@(NCFloat(@"dateFontScale",1,.6,1.6)),@"dateFontWeight":NCString(@"dateFontWeight",@"system")});
    NCEnabled = NCBool(@"enabled", YES); NCHideDate = NCBool(@"hideDate", NO);
    NCShowSeconds = NCBool(@"showSeconds", NO);
    NCFavoriteGestureEnabled = NCBool(@"doubleTapFavorites", NO);
    NCAnimated = ![NCString(@"animationStyle", @"animated") isEqual:@"static"];
    NCStillLowPower = NCBool(@"staticInLowPower", NO); NCTint = NCBool(@"colorFilterEnabled", NO);
    NCScale = NCFloat(@"clockScale", 1, .3, 2.5);
    NCSpacing = NCFloat(@"digitSpacing", -2, -25, 40);
    NCOffset = NCFloat(@"verticalOffset", 0, -120, 120);
    NCSpeed = NCFloat(@"animationSpeed", 1, .25, 3);
    NCWallpaperBindings = NCWallpaperPackBindings();
    NCPack = NCString(@"pack", @"Anime"); if (!NCValidIdentifier(NCPack)) NCPack = @"Anime";
    NCFormat = NCString(@"timeFormat", @"system");
    if (![@[@"system", @"12hour", @"24hour"] containsObject:NCFormat]) NCFormat = @"system";
    NCColorHex = NCString(@"tintColor", @"#FF9500");
    [NCImages removeAllObjects]; NCResolvedFolder = nil; NCGeneration++;
}
static BOOL NCWantsAnimation(void) {
    return !UIAccessibilityIsReduceMotionEnabled() && NCAnimated && !(NCStillLowPower && NSProcessInfo.processInfo.lowPowerModeEnabled);
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
// Keep a small static fallback while detached, without retaining decoded animations.
static void NCFreezeView(UIImageView *view) {
    NCGlyph *glyph = objc_getAssociatedObject(view, &NCGlyphKey);
    UIImage *still = glyph.frames.firstObject ?: view.image;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    NCClearView(view);
    view.image = still;
    [CATransaction commit];
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
    // The closing key time is 1.0; repeat the first frame at that boundary.
    [contents addObject:contents.firstObject];
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"contents"];
    animation.values = contents; animation.keyTimes = glyph.keyTimes;
    animation.calculationMode = kCAAnimationDiscrete; animation.duration = glyph.duration / NCSpeed;
    animation.repeatCount = HUGE_VALF; animation.removedOnCompletion = NO;
    if (!NCEpoch) NCEpoch = CACurrentMediaTime();
    animation.beginTime = [view.layer convertTime:NCEpoch fromLayer:nil];
    [view.layer addAnimation:animation forKey:@"NextClock.frames"];
}
static NSString *NCFolder(BOOL wanted, NSString *pack) {
    static NSString *resolvedPack;
    if (NCResolvedFolder && NCResolvedWanted == wanted && [resolvedPack isEqual:pack]) return NCResolvedFolder;
    NSArray *variants = wanted ? @[@"animated", @"static"] : @[@"static", @"animated"];
    NSArray *ids = [[NSOrderedSet orderedSetWithArray:@[pack, NCPack, @"Anime"]] array];
    resolvedPack = pack;
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

static void NCCycleFavorite(void) {
    CFPreferencesAppSynchronize(CFSTR("com.ratnik00.nextclock"));
    NSArray *favorites=NCFavoriteIdentifiers(NCPref(@"favoritePacks"),NCAllPacks());
    NSString *next=NCNextFavorite(favorites,NCString(@"pack",@"Anime"));
    if (!next) return;
    CFPreferencesSetAppValue(CFSTR("pack"),(__bridge CFStringRef)next,CFSTR("com.ratnik00.nextclock"));
    if (!CFPreferencesAppSynchronize(CFSTR("com.ratnik00.nextclock"))) return;
    NCLoadSettings(); NCRefreshViews();
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ratnik00.nextclock/preferenceschanged"),NULL,NULL,YES);
}

static char NCLayoutInProgressKey, NCLayoutQueuedKey;
// Coalesce callbacks from system setters/window attachment. UIKit can call these
// while the containing clock is already laying out its own children.
static void NCRequestClockLayout(UIView *host) {
    if (!host || [objc_getAssociatedObject(host,&NCLayoutQueuedKey) boolValue]) return;
    objc_setAssociatedObject(host,&NCLayoutQueuedKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakHost=host;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *view=weakHost; if (!view) return;
        objc_setAssociatedObject(view,&NCLayoutQueuedKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!view.window) return;
        [UIView performWithoutAnimation:^{ [view setNeedsLayout]; [view layoutIfNeeded]; }];
    });
}

static BOOL NCHasVisibleClock(void) {
    for (UIView *view in NCViews.allObjects) {
        NCClockState *state = objc_getAssociatedObject(view, &NCStateKey);
        if (!view.window || !state.overlay || state.overlay.hidden || state.overlay.alpha<=.01) continue;

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
                // Complete the clock update before the next visible frame.
                [UIView performWithoutAnimation:^{
                    for (UIView *view in NCViews.allObjects) {
                        if (!view.window) continue;
                        [view setNeedsLayout];
                        [view layoutIfNeeded];
                    }
                }];
                NCUpdateSecondsTimer();
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
    [NSNotificationCenter.defaultCenter addObserverForName:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NCResolvedFolder=nil; NCGeneration++; [NCImages removeAllObjects]; NCRefreshViews();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [NCImages removeAllObjects]; }];
    [NSNotificationCenter.defaultCenter addObserverForName:NSSystemTimeZoneDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { NCGeneration++; NCRefreshViews(); }];
}

@interface SBFLockScreenDateView : UIView
- (NSDate *)date;
- (void)setDate:(NSDate *)date;
@end

static char NCStatusReturnDeadlineKey, NCStatusReturnScheduledKey;

static BOOL NCRawStatusSubtitleVisible(UIView *clockView) {
    Class subtitleClass =
        NSClassFromString(@"SBFLockScreenDateSubtitleView");

    Class dateClass =
        NSClassFromString(@"SBFLockScreenDateSubtitleDateView");

    for (UIView *view in clockView.subviews) {
        BOOL isSubtitle =
            subtitleClass && [view isKindOfClass:subtitleClass];

        BOOL isDate =
            dateClass && [view isKindOfClass:dateClass];

        CALayer *presentation = (CALayer *)view.layer.presentationLayer;
        CGFloat visibleAlpha = presentation ? presentation.opacity : view.alpha;
        if (isSubtitle && !isDate && !view.hidden &&
            (view.alpha > 0.01 || visibleAlpha > 0.01)) {
            return YES;
        }
    }

    return NO;
}

// The battery artwork can outlive its status subtitle during the final fade.
// Keep a short settling interval after the last visible subtitle frame.
static BOOL NCStatusSubtitleVisible(UIView *clockView) {
    // The host's content fade starts before the charging subtitle is visible.
    // Its target alpha is available synchronously, before Core Animation draws
    // the battery. Do not wait for the subtitle's presentation layer to catch up.
    NSNumber *contentAlpha = objc_getAssociatedObject(clockView, &NCContentAlphaKey);
    BOOL systemHidingClock = contentAlpha && contentAlpha.doubleValue < 0.999;
    if (systemHidingClock || NCRawStatusSubtitleVisible(clockView)) {
        NSNumber *existingDeadline = objc_getAssociatedObject(clockView, &NCStatusReturnDeadlineKey);
        CFTimeInterval deadline = MAX(existingDeadline.doubleValue, CACurrentMediaTime() + 0.25);
        objc_setAssociatedObject(clockView, &NCStatusReturnDeadlineKey,
            @(deadline), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return YES;
    }
    NSNumber *deadline = objc_getAssociatedObject(clockView, &NCStatusReturnDeadlineKey);
    NSTimeInterval remaining = deadline.doubleValue - CACurrentMediaTime();
    if (!deadline || remaining <= 0) return NO;
    // A layout pass is not guaranteed when this interval expires. Queue one
    // independently of the display link, so an idle clock can return by itself.
    NSNumber *scheduled = objc_getAssociatedObject(clockView, &NCStatusReturnScheduledKey);
    if (![scheduled isEqualToNumber:deadline]) {
        objc_setAssociatedObject(clockView, &NCStatusReturnScheduledKey, deadline,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        __weak UIView *weakHost = clockView;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
            (int64_t)((remaining + 0.01) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *host = weakHost;
            if (!host || ![objc_getAssociatedObject(host, &NCStatusReturnScheduledKey)
                          isEqualToNumber:deadline]) return;
            objc_setAssociatedObject(host, &NCStatusReturnScheduledKey, nil,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            if (!host.window) return;
            [UIView performWithoutAnimation:^{
                [host setNeedsLayout];
                [host layoutIfNeeded];
            }];
        });
    }
    return YES;
}

// Only the legacy layout places its date below the clock. Preserve the
// system transform so size/offset changes never accumulate a date shift.
static char NCDatePlacementKey;
@interface NCDatePlacement : NSObject
@property(nonatomic) CGAffineTransform original;
@property(nonatomic) CGAffineTransform applied;
@end
@implementation NCDatePlacement
@end

static void NCRestoreDatePlacement(UIView *date) {
    NCDatePlacement *placement = objc_getAssociatedObject(date, &NCDatePlacementKey);
    if (placement && CGAffineTransformEqualToTransform(date.transform, placement.applied)) {
        [UIView performWithoutAnimation:^{ date.transform = placement.original; }];
    }
    if (date) objc_setAssociatedObject(date, &NCDatePlacementKey, nil,
                                      OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void NCPlaceLegacyDate(UIView *host, UIView *date, NCClockState *state) {
    Class legacyDate = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
    if (!NCEnabled || NCHideDate || !legacyDate ||
        ![date isKindOfClass:legacyDate] || !date.superview ||
        date.hidden || !state.overlay || state.overlay.hidden) return;
    // A model alpha of zero can still have visible presentation frames during
    // a system fade. Keep the date below the digits throughout that fade.
    CGRect digits = CGRectNull;
    for (UIImageView *glyphView in state.views) {
        if (glyphView.hidden || !glyphView.image) continue;
        CGRect rect = [date.superview convertRect:glyphView.bounds fromView:glyphView];
        digits = CGRectUnion(digits, rect);
    }
    if (CGRectIsNull(digits) || CGRectIsEmpty(digits)) return;
    CGRect dateRect = [date.superview convertRect:date.bounds fromView:date];
    CGFloat shift = MAX(0, CGRectGetMaxY(digits) + 8.0 - CGRectGetMinY(dateRect));
    if (!isfinite(shift) || shift <= 0.01) return;
    NCDatePlacement *placement = [NCDatePlacement new];
    placement.original = date.transform;
    CGAffineTransform transform = placement.original;
    transform.ty += shift;
    placement.applied = transform;
    objc_setAssociatedObject(date, &NCDatePlacementKey, placement,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [UIView performWithoutAnimation:^{ date.transform = transform; }];
}

@protocol NCDateFontHost <NSObject>
@property(nonatomic,strong) UIFont *font;
@end
@interface NCDateFontState : NSObject
@property(nonatomic,strong) UIFont *original;
@property(nonatomic,strong) UIFont *applied;
@property(nonatomic,strong) NSAttributedString *originalText;
@property(nonatomic,strong) NSAttributedString *appliedText;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger attempts;
@end
@implementation NCDateFontState
@end
static char NCDateFontStateKey;
static void NCStyleDateTree(UIView *date, BOOL allowCustom) {
    if (!date) return;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:date]; NSUInteger visited=0;
    while (pending.count && visited++<64) {
        UIView *view=pending.lastObject; [pending removeLastObject];
        [pending addObjectsFromArray:view.subviews];
        Class cls=object_getClass(view);
        if (!NCMethodHasABI(cls,@selector(font),"@",@[]) || !NCMethodHasABI(cls,@selector(setFont:),"v",@[@"@"])) continue;
        id<NCDateFontHost> label=(id)view; UIFont *current=label.font;
        if (![current isKindOfClass:UIFont.class]) continue;
        NCDateFontState *state=objc_getAssociatedObject(view,&NCDateFontStateKey);
        BOOL custom=allowCustom && !NCDateStyleIsSystem(NCDateStyle);
        UILabel *textLabel=[view isKindOfClass:UILabel.class] ? (UILabel *)view : nil;
        if (!custom) {
            BOOL restoreText=state.appliedText && [textLabel.attributedText isEqual:state.appliedText];
            if (state && [current isEqual:state.applied]) label.font=state.original;
            if (restoreText) textLabel.attributedText=state.originalText;
            objc_setAssociatedObject(view,&NCDateFontStateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); continue;
        }
        if (!state) {state=[NCDateFontState new];state.original=current;objc_setAssociatedObject(view,&NCDateFontStateKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
        NSAttributedString *currentText=textLabel.attributedText;
        NSAttributedString *baseText=(state.appliedText && [currentText isEqual:state.appliedText]) ? state.originalText : currentText;
        if (state.generation!=NCGeneration || (baseText.length && ![baseText.string isEqual:state.originalText.string])) {state.generation=NCGeneration;state.attempts=0;}
        // Bound retries when another tweak/the system repeatedly rewrites a font.
        // Leave the native label alone rather than causing endless layout passes.
        if (state.attempts>=4) continue;
        if (![current isEqual:state.applied]) state.original=current;
        UIFont *font=NCDateFont(NCDateStyle,state.original);
        if (![current isEqual:font]) {state.attempts++;label.font=font;}
        state.applied=font;
        if (baseText.length) {
            state.originalText=[baseText copy]; NSMutableAttributedString *styled=[baseText mutableCopy];
            [styled addAttribute:NSFontAttributeName value:font range:NSMakeRange(0,styled.length)];
            if (![textLabel.attributedText isEqual:styled]) {state.attempts++;textLabel.attributedText=styled;}
            state.appliedText=styled;
        } else {state.originalText=nil;state.appliedText=nil;}
    }
}

static void NCLayoutClock(UIView *self, UIView *timeLabel, UIView *dateLabel, NSDate *providedDate, BOOL modern) {
    NCStart();
    NCStyleDateTree(dateLabel, NCEnabled);
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
    BOOL statusVisible = NO;
    if (modern) {
        NSNumber *saved=objc_getAssociatedObject(self,&NCDateAlphaKey);
        if (NCEnabled && NCHideDate && dateLabel) {
            if (!saved) objc_setAssociatedObject(self,&NCDateAlphaKey,@(dateLabel.alpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            dateLabel.alpha=0;
        } else if (saved) {
            dateLabel.alpha=saved.doubleValue;
            objc_setAssociatedObject(self,&NCDateAlphaKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } else {
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

    statusVisible = NCEnabled && NCStatusSubtitleVisible(self);
    BOOL suppressDate = NCEnabled && (NCHideDate || statusVisible);
    // Hide the date before restoring its custom position. Otherwise its
    // presentation layer can show a frame at the system position during a fade.
    if (suppressDate) {
        [UIView performWithoutAnimation:^{
            [dateLabel.layer removeAnimationForKey:@"opacity"];
            dateLabel.alpha = 0;
        }];
    }
    NCRestoreDatePlacement(dateLabel);
    if (!suppressDate) dateLabel.alpha = systemDateAlpha;
    }
    if (statusVisible) {
        [UIView performWithoutAnimation:^{
            [timeLabel.layer removeAnimationForKey:@"opacity"];
            [dateLabel.layer removeAnimationForKey:@"opacity"];
            timeLabel.alpha = 0;
            dateLabel.alpha = 0;
            state.overlay.hidden = YES;
        }];
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

    NSString *pack = NCPack;
    if (modern && NCWallpaperBindings.count) {
        static NSString *selected;
        static NSTimeInterval lastRead;
        NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
        if (!lastRead || now - lastRead >= 0.25) {
            selected = NCSelectedWallpaper();
            lastRead = now;
        }
        if (selected) pack = NCWallpaperBindings[selected] ?: NCPack;
    }
    NSString *time = NCTime(date ?: NSDate.date);
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%@|%lu|%d", pack, time,
        NSStringFromCGRect(timeLabel.frame), NSStringFromCGRect(self.bounds), (unsigned long)NCGeneration, wanted];
    if (state && [state.signature isEqual:signature] && !state.overlay.hidden) {
        // Core Animation can discard animations while the lock screen is detached.
        for (UIImageView *view in state.views) {
            NCGlyph *glyph = objc_getAssociatedObject(view, &NCGlyphKey);
            if (!view.hidden && glyph) NCSetGlyph(view, glyph, state.animated);
        }
        timeLabel.alpha = 0;
        NCPlaceLegacyDate(self, dateLabel, state);
        return;
    }
    NSString *folder = NCFolder(wanted, pack);
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
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:state action:@selector(cycleFavorite:)];
        tap.numberOfTapsRequired=2; tap.cancelsTouchesInView=NO;
        tap.delaysTouchesBegan=NO; tap.delaysTouchesEnded=NO; tap.delegate=state;
        state.favoriteTap=tap; [self addGestureRecognizer:tap];
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
    NCPlaceLegacyDate(self, dateLabel, state);
    NCUpdateSecondsTimer();
}

%group NCLegacyClock
%hook SBFLockScreenDateView
- (void)layoutSubviews {
    NCPerformGuarded(self,&NCLayoutInProgressKey, ^{
    %orig;
    UIView *timeLabel = nil, *dateLabel = nil;
    Class timeClass = NSClassFromString(@"SBUILegibilityLabel"), dateClass = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
    for (UIView *view in self.subviews) {
        if (timeClass && [view isKindOfClass:timeClass]) timeLabel = view;
        if (dateClass && [view isKindOfClass:dateClass]) dateLabel = view;
    }
    // Allow the renderer to restore the system label if a pack cannot load.
    if (timeLabel) objc_setAssociatedObject(timeLabel, &NCLegacyTimeSuppressionKey, nil,
                                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NCLayoutClock(self, timeLabel, dateLabel, self.date, NO);
    NCClockState *state = objc_getAssociatedObject(self, &NCStateKey);
    BOOL replacingTime = NCEnabled &&
        ((state.signature && !state.overlay.hidden) || NCStatusSubtitleVisible(self));
    if (replacingTime && timeLabel) {
        objc_setAssociatedObject(timeLabel, &NCLegacyTimeSuppressionKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [UIView performWithoutAnimation:^{
            [timeLabel.layer removeAnimationForKey:@"opacity"];
            timeLabel.alpha = 0;
        }];
    }

    });
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
            for (UIImageView *view in state.views) NCFreezeView(view);
            state.signature = nil;
        } else {
            NCRequestClockLayout(self);
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
    NSNumber *previousAlpha = objc_getAssociatedObject(self, &NCContentAlphaKey);
    if (NCEnabled && previousAlpha && previousAlpha.doubleValue < 0.999 && alpha >= 0.999) {
        // The model alpha reaches one at the START of the return crossfade.
        // Wait for the enclosing UIKit/Core Animation duration before revealing
        // our replacement. Do not mistake the target value for completion.
        NSTimeInterval duration = UIView.inheritedAnimationDuration;
        if (duration <= 0) duration = CATransaction.animationDuration;
        if (!isfinite(duration) || duration < 0) duration = 0;
        duration = MIN(duration, 3.0);
        NSNumber *previousDeadline = objc_getAssociatedObject(self, &NCStatusReturnDeadlineKey);
        CFTimeInterval deadline = MAX(previousDeadline.doubleValue,
            CACurrentMediaTime() + MAX(duration, 0.25) + 0.05);
        objc_setAssociatedObject(self, &NCStatusReturnDeadlineKey, @(deadline),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(self, &NCContentAlphaKey, @(alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Hide synchronously before %orig starts the system battery crossfade.
    // Applying an alpha inside that transaction would fade our artwork over it.
    if (NCEnabled && alpha < 0.999) {
        NCClockState *clockState = objc_getAssociatedObject(self, &NCStateKey);
        Class timeClass = NSClassFromString(@"SBUILegibilityLabel");
        Class subtitleDateClass = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
        [UIView performWithoutAnimation:^{
            [clockState.overlay.layer removeAnimationForKey:@"opacity"];
            clockState.overlay.alpha = 0;
            clockState.overlay.hidden = YES;
            for (UIView *child in self.subviews) {
                BOOL time = timeClass && [child isKindOfClass:timeClass];
                BOOL date = subtitleDateClass && [child isKindOfClass:subtitleDateClass];
                if (!time && !date) continue;
                if (time) objc_setAssociatedObject(child, &NCLegacyTimeSuppressionKey,
                    @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [child.layer removeAnimationForKey:@"opacity"];
                child.alpha = 0;
            }
        }];
        clockState.signature = nil;
    }
    Class dateClass = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
    BOOL hideDateForTransition = NCEnabled &&
        (NCHideDate || !subtitleVisible || NCStatusSubtitleVisible(self));
    if (hideDateForTransition) {
        [UIView performWithoutAnimation:^{
            for (UIView *view in self.subviews) {
                if (dateClass && [view isKindOfClass:dateClass]) {
                    [view.layer removeAnimationForKey:@"opacity"];
                    view.alpha = 0;
                }
            }
        }];
    }
    %orig;

    CGFloat systemDateAlpha = subtitleVisible ? alpha : 0;

    objc_setAssociatedObject(
        self,
        &NCDateAlphaKey,
        @(systemDateAlpha),
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );

    for (UIView *view in self.subviews) {
        if (dateClass && [view isKindOfClass:dateClass]) {
            if (hideDateForTransition) {
                [UIView performWithoutAnimation:^{
                    [view.layer removeAnimationForKey:@"opacity"];
                    view.alpha = 0;
                }];
            } else {
                view.alpha = systemDateAlpha;
            }
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

// Scope this shared label class hook to a clock label claimed by our renderer.
// Other legibility labels and missing-pack fallback retain system visibility.
@interface SBUILegibilityLabel : UIView
@end
%group NCLegacyTimeVisibility
%hook SBUILegibilityLabel
- (void)setAlpha:(CGFloat)alpha {
    Class clockClass = NSClassFromString(@"SBFLockScreenDateView");
    if (NCEnabled && clockClass && [self.superview isKindOfClass:clockClass] &&
        [objc_getAssociatedObject(self, &NCLegacyTimeSuppressionKey) boolValue]) {
        alpha = 0;
    }
    %orig(alpha);
}
%end
%end

// A short-lived display link follows the actual subtitle fade. It never
// polls while idle and never changes the system's status subtitle itself.
static char NCStatusTransitionKey;
@interface NCStatusTransition : NSObject
@property(nonatomic, weak) UIView *host;
@property(nonatomic, strong) CADisplayLink *link;
@property(nonatomic) CFTimeInterval started;
@property(nonatomic) BOOL updating;
- (void)refresh;
- (void)stop;
@end

static BOOL NCIsLegacyStatus(UIView *view) {
    Class subtitle = NSClassFromString(@"SBFLockScreenDateSubtitleView");
    Class date = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
    return subtitle && [view isKindOfClass:subtitle] &&
        !(date && [view isKindOfClass:date]);
}

static UIView *NCLegacyStatusHost(UIView *view) {
    Class clock = NSClassFromString(@"SBFLockScreenDateView");
    for (UIView *parent = view.superview; parent; parent = parent.superview) {
        if (clock && [parent isKindOfClass:clock]) return parent;
    }
    return nil;
}

static void NCHideLegacyClockImmediately(UIView *host) {
    if (!NCEnabled || !host) return;
    NCClockState *state = objc_getAssociatedObject(host, &NCStateKey);
    Class timeClass = NSClassFromString(@"SBUILegibilityLabel");
    Class dateClass = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
    if (!objc_getAssociatedObject(host, &NCDateAlphaKey)) {
        for (UIView *child in host.subviews) {
            if (dateClass && [child isKindOfClass:dateClass]) {
                objc_setAssociatedObject(host, &NCDateAlphaKey, @(child.alpha),
                                         OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                break;
            }
        }
    }
    [UIView performWithoutAnimation:^{
        state.overlay.hidden = YES;
        for (UIView *child in host.subviews) {
            if ((timeClass && [child isKindOfClass:timeClass]) ||
                (dateClass && [child isKindOfClass:dateClass])) {
                [child.layer removeAnimationForKey:@"opacity"];
                child.alpha = 0;
            }
        }
    }];
    state.signature = nil;
}

@implementation NCStatusTransition
- (void)stop {
    [self.link invalidate];
    self.link = nil;
}
- (void)refresh {
    if (self.updating) return;
    UIView *host = self.host;
    if (!host || !host.window || !NCEnabled) { [self stop]; return; }
    self.updating = YES;
    NCRequestClockLayout(host);
    self.updating = NO;
}
- (void)tick:(CADisplayLink *)sender {
    [self refresh];
    NSNumber *contentAlpha = objc_getAssociatedObject(self.host, &NCContentAlphaKey);
    if (contentAlpha && contentAlpha.doubleValue < 0.999) {
        [self stop];
        return;
    }
    BOOL transitioning = NO;
    for (UIView *child in self.host.subviews) {
        if (!NCIsLegacyStatus(child) || child.hidden) continue;
        CALayer *visible = (CALayer *)child.layer.presentationLayer;
        if (visible && fabs(visible.opacity - child.alpha) > 0.01) {
            transitioning = YES;
            break;
        }
    }
    // Resource bound only; the normal completion follows presentation opacity.
    BOOL waitingForReturn = !NCRawStatusSubtitleVisible(self.host) &&
        NCStatusSubtitleVisible(self.host);
    if ((!transitioning && !waitingForReturn) || !self.host.window ||
        CACurrentMediaTime() - self.started > 3.0) {
        [self stop];
    }
}
@end

static void NCSubtitleChanged(UIView *view) {
    if (!NCIsLegacyStatus(view)) return;
    UIView *host = NCLegacyStatusHost(view);
    if (!host) return;
    NCStatusTransition *transition = objc_getAssociatedObject(host, &NCStatusTransitionKey);
    if (!transition) {
        transition = [NCStatusTransition new];
        transition.host = host;
        objc_setAssociatedObject(host, &NCStatusTransitionKey, transition,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (transition.updating) return;
    [transition refresh];
    if (NCEnabled && host.window && !transition.link) {
        transition.started = CACurrentMediaTime();
        transition.link = [CADisplayLink displayLinkWithTarget:transition selector:@selector(tick:)];
        [transition.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}

%group NCStatusSubtitleUpdates
%hook SBFLockScreenDateSubtitleView
- (void)setAlpha:(CGFloat)alpha {
    BOOL changed = self.alpha != alpha;
    if (changed && alpha > 0.01 && !self.hidden && NCIsLegacyStatus(self)) {
        NCHideLegacyClockImmediately(NCLegacyStatusHost(self));
    }
    %orig;
    if (changed) NCSubtitleChanged(self);
}
- (void)setHidden:(BOOL)hidden {
    BOOL changed = self.hidden != hidden;
    if (changed && !hidden && self.alpha > 0.01 && NCIsLegacyStatus(self)) {
        NCHideLegacyClockImmediately(NCLegacyStatusHost(self));
    }
    %orig;
    if (changed) NCSubtitleChanged(self);
}
- (void)willMoveToSuperview:(UIView *)newSuperview {
    __weak UIView *oldHost = NCIsLegacyStatus(self) ? NCLegacyStatusHost(self) : nil;
    %orig;
    if (oldHost && newSuperview != self.superview) {
        dispatch_async(dispatch_get_main_queue(), ^{
            UIView *host = oldHost;
            if (!host || !host.window) return;
            [UIView performWithoutAnimation:^{
                [host setNeedsLayout];
                [host layoutIfNeeded];
            }];
        });
    }
}
- (void)didMoveToSuperview {
    %orig;
    NCSubtitleChanged(self);
}
%end
%end


// The system can animate the date directly after the host's layout pass.
// Enforce hiding on that specific view, before UIKit creates its fade animation.
@interface SBFLockScreenDateSubtitleDateView : UIView
@end

static BOOL NCShouldSuppressLegacyDate(UIView *view) {
    UIView *host = NCLegacyStatusHost(view);
    return host && NCEnabled && (NCHideDate || NCStatusSubtitleVisible(host));
}

%group NCLegacyDateVisibility
%hook SBFLockScreenDateSubtitleDateView
- (void)setAlpha:(CGFloat)alpha {
    if (NCShouldSuppressLegacyDate(self)) alpha = 0;
    %orig(alpha);
}
- (void)layoutSubviews {
    %orig;
    if (NCShouldSuppressLegacyDate(self)) {
        [UIView performWithoutAnimation:^{
            [self.layer removeAnimationForKey:@"opacity"];
            self.alpha = 0;
        }];
    }
}
%end
%end


// Experimental adapter: selector names verified only against an upstream iOS 18
// class dump. Runtime availability checks do not establish iOS 16/17 compatibility.
static char NCModernDisplayDateKey;
static char NCModernSuppressTimeKey;
static char NCModernRequestedAlphaKey, NCModernOwnAlphaWriteKey, NCModernDateKey, NCModernOwnerKey;
@interface NCModernOwner : NSObject
@property(nonatomic,weak) UIView *host;
@end
@implementation NCModernOwner
@end
static void NCModernFollowSystemAlpha(UIView *time, CGFloat alpha) {
    NCModernOwner *owner=objc_getAssociatedObject(time,&NCModernOwnerKey);
    UIView *host=owner.host;
    if (!host || !NCEnabled) return;
    NCClockState *state=objc_getAssociatedObject(host,&NCStateKey);
    // Executed in the same UIKit transaction as the native time alpha setter.
    // No guessed charging duration and no delayed reveal.
    state.overlay.alpha=NCModernVisibleAlpha(alpha);
    objc_setAssociatedObject(host,&NCContentAlphaKey,@(NCModernVisibleAlpha(alpha)),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}


// The native time view remains in its hierarchy. Only a renderer that owns it
// may suppress it; remember system alpha requests for exact hand-back.
static void NCModernSetTimeAlpha(UIView *time, CGFloat alpha) {
    if (!time) return;
    objc_setAssociatedObject(time,&NCModernOwnAlphaWriteKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { time.alpha=alpha; }
    @finally { objc_setAssociatedObject(time,&NCModernOwnAlphaWriteKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}
static void NCModernClaimTime(UIView *time) {
    if (!objc_getAssociatedObject(time,&NCModernRequestedAlphaKey))
        objc_setAssociatedObject(time,&NCModernRequestedAlphaKey,@(time.alpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(time,&NCModernSuppressTimeKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NCModernSetTimeAlpha(time,0);
}
static void NCModernReleaseTime(UIView *time) {
    NSNumber *alpha=objc_getAssociatedObject(time,&NCModernRequestedAlphaKey);
    objc_setAssociatedObject(time,&NCModernSuppressTimeKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (alpha) NCModernSetTimeAlpha(time,alpha.doubleValue);
    objc_setAssociatedObject(time,&NCModernRequestedAlphaKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(time,&NCModernOwnerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL NCModernUsesEditingLayout(UIView *host) {
    SEL selector=NSSelectorFromString(@"usesEditingLayout");
    if (!NCMethodHasABI(object_getClass(host),selector,@encode(BOOL),@[]) &&
        !NCMethodHasABI(object_getClass(host),selector,"c",@[])) return NO;
    BOOL (*read)(id,SEL)=(BOOL (*)(id,SEL))[host methodForSelector:selector];
    return read(host,selector);
}
static BOOL NCModernEditingContext(UIView *host) {
    // Editors can host the same renderer; galleries/snapshots remain native
    // until their separate rendering process and capture lifecycle are verified.
    // Private containers differ by OS. Inspect the responder chain, not label
    // text; unknown container names must be checked on the test device.
    UIResponder *item=host;
    for (NSUInteger i=0;item && i<96;i++,item=item.nextResponder) {
        if (NCModernIsPreviewContainer(NSStringFromClass(item.class))) return YES;
    }
    return NO;
}
static void NCModernReleaseClock(UIView *host, UIView *time) {
    NCModernReleaseTime(time);
    NCClockState *state=objc_getAssociatedObject(host,&NCStateKey);
    state.overlay.hidden=YES; state.signature=nil;
    for (UIImageView *image in state.views) NCClearView(image);
    UIView *date=objc_getAssociatedObject(host,&NCModernDateKey);
    NSNumber *alpha=objc_getAssociatedObject(host,&NCDateAlphaKey);
    if (date && alpha) date.alpha=alpha.doubleValue;
    NCStyleDateTree(date,NO);
    objc_setAssociatedObject(host,&NCDateAlphaKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host,&NCContentAlphaKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(host,&NCModernDateKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NCUpdateSecondsTimer();
}

@interface CSProminentDisplayView : UIView
- (UIView *)timeView;
- (UIView *)subtitleView;
- (UIView *)transientSubtitleView;
@end

#ifdef NC_WALLPAPER_PROBE
// Local probe for the per-wallpaper feature. Follow only explicitly named,
// zero-argument object getters and record UUID fingerprints, never raw IDs.
static void NCProbeWallpaperIdentity(UIView *host) {
    static CFTimeInterval lastProbe;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - lastProbe < 1) return;
    lastProbe = now;
    NSMutableArray *objects = [NSMutableArray array];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSHashTable *seen = [NSHashTable hashTableWithOptions:NSPointerFunctionsObjectPointerPersonality];
    for (UIResponder *item = host; item && objects.count < 32; item = item.nextResponder) {
        [objects addObject:item];
        [paths addObject:NSStringFromClass(item.class)];
        [seen addObject:item];
    }
    NSMutableOrderedSet<NSString *> *results = [NSMutableOrderedSet orderedSet];
    NSArray *links = @[@"wallpaperController", @"wallpaperViewController",
        @"posterController", @"activePosterConfiguration", @"currentPosterConfiguration",
        @"posterConfiguration", @"wallpaperConfiguration", @"configuration", @"descriptor"];
    for (NSUInteger i = 0; i < objects.count && results.count < 32; i++) {
        id object = objects[i];
        NSString *path = paths[i];
        Class cls = object_getClass(object);
        if (i >= 32 || ![object isKindOfClass:UIResponder.class]) {
            for (NSString *name in @[@"uniqueIdentifier", @"identifier", @"UUID", @"configurationIdentifier"]) {
                SEL selector = NSSelectorFromString(name);
                if (!NCMethodHasABI(cls, selector, "@", @[])) continue;
                id (*read)(id, SEL) = (id (*)(id, SEL))[object methodForSelector:selector];
                id value = read(object, selector);
                NSUUID *uuid = [value isKindOfClass:NSUUID.class] ? value :
                    ([value isKindOfClass:NSString.class] && [value length] == 36
                     ? [[NSUUID alloc] initWithUUIDString:value] : nil);
                if (!uuid) continue;
                const char *bytes = uuid.UUIDString.UTF8String;
                unsigned char digest[CC_SHA256_DIGEST_LENGTH];
                CC_SHA256(bytes, (CC_LONG)strlen(bytes), digest);
                NSMutableString *fingerprint = [NSMutableString string];
                for (NSUInteger n = 0; n < 12; n++) [fingerprint appendFormat:@"%02x", digest[n]];
                [results addObject:[NSString stringWithFormat:@"%@.%@ = %@", path, name, fingerprint]];
            }
        }
        for (NSString *name in links) {
            if (objects.count >= 48) break;
            SEL selector = NSSelectorFromString(name);
            if (!NCMethodHasABI(cls, selector, "@", @[])) continue;
            id (*read)(id, SEL) = (id (*)(id, SEL))[object methodForSelector:selector];
            id value = read(object, selector);
            if (!value || [seen containsObject:value]) continue;
            NSString *className = NSStringFromClass(object_getClass(value));
            if (![className containsString:@"Poster"] && ![className containsString:@"Wallpaper"]) continue;
            [seen addObject:value];
            [objects addObject:value];
            [paths addObject:[NSString stringWithFormat:@"%@.%@ (%@)", path, name, className]];
        }
    }
    NSString *sample = results.count ? [[results array] componentsJoinedByString:@"\n"] : @"No UUID candidate found";
    static NSString *previous;
    if ([sample isEqualToString:previous]) return;
    NSString *file = @"/var/mobile/Library/NextClock-wallpaper-probe.txt";
    NSString *history = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] ?: @"";
    if (history.length > 24000) history = @"";
    NSString *entry = [NSString stringWithFormat:@"%@\n--- %@ | PID %d | iOS %@ ---\n%@\n",
        history, NSDate.date, getpid(), UIDevice.currentDevice.systemVersion, sample];
    if ([entry writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:nil]) previous = sample;
}

#endif

static void NCCompatibilitySnapshot(UIView *host) {
    static NSMutableDictionary<NSString *,NSString *> *snapshots;
    static dispatch_queue_t writer;
    if (!snapshots) { snapshots=[NSMutableDictionary dictionary]; writer=dispatch_queue_create("com.ratnik00.nextclock.snapshots",DISPATCH_QUEUE_SERIAL); }
    NSString *mode=NCModernEditingContext(host) ? @"gallery/snapshot" :
        (NCModernUsesEditingLayout(host) ? @"editor" : @"live/unknown");
    if (snapshots[mode]) return;
    NSMutableString *report = [NSMutableString stringWithFormat:@"Context: %@\n", mode];
    UIResponder *responder=host;
    for (NSUInteger i=0;responder && i<48;i++,responder=responder.nextResponder)
        [report appendFormat:@"Responder: %@\n",NSStringFromClass(responder.class)];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:host];
    for (NSUInteger i = 0; i < queue.count && i < 120; i++) {
        UIView *view = queue[i];
        [report appendFormat:@"%@ frame=%@ alpha=%.2f hidden=%d\n", NSStringFromClass(view.class), NSStringFromCGRect(view.frame), view.alpha, view.hidden];
        NSUInteger remaining = 120 - queue.count;
        if (remaining) [queue addObjectsFromArray:[view.subviews subarrayWithRange:
            NSMakeRange(0, MIN(remaining, view.subviews.count))]];
    }
    snapshots[mode]=report.copy;
    NSMutableString *combined=[NSMutableString stringWithFormat:@"NextClock %@\niOS: %@\n",NC_VERSION,UIDevice.currentDevice.systemVersion];
    for (NSString *key in [[snapshots allKeys] sortedArrayUsingSelector:@selector(compare:)])
        [combined appendFormat:@"\n%@\n",snapshots[key]];
    NSString *snapshot = combined.copy;
    dispatch_async(writer, ^{
        [snapshot writeToFile:@"/var/mobile/Library/NextClock-compatibility.txt" atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
}
%group NCModernClock
%hook CSProminentDisplayView
- (void)layoutSubviews {
    NCStart();
    // An untouched, disabled instance must be a straight pass-through.
    UIView *priorTime=self.timeView;
    BOOL managed=objc_getAssociatedObject(self,&NCStateKey)!=nil ||
        objc_getAssociatedObject(self,&NCModernDateKey)!=nil ||
        objc_getAssociatedObject(priorTime,&NCModernRequestedAlphaKey)!=nil;
    if (!NCEnabled && !managed) {
        %orig;
        return;
    }
    NCPerformGuarded(self,&NCLayoutInProgressKey, ^{
    BOOL editing=NCModernEditingContext(self);
    if (!NCEnabled || editing) NCModernReleaseClock(self,priorTime);
    %orig;
    editing=NCModernEditingContext(self);
    if (NCEnabled) NCCompatibilitySnapshot(self);
    if (!NCModernShouldRender(NCEnabled,self.window!=nil,editing)) {
        NCModernReleaseClock(self,self.timeView);
        return;
    }
#ifdef NC_WALLPAPER_PROBE
    if (!NCModernUsesEditingLayout(self)) NCProbeWallpaperIdentity(self);
#endif
    UIView *time = self.timeView;
    if (priorTime!=time) NCModernReleaseTime(priorTime);
    if (![time isKindOfClass:UIView.class] || ![time isDescendantOfView:self]) {
        NCModernReleaseClock(self,priorTime);
        return;
    }
    UIView *subtitle = self.subtitleView;
    Class dateClass = NSClassFromString(@"CSProminentSubtitleDateView");
    UIView *date = dateClass && [subtitle isKindOfClass:dateClass] ? subtitle : nil;
    UIView *oldDate=objc_getAssociatedObject(self,&NCModernDateKey);
    if (oldDate && oldDate!=date) {
        NSNumber *alpha=objc_getAssociatedObject(self,&NCDateAlphaKey);
        if (alpha) oldDate.alpha=alpha.doubleValue;
        NCStyleDateTree(oldDate,NO);
        objc_setAssociatedObject(self,&NCDateAlphaKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    objc_setAssociatedObject(self,&NCModernDateKey,date,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Keep owned native text suppressed through live layout. Restoring it on
    // every pass could itself create a stock-clock opacity animation.
    // A charging subtitle can legitimately coexist with the clock. Only the
    // native time view's visibility determines whether our digits fade out.
    NSDate *displayDate =
        objc_getAssociatedObject(self, &NCModernDisplayDateKey);

    NSNumber *savedAlpha=objc_getAssociatedObject(time,&NCModernRequestedAlphaKey);
    CGFloat requestedAlpha=NCModernVisibleAlpha(savedAlpha ? savedAlpha.doubleValue : time.alpha);
    objc_setAssociatedObject(self,&NCContentAlphaKey,@(requestedAlpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(time,&NCModernOwnAlphaWriteKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { NCLayoutClock(self, time, date, displayDate ?: [NSDate date], YES); }
    @finally { objc_setAssociatedObject(time,&NCModernOwnAlphaWriteKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NCClockState *rendered = objc_getAssociatedObject(self, &NCStateKey);
    // Editing a wallpaper must not cycle global favorites via double tap.
    rendered.favoriteTap.enabled=!NCModernUsesEditingLayout(self);
    BOOL replacingTime = NCEnabled && rendered.overlay &&
        rendered.overlay.superview == self && !rendered.overlay.hidden;
    if (replacingTime) {
        // NCLayoutClock has already hidden the view; retain the pre-render value.
        objc_setAssociatedObject(time,&NCModernRequestedAlphaKey,@(requestedAlpha),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NCModernOwner *owner=[NCModernOwner new]; owner.host=self;
        objc_setAssociatedObject(time,&NCModernOwnerKey,owner,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NCModernClaimTime(time);
    } else {
        NCModernReleaseTime(time);
    }

    });
}
- (void)setDisplayDate:(NSDate *)date {
    objc_setAssociatedObject(
        self,
        &NCModernDisplayDateKey,
        date,
        OBJC_ASSOCIATION_COPY_NONATOMIC
    );

    %orig;
    if (NCEnabled) [self setNeedsLayout];
}
- (void)didMoveToWindow {
    %orig;
    NCClockState *state = objc_getAssociatedObject(self, &NCStateKey);
    if (!self.window) {
        for (UIImageView *image in state.views) NCFreezeView(image);
        state.signature = nil;
    } else if (NCEnabled) {
        NCRequestClockLayout(self);
    }
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
    BOOL ownWrite=[objc_getAssociatedObject(self,&NCModernOwnAlphaWriteKey) boolValue];
    if (!ownWrite && objc_getAssociatedObject(self,&NCModernRequestedAlphaKey)) {
        objc_setAssociatedObject(self,&NCModernRequestedAlphaKey,@(NCModernVisibleAlpha(alpha)),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NCModernFollowSystemAlpha(self,alpha);
    }
    BOOL suppress = NCEnabled &&
        [objc_getAssociatedObject(self, &NCModernSuppressTimeKey) boolValue];
    %orig(suppress ? 0 : alpha);
}
- (void)layoutSubviews {
    %orig;
    if (NCEnabled &&
        [objc_getAssociatedObject(self, &NCModernSuppressTimeKey) boolValue]) {
        NCModernSetTimeAlpha(self,0);
    }
}
%end
%end

// Re-evaluate the overlay when transient system subtitles change.
%group NCModernSubtitleUpdates
%hook CSProminentDisplayView
- (void)setSubtitleAlpha:(CGFloat)alpha {
    %orig;
    if (NCEnabled) NCRequestClockLayout(self);
}
- (void)setTransientSubtitleView:(UIView *)view {
    %orig;
    if (NCEnabled) NCRequestClockLayout(self);
}
%end
%end

%ctor {
    @autoreleasepool {
        Class modernClass = NSClassFromString(@"CSProminentDisplayView");
        BOOL modern = UIDevice.currentDevice.systemVersion.doubleValue >= 16 && modernClass &&
            NCMethodHasABI(modernClass, @selector(timeView), "@", @[]) &&
            NCMethodHasABI(modernClass, @selector(subtitleView), "@", @[]) &&
            NCMethodHasABI(modernClass, @selector(setDisplayDate:), "v", @[@"@"]);
        Class legacyClass = NSClassFromString(@"SBFLockScreenDateView");
        BOOL legacy = legacyClass && [legacyClass isSubclassOfClass:UIView.class] &&
            class_getInstanceMethod(legacyClass, @selector(layoutSubviews)) &&
            NCMethodHasABI(legacyClass, @selector(date), "@", @[]) &&
            NCMethodHasABI(legacyClass, @selector(setDate:), "v", @[@"@"]);
        NSMutableString *startupReport = [NSMutableString stringWithFormat:
            @"NextClock %@\niOS: %@\nAdapter: %@\n",
            NC_VERSION, UIDevice.currentDevice.systemVersion, modern ? @"prominent (experimental)" : (legacy ? @"legacy" : @"none; required classes unavailable")];
        for (NSString *name in @[@"SBFLockScreenDateView", @"CSProminentDisplayView", @"CSProminentTimeView", @"CSProminentSubtitleDateView"]) {
            [startupReport appendFormat:@"%@: %@\n", name, NSClassFromString(name) ? @"present" : @"absent"];
        }
        [startupReport appendString:@"\nLegacy adapter methods:\n"];
        for (NSString *name in @[@"date", @"setDate:", @"layoutSubviews",
                                @"setContentAlpha:withSubtitleVisible:"]) {
            BOOL present = legacyClass && class_getInstanceMethod(legacyClass, NSSelectorFromString(name));
            [startupReport appendFormat:@"%@: %@\n", name, present ? @"present" : @"absent"];
        }
#ifdef NC_LEGACY_BUILD
        [startupReport appendString:@"Build: experimental rootful; iOS 12-14 device testing pending\n"];
#endif
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
        [startupReport appendFormat:@"\nVisibility method ABI compatible: %@\nLayout safety: guarded; subtitle/window callbacks coalesced\n",
            NCMethodHasABI(legacyClass,@selector(setContentAlpha:withSubtitleVisible:),"v",@[@(@encode(CGFloat)),@"BOOL"]) ? @"yes" : @"no; hook skipped"];
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
                NCMethodHasABI(modernClass, @selector(setSubtitleAlpha:), "v", @[@(@encode(CGFloat))]) &&
                NCMethodHasABI(modernClass, @selector(setTransientSubtitleView:), "v", @[@"@"]);
            if (subtitleUpdatesAvailable) {
                %init(NCModernSubtitleUpdates);
            }
            NSLog(@"[NextClock] Experimental modern adapter selected; runtime testing required");
        } else if (legacy) {
            %init(NCLegacyClock);
        } else {
            NSLog(@"[NextClock] No compatible clock adapter; keeping system clock");
        }
        Class statusClass=NSClassFromString(@"SBFLockScreenDateSubtitleView");
        if (!modern && legacy && statusClass && [statusClass isSubclassOfClass:UIView.class] &&
            class_getInstanceMethod(statusClass,@selector(setAlpha:)) &&
            class_getInstanceMethod(statusClass,@selector(setHidden:)) &&
            class_getInstanceMethod(statusClass,@selector(willMoveToSuperview:)) &&
            class_getInstanceMethod(statusClass,@selector(didMoveToSuperview))) {
            %init(NCStatusSubtitleUpdates);
        }
        Class legacyTimeClass = NSClassFromString(@"SBUILegibilityLabel");
        if (!modern && legacy && legacyTimeClass &&
            [legacyTimeClass isSubclassOfClass:UIView.class]) {
            %init(NCLegacyTimeVisibility);
        }
        Class legacyDateClass = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
        if (!modern && legacy && legacyDateClass &&
            [legacyDateClass isSubclassOfClass:UIView.class]) {
            %init(NCLegacyDateVisibility);
        }
        Class dateClass = NSClassFromString(@"SBFLockScreenDateView");
        SEL selector = @selector(setContentAlpha:withSubtitleVisible:);
        if (!modern && legacy && NCMethodHasABI(dateClass, selector, "v", @[@(@encode(CGFloat)),@"BOOL"])) {
            %init(NCSystemClockVisibility);
        } else {
            NSLog(@"[NextClock] System clock visibility method unavailable on this iOS version");
        }
    }
}
