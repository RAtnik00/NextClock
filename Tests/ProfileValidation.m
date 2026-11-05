#import "../Shared/NCProfiles.h"
static void Check(BOOL ok, NSString *reason) { if (!ok) {fprintf(stderr,"FAIL: %s\n",reason.UTF8String);exit(1);} }
int main(int argc,const char **argv) {
    @autoreleasepool {
        Check(argc==2,@"isolated fixture directory"); NSString *path=[@(argv[1]) stringByAppendingPathComponent:@"profiles.plist"];
        Check([NCNormalizeAppearance(nil) isEqual:NCAppearanceDefaults()],@"complete defaults");
        NSDictionary *s=NCNormalizeAppearance(@{@"clockScale":@999,@"verticalOffset":@(-999),@"animationSpeed":@(NAN),
            @"digitSpacing":@"bad",@"pack":@"../escape",@"tintColor":@"#aabbcc",@"enabled":@NO,
            @"showSeconds":@YES,@"unexpected":@"private"});
        Check([s[@"clockScale"] isEqual:@2.5] && [s[@"verticalOffset"] isEqual:@(-120)],@"bounded numbers");
        Check([s[@"animationSpeed"] isEqual:@1] && [s[@"digitSpacing"] isEqual:@(-2)],@"invalid numbers default");
        Check([s[@"pack"] isEqual:@"Anime"] && [s[@"tintColor"] isEqual:@"#AABBCC"],@"safe pack and canonical color");
        Check(!s[@"enabled"] && !s[@"unexpected"] && [s[@"showSeconds"] boolValue],@"appearance whitelist only");
        Check(NCProfileName(@"  Night  ") && !NCProfileName(@" \n ") && !NCProfileName(@"a\nb") &&
            !NCProfileName([@"x" stringByPaddingToLength:61 withString:@"x" startingAtIndex:0]),@"name validation");
        NSError *error=nil; Check(NCReadProfiles(path,&error).count==0 && !error,@"first-run empty store");
        NSDictionary *record=@{@"id":NSUUID.UUID.UUIDString,@"name":@"Night",@"settings":s};
        Check(NCWriteProfiles(path,@[record],&error),@"persist profile");
        Check([NCReadProfiles(path,&error) isEqual:@[record]],@"round trip all settings");
        NSData *before=[NSData dataWithContentsOfFile:path]; error=nil;
        Check(!NCWriteProfiles(path,@[record,record],&error) && error,@"reject duplicate IDs");
        Check([before isEqual:[NSData dataWithContentsOfFile:path]],@"invalid save does not overwrite existing profiles");
        Check(!NCValidateProfiles(@{@"version":@2,@"profiles":@[]},NULL),@"future schema rejected");
        Check(!NCValidateProfiles(@{@"version":@1,@"profiles":@[@"not a record"]},NULL),@"malformed record rejected");
        NSMutableArray *many=[NSMutableArray array];
        for (int i=0;i<21;i++) [many addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":@"Profile",@"settings":s}];
        Check(!NCWriteProfiles(path,many,NULL),@"twenty-profile limit");
        Check(NCWriteProfiles(path,@[],&error) && NCReadProfiles(path,NULL).count==0,@"deletion persisted");
        [@"broken" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
        error=nil; Check(!NCReadProfiles(path,&error) && error,@"corrupt store reports error");
        NSString *link=[path stringByAppendingString:@".link"];
        [NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:path error:NULL];
        Check(!NCReadProfiles(link,NULL),@"symlink store rejected");
        puts("PASS: profile normalization, whitelist, names, persistence, schema and corrupt-store checks.");
    } return 0;
}
