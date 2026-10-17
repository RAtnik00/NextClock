#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <rootless.h>

static inline NSString *NCUserRoot(void) { return @"/var/mobile/Library/NextClock/Packs"; }
static inline NSString *NCBuiltinRoot(void) { return ROOT_PATH_NS(@"/Library/Application Support/NextClock/Packs"); }
static inline NSArray<NSString *> *NCGlyphNames(void) {
    return @[@"0", @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"colon"];
}
static inline BOOL NCValidIdentifier(NSString *name) {
    return [name isKindOfClass:NSString.class] && name.length &&
        ![name isEqual:@"."] && ![name isEqual:@".."] &&
        [name rangeOfString:@"/"].location == NSNotFound && ![name hasPrefix:@"."];
}
static inline NSError *NCError(NSString *message) {
    return [NSError errorWithDomain:@"NextClock" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static inline BOOL NCRegularFile(NSString *path) {
    NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    return [a[NSFileType] isEqual:NSFileTypeRegular];
}
static inline NSString *NCGlyphPath(NSString *folder, NSString *name) {
    for (NSString *ext in @[@"gif", @"png"]) {
        NSString *p = [folder stringByAppendingPathComponent:[name stringByAppendingPathExtension:ext]];
        if (NCRegularFile(p)) return p;
    }
    return nil;
}
static inline BOOL NCImageValid(NSString *path, BOOL deep) {
    if (!NCRegularFile(path)) return NO;
    NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if ([a[NSFileSize] unsignedLongLongValue] > 8 * 1024 * 1024) return NO;
    CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!src) return NO;
    size_t n = CGImageSourceGetCount(src);
    if (!n) { CFRelease(src); return NO; }
    NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, 0, NULL));
    NSUInteger w = [props[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    NSUInteger h = [props[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    BOOL ok = n > 0 && n <= 240 && w > 0 && h > 0 && w <= 2048 && h <= 2048 &&
        (uint64_t)w * h * 4 * n <= 96 * 1024 * 1024;
    if (ok) {
        uint64_t total = 0;
        for (size_t i = 0; i < n; i++) {
            @autoreleasepool {
                NSDictionary *frameProps = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(src, i, NULL));
                NSUInteger fw = [frameProps[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
                NSUInteger fh = [frameProps[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
                if (!fw || !fh || fw > 2048 || fh > 2048) { ok = NO; break; }
                total += (uint64_t)fw * fh * 4;
                if (total > 96 * 1024 * 1024) { ok = NO; break; }
                if (deep) {
                    CGImageRef frame = CGImageSourceCreateImageAtIndex(src, i, NULL);
                    if (!frame) { ok = NO; break; }
                    CGImageRelease(frame);
                }
            }
        }
    }
    CFRelease(src);
    return ok;
}
static inline BOOL NCCompleteVariant(NSString *folder, BOOL deep) {
    NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:folder error:nil];
    if (![a[NSFileType] isEqual:NSFileTypeDirectory]) return NO;
    for (NSString *glyph in NCGlyphNames()) {
        NSString *p = NCGlyphPath(folder, glyph);
        if (!p || !NCImageValid(p, deep)) return NO;
    }
    return YES;
}
static inline NSDictionary *NCPackInfo(NSString *path, NSString *identifier, BOOL user, BOOL deep) {
    NSDictionary *a = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
    if (![a[NSFileType] isEqual:NSFileTypeDirectory]) return nil;
    NSMutableArray *variants = [NSMutableArray array];
    for (NSString *v in @[@"static", @"animated"]) {
        if (NCCompleteVariant([path stringByAppendingPathComponent:v], deep)) [variants addObject:v];
    }
    if (!variants.count) return nil;
    NSString *meta = [path stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = NCRegularFile(meta) ? [NSDictionary dictionaryWithContentsOfFile:meta] : nil;
    id format = info[@"FormatVersion"];
    if (format && (![format isKindOfClass:NSNumber.class] || ![format isEqual:@1])) return nil;
    NSString *name = info[@"Name"];
    if (![name isKindOfClass:NSString.class] || !name.length) name = [identifier stringByDeletingPathExtension];
    NSString *version = info[@"Version"];
    NSString *author = info[@"Author"];
    return @{@"id":identifier, @"path":path, @"user":@(user), @"Name":name,
             @"Version":[version isKindOfClass:NSString.class] ? version : @"1.0",
             @"Author":[author isKindOfClass:NSString.class] ? author : @"",
             @"variants":variants};
}
static inline NSArray<NSDictionary *> *NCAllPacks(void) {
    NSMutableArray *packs = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *root in @[NCUserRoot(), NCBuiltinRoot()]) {
        NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil]
                          sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        for (NSString *name in names) {
            if (!NCValidIdentifier(name) || [seen containsObject:name]) continue;
            NSDictionary *info = NCPackInfo([root stringByAppendingPathComponent:name], name,
                                            [root isEqual:NCUserRoot()], NO);
            if (info) { [packs addObject:info]; [seen addObject:name]; }
        }
    }
    return packs;
}
static inline NSString *NCResolvePickedFolder(NSString *path) {
    if (NCPackInfo(path, path.lastPathComponent, YES, YES)) return path;
    NSArray *names = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:nil]
                      sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *name in names) {
        if (!NCValidIdentifier(name)) continue;
        NSString *child = [path stringByAppendingPathComponent:name];
        if (NCPackInfo(child, name, YES, YES)) return child;
    }
    return nil;
}
