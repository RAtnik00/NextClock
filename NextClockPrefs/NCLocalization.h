#import <Foundation/Foundation.h>

// Use the phone's language preferences, independently of the Settings host bundle.
static inline NSString *NCLocalizedString(NSBundle *bundle, NSString *key) {
    if (!key.length) return key;
    NSArray *available = @[@"en", @"ru", @"uk", @"de", @"pl", @"sv", @"nb", @"it", @"fr"];
    NSString *language = [NSBundle preferredLocalizationsFromArray:available
        forPreferences:NSLocale.preferredLanguages].firstObject ?: @"en";
    NSString *path = [bundle pathForResource:language ofType:@"lproj"];
    NSBundle *localized = path ? [NSBundle bundleWithPath:path] : nil;
    return [localized localizedStringForKey:key value:key table:@"Localizable"] ?: key;
}
