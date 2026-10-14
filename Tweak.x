#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ImageIO/ImageIO.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>
#import <stdlib.h>
#import <math.h>
#import "Shared/NCPacks.h"

// iOS 15 implementation. All rendering and settings changes run on the main thread.
static BOOL NCEnabled = YES, NCHideDate = NO, NCAnimated = YES, NCStillLowPower = NO, NCTint = NO;
static CGFloat NCScale = 1, NCSpacing = -2, NCOffset = 0, NCSpeed = 1;
static NSString *NCPack = @"Anime", *NCFormat = @"system", *NCColorHex = @"#FF9500";
static NSHashTable<UIView *> *NCViews;
static NSCache *NCImages;
static NSUInteger NCGeneration = 1;
static NSString *NCResolvedFolder;
static BOOL NCResolvedWanted;
static BOOL NCStarted = NO;
static CFTimeInterval NCEpoch = 0;
static char NCStateKey, NCGlyphKey;

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
static NCGlyph *NCDecode(NSString *path, BOOL animate) {
    NSString *key = [NSString stringWithFormat:@"%@|%d|%d|%@", path, animate, NCTint, NCColorHex];
    NCGlyph *cached = [NCImages objectForKey:key]; if (cached) return cached;
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
            if (bytes > 96 * 1024 * 1024 || cost > 96 * 1024 * 1024 - bytes) {
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
            seconds = MAX(.01, seconds); [durations addObject:@(seconds)]; total += seconds;
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
    formatter.dateFormat = use24 ? @"HH:mm" : @"h:mm";
    formatter.timeZone = NSTimeZone.localTimeZone; return [formatter stringFromDate:date];
}
static void NCRefreshViews(void) {
    for (UIView *view in NCViews.allObjects) [view setNeedsLayout];
}
static void NCPreferencesChanged(CFNotificationCenterRef c, void *o, CFStringRef n, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ NCLoadSettings(); NCRefreshViews(); });
}
static void NCRespring(CFNotificationCenterRef c, void *o, CFStringRef n, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ exit(0); });
}
static void NCStart(void) {
    if (NCStarted) return; NCStarted = YES;
    NCViews = [NSHashTable weakObjectsHashTable]; NCImages = [NSCache new]; NCImages.totalCostLimit = 36 * 1024 * 1024;
    NCLoadSettings();
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

%hook SBFLockScreenDateView
- (void)layoutSubviews {
    %orig;
    NCStart(); [NCViews addObject:self];
    UIView *timeLabel = nil, *dateLabel = nil;
    Class timeClass = NSClassFromString(@"SBUILegibilityLabel"), dateClass = NSClassFromString(@"SBFLockScreenDateSubtitleDateView");
    for (UIView *view in self.subviews) {
        if (timeClass && [view isKindOfClass:timeClass]) timeLabel = view;
        if (dateClass && [view isKindOfClass:dateClass]) dateLabel = view;
    }
    if (!timeLabel) return;
    dateLabel.alpha = NCEnabled && NCHideDate ? 0 : 1;
    NCClockState *state = objc_getAssociatedObject(self, &NCStateKey);
    if (!NCEnabled) {
        timeLabel.alpha = 1; state.overlay.hidden = YES; state.signature = nil;
        for (UIImageView *view in state.views) NCClearView(view);
        return;
    }
    BOOL wanted = NCWantsAnimation();
    NSDate *date = [self respondsToSelector:@selector(date)] ? [self date] : nil;
    NSString *time = NCTime(date ?: NSDate.date);
    NSString *signature = [NSString stringWithFormat:@"%@|%@|%@|%lu|%d", time,
        NSStringFromCGRect(timeLabel.frame), NSStringFromCGRect(self.bounds), (unsigned long)NCGeneration, wanted];
    if (state && [state.signature isEqual:signature] && !state.overlay.hidden) { timeLabel.alpha = 0; return; }
    NSString *folder = NCFolder(wanted);
    NSMutableArray<NCGlyph *> *glyphs = [NSMutableArray array];
    for (NSUInteger i = 0; folder && i < time.length; i++) {
        NSString *symbol = [time substringWithRange:NSMakeRange(i, 1)];
        NSString *name = [symbol isEqual:@":"] ? @"colon" : symbol;
        NSString *path = NCGlyphPath(folder, name);
        NCGlyph *glyph = path ? NCDecode(path, wanted) : nil;
        if (!glyph) { [glyphs removeAllObjects]; break; } [glyphs addObject:glyph];
    }
    if (!glyphs.count) {
        timeLabel.alpha = 1; state.overlay.hidden = YES; state.signature = nil;
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
        state.overlay.hidden = YES; timeLabel.alpha = 1; state.signature = nil;
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
    timeLabel.alpha = 0; state.signature = signature;
}
- (void)setDate:(NSDate *)date {
    %orig;
    [self setNeedsLayout];
}
- (void)didMoveToWindow {
    %orig;
    NCClockState *state = objc_getAssociatedObject(self, &NCStateKey);
    if (!self.window) { for (UIImageView *view in state.views) NCClearView(view); state.signature = nil; }
    else [self setNeedsLayout];
}
%end
%ctor { @autoreleasepool { %init; } }
