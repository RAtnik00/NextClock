#import "../Shared/NCProfiles.h"
#import "../Shared/NCEditorLayout.h"
static void Check(BOOL ok) {if(!ok)exit(1);}
int main(void) {@autoreleasepool {
    Check(NCDateStyleIsSystem(nil)); Check(NCDateStyleIsSystem(@"bad"));
    Check([NCNormalizeDateStyle(@{@"dateFontScale":@(NAN),@"dateFontDesign":@5,@"dateFontWeight":@"bad"}) isEqual:NCDateStyleDefaults()]);
    Check([NCNormalizeDateStyle(@{@"dateFontScale":@99})[@"dateFontScale"] isEqual:@1.6]);
    Check([NCNormalizeDateStyle(@{@"dateFontScale":@(-9)})[@"dateFontScale"] isEqual:@0.6]);
    for(NSString *design in @[@"system",@"rounded",@"serif",@"monospaced"]) for(NSString *weight in @[@"system",@"regular",@"medium",@"semibold",@"bold"]) {
        NSDictionary *s=@{@"dateFontDesign":design,@"dateFontWeight":weight,@"dateFontScale":@1.25};
        Check([NCNormalizeDateStyle(s) isEqual:s]);
        NSDictionary *profile=NCNormalizeAppearance(s);
        Check([profile[@"dateFontDesign"] isEqual:design] && [profile[@"dateFontWeight"] isEqual:weight] && [profile[@"dateFontScale"] isEqual:@1.25]);
        Check(![profile[@"enabled"] boolValue]);
    }
    NSDictionary *old=NCNormalizeAppearance(@{@"pack":@"Anime",@"showSeconds":@YES});
    Check(NCDateStyleIsSystem(old)); Check([old[@"showSeconds"] boolValue]);
    Check(NCDateStyleIsSystem(NCNormalizeAppearance(NCAppearanceDefaults())));
    puts("PASS: system defaults, old-profile migration, all date font/weight combinations and bounded/nonfinite scale.");
}return 0;}
