#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Preferences/PSSpecifier.h>
#import "NCRootListControllerRootListController.h"
#import "../Shared/NCPacks.h"
#import "../Shared/NCZip.h"

@interface PSSpecifier (NextClockLists)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles shortTitles:(NSArray *)shortTitles;
@end
@interface NCRootListControllerRootListController ()
@property(nonatomic) BOOL importing;
- (void)refreshNextClockSettings;
- (void)refreshAllPages;
- (NSString *)installPackFromFolder:(NSURL *)url error:(NSError **)error;
@end

@implementation NCRootListControllerRootListController
- (PSSpecifier *)button:(NSString *)title action:(SEL)action {
    PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:title target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
    row.buttonAction=action; return row;
}
- (PSSpecifier *)text:(NSString *)text {
    return [PSSpecifier preferenceSpecifierNamed:text target:self set:NULL get:NULL detail:Nil cell:PSStaticTextCell edit:Nil];
}
- (NSDictionary *)currentPack {
    id value=[self.specifier propertyForKey:@"ncPack"];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSString *page=[self.specifier propertyForKey:@"nextClockPage"];
    if ([page isEqual:@"About"]) {
        _specifiers=[self loadSpecifiersFromPlistName:@"About" target:self]; return _specifiers;
    }
    if ([page isEqual:@"PackDetails"]) {
        NSDictionary *pack=[self currentPack]; NSMutableArray *items=[NSMutableArray array];
        [items addObject:[PSSpecifier groupSpecifierWithName:pack[@"Name"] ?: @"Pack"]];
        [items addObject:[self text:[@"Version: " stringByAppendingString:pack[@"Version"] ?: @"1.0"]]];
        if ([pack[@"Author"] length]) [items addObject:[self text:[@"Author: " stringByAppendingString:pack[@"Author"]]]];
        [items addObject:[self text:[pack[@"user"] boolValue] ? @"User pack" : @"Bundled pack"]];
        [items addObject:[self button:@"Use this pack" action:@selector(useThisPack)]];
        PSSpecifier *group=[PSSpecifier groupSpecifierWithName:@""];
        [items addObject:group];
        if ([pack[@"user"] boolValue]) {
            PSSpecifier *remove=[self button:@"Delete pack" action:@selector(deleteThisPack)];
            [remove setProperty:@YES forKey:@"isDestructive"]; [items addObject:remove];
        } else [group setProperty:@"Bundled packs are part of NextClock and cannot be deleted here." forKey:@"footerText"];
        _specifiers=items; return _specifiers;
    }
    NSArray *packs=NCAllPacks();
    if ([page isEqual:@"ManagePacks"]) {
        NSMutableArray *items=[NSMutableArray array];
        [items addObject:[PSSpecifier groupSpecifierWithName:@"INSTALLED"]];
        for (NSDictionary *pack in packs) {
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:pack[@"Name"] target:self set:NULL get:NULL
                detail:self.class cell:PSLinkCell edit:Nil];
            [row setProperty:@"PackDetails" forKey:@"nextClockPage"]; [row setProperty:pack forKey:@"ncPack"];
            [items addObject:row];
        }
        NSArray *imports=[self loadSpecifiersFromPlistName:@"ManagePacks" target:self];
        if (imports) [items addObjectsFromArray:imports]; _specifiers=items; return _specifiers;
    }
    _specifiers=[self loadSpecifiersFromPlistName:@"Root" target:self];
    NSMutableArray *values=[NSMutableArray array], *titles=[NSMutableArray array];
    for (NSDictionary *pack in packs) { [values addObject:pack[@"id"]]; [titles addObject:pack[@"Name"]]; }
    for (PSSpecifier *row in _specifiers) if ([[row propertyForKey:@"key"] isEqual:@"pack"]) {
        [row setValues:values titles:titles shortTitles:titles]; break;
    }
    return _specifiers;
}
- (void)refreshNextClockSettings { _specifiers=nil; [self reloadSpecifiers]; }
- (void)refreshAllPages {
    for (UIViewController *page in self.navigationController.viewControllers)
        if ([page isKindOfClass:self.class]) [(NCRootListControllerRootListController *)page refreshNextClockSettings];
}
- (void)setPack:(NSString *)identifier {
    CFStringRef domain=CFSTR("com.ratnik00.nextclock");
    CFPreferencesSetAppValue(CFSTR("pack"),(__bridge CFStringRef)identifier,domain);
    CFPreferencesAppSynchronize(domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ratnik00.nextclock/preferenceschanged"),NULL,NULL,YES);
}
- (void)useThisPack {
    NSDictionary *pack=[self currentPack]; NSString *identifier=pack[@"id"];
    if (!NCValidIdentifier(identifier)) return;
    [self setPack:identifier]; [self refreshAllPages]; [self.navigationController popViewControllerAnimated:YES];
}
- (void)showMessage:(NSString *)message title:(NSString *)title {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)deleteThisPack {
    NSDictionary *pack=[self currentPack]; NSString *identifier=pack[@"id"];
    if (![pack[@"user"] boolValue] || !NCValidIdentifier(identifier)) return;
    NSString *path=[NCUserRoot() stringByAppendingPathComponent:identifier];
    if (![path isEqual:pack[@"path"]]) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Delete pack?"
        message:[NSString stringWithFormat:@"Delete “%@”? You can import it again later.",pack[@"Name"]] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Delete" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error=nil;
        if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) { [self showMessage:error.localizedDescription title:@"Delete failed"]; return; }
        CFPreferencesAppSynchronize(CFSTR("com.ratnik00.nextclock"));
        id selected=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("pack"),CFSTR("com.ratnik00.nextclock")));
        [self setPack:[selected isKindOfClass:NSString.class] && ![selected isEqual:identifier] ? selected : @"Anime"];
        [self.navigationController popViewControllerAnimated:YES]; [self refreshAllPages];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)importPack {
    if (self.importing) return;
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeFolder,UTTypeData] asCopy:NO];
    picker.delegate=self; picker.allowsMultipleSelection=NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (NSString *)installPackFromFolder:(NSURL *)url error:(NSError **)error {
    NSFileManager *manager=NSFileManager.defaultManager;
    NSString *source=NCResolvePickedFolder(url.path);
    if (!source) { if (error) *error=NCError(@"Choose a pack containing all digits 0–9 and colon in static/ or animated/. PNG, GIF and APNG are supported."); return nil; }
    NSDictionary *info=NCPackInfo(source,source.lastPathComponent,YES,YES);
    NSString *identifier=[@"Imported-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSString *root=NCUserRoot();
    if (![manager createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *stage=[root stringByAppendingPathComponent:[@".incoming-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    BOOL copied=[manager createDirectoryAtPath:stage withIntermediateDirectories:NO attributes:nil error:error];
    for (NSString *variant in info[@"variants"]) {
        if (!copied) break;
        NSString *from=[source stringByAppendingPathComponent:variant], *to=[stage stringByAppendingPathComponent:variant];
        copied=[manager createDirectoryAtPath:to withIntermediateDirectories:NO attributes:nil error:error];
        for (NSString *glyph in NCGlyphNames()) {
            if (!copied) break;
            NSString *path=NCGlyphPath(from,glyph);
            copied=[manager copyItemAtPath:path toPath:[to stringByAppendingPathComponent:path.lastPathComponent] error:error];
        }
    }
    if (copied) {
        NSDictionary *meta=@{@"Name":info[@"Name"],@"Version":info[@"Version"],@"Author":info[@"Author"],@"FormatVersion":@1};
        NSData *data=[NSPropertyListSerialization dataWithPropertyList:meta format:NSPropertyListXMLFormat_v1_0 options:0 error:error];
        copied=data && [data writeToFile:[stage stringByAppendingPathComponent:@"Info.plist"] options:NSDataWritingAtomic error:error];
    }
    if (copied && !NCPackInfo(stage,identifier,YES,YES)) { copied=NO; if (error) *error=NCError(@"Copied pack failed validation."); }
    if (copied) copied=[manager moveItemAtPath:stage toPath:[root stringByAppendingPathComponent:identifier] error:error];
    if (!copied) [manager removeItemAtPath:stage error:nil];
    return copied ? identifier : nil;
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject; if (!url || self.importing) return; self.importing=YES;
    // Decode and coordinate outside the UI thread; only presentation and list updates run on main.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        BOOL scoped=[url startAccessingSecurityScopedResource];
        __block NSString *identifier=nil; __block NSError *failure=nil;
        NSError *coordinationError=nil;
        NSFileCoordinator *coordinator=[[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coordinator coordinateReadingItemAtURL:url options:0 error:&coordinationError byAccessor:^(NSURL *readURL) {
            BOOL directory=NO; [NSFileManager.defaultManager fileExistsAtPath:readURL.path isDirectory:&directory];
            if (directory) identifier=[self installPackFromFolder:readURL error:&failure];
            else {
                NSString *temporary=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
                if ([NSFileManager.defaultManager createDirectoryAtPath:temporary withIntermediateDirectories:NO attributes:nil error:&failure] &&
                    NCExtractZip(readURL.path,temporary,&failure)) identifier=[self installPackFromFolder:[NSURL fileURLWithPath:temporary] error:&failure];
                [NSFileManager.defaultManager removeItemAtPath:temporary error:nil];
            }
        }];
        if (scoped) [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.importing=NO;
            if (identifier) [self setPack:identifier];
            NSString *message=identifier ? @"Pack imported and selected." : (failure ?: coordinationError).localizedDescription ?: @"Import failed.";
            void (^finish)(void)=^{ if (identifier) [self refreshAllPages]; [self showMessage:message title:@"NextClock"]; };
            if (controller.presentingViewController) [controller dismissViewControllerAnimated:YES completion:finish]; else finish();
        });
    });
}
- (void)resetSettings {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Reset settings?"
        message:@"All clock settings will return to defaults. Installed packs will be kept." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        CFStringRef domain=CFSTR("com.ratnik00.nextclock");
        for (NSString *key in @[@"enabled",@"pack",@"animationStyle",@"animationSpeed",@"staticInLowPower",@"clockScale",@"digitSpacing",@"verticalOffset",@"timeFormat",@"hideDate",@"colorFilterEnabled",@"tintColor"])
            CFPreferencesSetAppValue((__bridge CFStringRef)key,NULL,domain);
        CFPreferencesAppSynchronize(domain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ratnik00.nextclock/preferenceschanged"),NULL,NULL,YES);
        [self refreshAllPages];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)restartSpringBoard {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ratnik00.nextclock/respring"),NULL,NULL,YES);
}
@end
