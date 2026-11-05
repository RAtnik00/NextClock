#import <Foundation/Foundation.h>
#import <math.h>

// Live and editor hosts share the renderer. Gallery/snapshot hosts stay native.
static inline BOOL NCModernShouldRender(BOOL enabled, BOOL attached, BOOL preview) {
    return enabled && attached && !preview;
}
static inline double NCModernVisibleAlpha(double alpha) {
    return isfinite(alpha) ? fmax(0,fmin(1,alpha)) : 0;
}
static inline BOOL NCModernIsPreviewContainer(NSString *name) {
    for (NSString *part in @[@"PosterSwitcher",@"PosterPreview",@"PosterGallery",@"WallpaperPicker",@"Snapshot"])
        if ([name rangeOfString:part options:NSCaseInsensitiveSearch].location!=NSNotFound) return YES;
    return NO;
}
