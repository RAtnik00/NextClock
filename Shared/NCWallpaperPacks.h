#import <Foundation/Foundation.h>
#import "NCPacks.h"

static inline NSString *NCWallpaperUUID(id value) {
    if (![value isKindOfClass:NSString.class] || [value length] != 36) return nil;
    return [[NSUUID alloc] initWithUUIDString:value].UUIDString;
}

static inline NSString *NCSelectedWallpaperAtPath(NSString *path) {
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:path];
    return NCWallpaperUUID(plist[@"selectedConfigurationIdentifier"]);
}

static inline NSString *NCSelectedWallpaper(void) {
    static NSString *cachedPath;
    static NSTimeInterval lastSearch;
    NSString *selected = cachedPath ? NCSelectedWallpaperAtPath(cachedPath) : nil;
    if (selected) return selected;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (lastSearch && now - lastSearch < 5) return nil;
    lastSearch = now;

    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *root = @"/var/mobile/Containers/Data/Application";
    NSString *match = nil;
    for (NSString *container in [manager contentsOfDirectoryAtPath:root error:nil]) {
        if (!NCWallpaperUUID(container)) continue;
        NSString *store = [root stringByAppendingPathComponent:container];
        store = [store stringByAppendingPathComponent:@"Library/Application Support/PRBPosterExtensionDataStore"];
        for (NSString *schema in [manager contentsOfDirectoryAtPath:store error:nil]) {
            if (!schema.length || [schema rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) continue;
            NSString *path = [[store stringByAppendingPathComponent:schema]
                stringByAppendingPathComponent:@"SelectedConfigurationIdentifier.plist"];
            NSString *identifier = NCSelectedWallpaperAtPath(path);
            if (!identifier) continue;
            if (match) return nil;
            match = path;
            selected = identifier;
        }
    }
    cachedPath = match;
    return selected;
}

static inline NSMutableDictionary *NCWallpaperPackBindings(void) {
    id stored = CFBridgingRelease(CFPreferencesCopyAppValue(
        CFSTR("wallpaperPacks"), CFSTR("com.ratnik00.nextclock")));
    NSMutableDictionary *bindings = [NSMutableDictionary dictionary];
    if (![stored isKindOfClass:NSDictionary.class]) return bindings;
    for (id key in stored) {
        NSString *identifier = NCWallpaperUUID(key);
        id pack = stored[key];
        if (identifier && [pack isKindOfClass:NSString.class] && NCValidIdentifier(pack)) {
            bindings[identifier] = pack;
            if (bindings.count >= 128) break;
        }
    }
    return bindings;
}
