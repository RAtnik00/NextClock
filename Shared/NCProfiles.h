#import <Foundation/Foundation.h>
#import <math.h>
#import "NCPacks.h"
#import "NCDateStyle.h"

// Only appearance settings belong in a profile. Never store enabled, diagnostics,
// filesystem paths or unknown preference keys from an imported dictionary.
static inline NSDictionary *NCAppearanceDefaults(void) {
    return @{@"pack":@"Anime", @"animationStyle":@"animated", @"animationSpeed":@1,
        @"staticInLowPower":@NO, @"clockScale":@1, @"digitSpacing":@(-2),
        @"verticalOffset":@0, @"timeFormat":@"system", @"hideDate":@NO,
        @"dateFontDesign":@"system",@"dateFontScale":@1,@"dateFontWeight":@"system",
        @"showSeconds":@NO, @"colorFilterEnabled":@NO, @"tintColor":@"#FF9500"};
}
static inline NSDictionary *NCNormalizeAppearance(id input) {
    NSDictionary *source = [input isKindOfClass:NSDictionary.class] ? input : @{};
    NSMutableDictionary *out = [NCAppearanceDefaults() mutableCopy];
    for (NSString *key in @[@"staticInLowPower", @"hideDate", @"showSeconds", @"colorFilterEnabled"])
        if ([source[key] isKindOfClass:NSNumber.class]) out[key]=@([source[key] boolValue]);
    NSDictionary *ranges=@{@"animationSpeed":@[@0.25,@3], @"clockScale":@[@0.3,@2.5],
        @"digitSpacing":@[@(-25),@40], @"verticalOffset":@[@(-120),@120]};
    for (NSString *key in ranges) {
        id value=source[key]; double number=[value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN;
        if (isfinite(number)) out[key]=@(MAX([ranges[key][0] doubleValue], MIN([ranges[key][1] doubleValue],number)));
    }
    if (NCValidIdentifier(source[@"pack"]) && [source[@"pack"] length]<=128) out[@"pack"]=source[@"pack"];
    for (NSString *key in @[@"animationStyle",@"timeFormat"]) {
        NSArray *allowed=[key isEqual:@"animationStyle"] ? @[@"static",@"animated"] : @[@"system",@"12hour",@"24hour"];
        if (source[key] && [allowed containsObject:source[key]]) out[key]=source[key];
    }
    NSString *color=source[@"tintColor"];
    if ([color isKindOfClass:NSString.class] && color.length==7 && [color hasPrefix:@"#"] &&
        [[color substringFromIndex:1] rangeOfCharacterFromSet:
            [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefABCDEF"] invertedSet]].location==NSNotFound)
        out[@"tintColor"]=color.uppercaseString;
    [out addEntriesFromDictionary:NCNormalizeDateStyle(source)];
    return out;
}
static inline NSString *NCProfileName(id input) {
    if (![input isKindOfClass:NSString.class]) return nil;
    NSString *name=[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!name.length || name.length>60 || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound) return nil;
    return name;
}
static inline NSArray *NCValidateProfiles(id root, NSError **error) {
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"version"] isEqual:@1] ||
        ![root[@"profiles"] isKindOfClass:NSArray.class] || [root[@"profiles"] count]>20) {
        if (error) *error=NCError(@"Invalid profiles file."); return nil;
    }
    NSMutableArray *out=[NSMutableArray array]; NSMutableSet *ids=[NSMutableSet set];
    for (id record in root[@"profiles"]) {
        if (![record isKindOfClass:NSDictionary.class] || !NCProfileName(record[@"name"]) ||
            ![record[@"id"] isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:record[@"id"]] ||
            [ids containsObject:record[@"id"]] || ![record[@"settings"] isKindOfClass:NSDictionary.class]) {
            if (error) *error=NCError(@"Invalid profiles file."); return nil;
        }
        [ids addObject:record[@"id"]];
        [out addObject:@{@"id":record[@"id"], @"name":NCProfileName(record[@"name"]),
            @"settings":NCNormalizeAppearance(record[@"settings"])}];
    }
    return out;
}
static inline NSArray *NCReadProfiles(NSString *path, NSError **error) {
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return @[];
    NSDictionary *attrs=[NSFileManager.defaultManager attributesOfItemAtPath:path error:error];
    if (![attrs[NSFileType] isEqual:NSFileTypeRegular] || [attrs[NSFileSize] unsignedLongLongValue]>128*1024) {
        if (error) *error=NCError(@"Invalid profiles file."); return nil;
    }
    NSData *data=[NSData dataWithContentsOfFile:path options:0 error:error]; if (!data) return nil;
    id root=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:error];
    return NCValidateProfiles(root,error);
}
static inline BOOL NCWriteProfiles(NSString *path, NSArray *profiles, NSError **error) {
    profiles=NCValidateProfiles(@{@"version":@1,@"profiles":profiles ?: @[]},error);
    if (!profiles) return NO;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"profiles":profiles}
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || data.length>128*1024) return NO;
    if (![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    return [data writeToFile:path options:NSDataWritingAtomic error:error];
}
