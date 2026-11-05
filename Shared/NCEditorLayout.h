#import <Foundation/Foundation.h>
// One source of truth for the editor hierarchy; all persisted keys are unchanged.
static inline NSDictionary *NCEditorRow(NSString *key, NSString *title, NSString *kind) {
    return @{@"key":key,@"title":title,@"kind":kind};
}
static inline NSArray *NCEditorSections(BOOL pro) {
    NSMutableArray *sections=[@[
        @{@"title":@"Preview",@"footer":@"Draft only. Apply sends these settings to the Lock Screen.",@"rows":@[NCEditorRow(@"",@"Preview",@"preview")]},
        @{@"title":@"Appearance",@"rows":@[NCEditorRow(@"pack",@"Pack",@"choice"),NCEditorRow(@"animationStyle",@"Animated",@"toggle"),NCEditorRow(@"animationSpeed",@"Animation Speed",@"slider"),NCEditorRow(@"staticInLowPower",@"Still in Low Power Mode",@"toggle")]},
        @{@"title":@"Layout",@"rows":@[NCEditorRow(@"clockScale",@"Size",@"slider"),NCEditorRow(@"digitSpacing",@"Spacing",@"slider"),NCEditorRow(@"verticalOffset",@"Vertical Offset",@"slider")]},
        @{@"title":@"TIME",@"rows":@[NCEditorRow(@"timeFormat",@"Format",@"choice"),NCEditorRow(@"showSeconds",@"Seconds",@"toggle"),NCEditorRow(@"hideDate",@"Hide Date",@"toggle")]},
        @{@"title":@"Date",@"footer":@"Choose System for font and weight, and 100% size, to restore the original date appearance.",@"rows":@[NCEditorRow(@"dateFontDesign",@"Date font",@"choice"),NCEditorRow(@"dateFontScale",@"Date size",@"slider"),NCEditorRow(@"dateFontWeight",@"Date weight",@"choice")]},
        @{@"title":@"COLOR",@"rows":@[NCEditorRow(@"colorFilterEnabled",@"Tint",@"toggle"),NCEditorRow(@"tintColor",@"Color",@"choice")]}
    ] mutableCopy];
    if (pro) [sections addObject:@{@"title":@"Profiles",@"rows":@[NCEditorRow(@"saveProfile",@"Save Profile",@"action"),NCEditorRow(@"showProfiles",@"Profiles",@"action")]}];
    return sections;
}
