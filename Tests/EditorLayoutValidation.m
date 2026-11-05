#import "../Shared/NCProfiles.h"
#import "../Shared/NCEditorLayout.h"
static void Check(BOOL ok) { if(!ok) exit(1); }
int main(void) { @autoreleasepool {
    NSSet *expected=[NSSet setWithArray:NCAppearanceDefaults().allKeys];
    for (NSNumber *pro in @[@NO,@YES]) {
        NSMutableSet *found=[NSMutableSet set]; NSUInteger actions=0,previews=0;
        for (NSDictionary *section in NCEditorSections(pro.boolValue)) {
            Check([section[@"title"] length]>0 && [section[@"rows"] count]>0);
            for (NSDictionary *row in section[@"rows"]) {
                NSString *kind=row[@"kind"],*key=row[@"key"];
                Check([row[@"title"] length]>0);
                if ([kind isEqual:@"preview"]) { previews++;continue; }
                if ([kind isEqual:@"action"]) { actions++;continue; }
                Check([@[@"slider",@"toggle",@"choice"] containsObject:kind]);
                Check(![found containsObject:key]);[found addObject:key];
            }
        }
        Check([found isEqual:expected]);Check(previews==1);Check(actions==(pro.boolValue ? 2 : 0));
        Check(![found containsObject:@"enabled"] && ![found containsObject:@"favoritePacks"]);
    }
    puts("PASS: every appearance preference reachable exactly once; one preview; profile actions Pro-only; enabled/favorites remain independent.");
} return 0; }
