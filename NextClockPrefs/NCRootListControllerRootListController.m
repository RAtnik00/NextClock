#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <Preferences/PSSpecifier.h>
#import "NCRootListControllerRootListController.h"
#import "../Shared/NCPacks.h"
#import "../Shared/NCZip.h"
#import "NCLocalization.h"
#import "../Shared/NCVersion.h"
#import "NCProController.h"
#import "../Shared/NCFavorites.h"

static NSString *NCText(NSString *key) {
    return NCLocalizedString([NSBundle bundleForClass:NCRootListControllerRootListController.class], key);
}

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
// Localize plist labels, footers and list choices; stored preference values stay unchanged.
- (NSMutableArray *)nc_loadSpecifiers:(NSString *)name {
    NSMutableArray *items = [[self loadSpecifiersFromPlistName:name target:self] mutableCopy];
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSDictionary *source = [NSDictionary dictionaryWithContentsOfFile:
        [bundle pathForResource:name ofType:@"plist"]];
    self.title = NCText(source[@"title"] ?: @"NextClock");
    for (PSSpecifier *row in items) {
        if ([[row propertyForKey:@"nextClockVersion"] boolValue])
            row.name = [NSString stringWithFormat:NCText(@"Version: %@"), NC_VERSION];
        else if (row.name.length) row.name = NCText(row.name);
        NSString *footer = [row propertyForKey:@"footerText"];
#ifdef NC_LEGACY_BUILD
        if (([name isEqual:@"About"] && footer.length) ||
            [footer isEqual:@"iOS 16–18 support is experimental and has limited device testing. iOS 15 remains supported. Please report your model, exact iOS version and jailbreak."])
            footer = @"Experimental rootful build for iOS 12–14. Device testing required.";
#endif
        if (footer.length) [row setProperty:NCText(footer) forKey:@"footerText"];
        NSString *key = [row propertyForKey:@"key"];
        for (NSDictionary *entry in source[@"items"]) {
            if (!key || ![key isEqual:entry[@"key"]]) continue;
            NSArray *titles = entry[@"validTitles"], *values = entry[@"validValues"];
            if (titles.count && titles.count == values.count && ![key isEqual:@"pack"]) {
                NSMutableArray *translated = [NSMutableArray array];
                for (NSString *title in titles) [translated addObject:NCText(title)];
                [row setValues:values titles:translated shortTitles:translated];
            }
            break;
        }
    }
    return items;
}

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
        _specifiers=[self nc_loadSpecifiers:@"About"]; return _specifiers;
    }
    if ([page isEqual:@"PackDetails"]) {
        NSDictionary *pack=[self currentPack]; self.title=pack[@"Name"] ?: NCText(@"Pack"); NSMutableArray *items=[NSMutableArray array];
        [items addObject:[PSSpecifier groupSpecifierWithName:pack[@"Name"] ?: NCText(@"Pack")]];
        [items addObject:[self text:[NSString stringWithFormat:NCText(@"Version: %@"), pack[@"Version"] ?: @"1.0"]]];
        if ([pack[@"Author"] length]) [items addObject:[self text:[NSString stringWithFormat:NCText(@"Author: %@"), pack[@"Author"]]]];
        [items addObject:[self text:[pack[@"user"] boolValue] ? NCText(@"User pack") : NCText(@"Bundled pack")]];
        [items addObject:[self button:NCText(@"Use this pack") action:@selector(useThisPack)]];
        PSSpecifier *group=[PSSpecifier groupSpecifierWithName:@""];
        [items addObject:group];
        if ([pack[@"user"] boolValue]) {
            PSSpecifier *remove=[self button:NCText(@"Delete pack") action:@selector(deleteThisPack)];
            [remove setProperty:@YES forKey:@"isDestructive"]; [items addObject:remove];
        } else [group setProperty:NCText(@"Bundled packs are part of NextClock and cannot be deleted here.") forKey:@"footerText"];
        _specifiers=items; return _specifiers;
    }
    if ([page isEqual:@"Favorites"]) {
        NSArray *packs=NCAllPacks();
        self.title=NCText(@"Favorites");
        NSMutableArray *items=[NSMutableArray array];
        PSSpecifier *group=[PSSpecifier groupSpecifierWithName:NCText(@"Favorites")];
        [group setProperty:NCText(@"Choose at least two packs. Double-tap the clock digits to switch. Long-press remains available for wallpaper editing.") forKey:@"footerText"];
        [items addObject:group];
        for (NSDictionary *pack in [@[@{@"id":@"doubleTapFavorites",@"Name":NCText(@"Double-tap to switch")}] arrayByAddingObjectsFromArray:packs]) {
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:pack[@"Name"] target:self
                set:@selector(setFavorite:specifier:) get:@selector(readFavorite:) detail:Nil cell:PSSwitchCell edit:Nil];
            [row setProperty:pack[@"id"] forKey:@"favoriteID"]; [items addObject:row];
        }
        _specifiers=items; return _specifiers;
    }
    if ([page isEqual:@"ManagePacks"]) {
        NSArray *packs=NCAllPacks();
        NSMutableArray *items=[NSMutableArray array];
        [items addObject:[PSSpecifier groupSpecifierWithName:NCText(@"INSTALLED")]];
        for (NSDictionary *pack in packs) {
            PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:pack[@"Name"] target:self set:NULL get:NULL
                detail:self.class cell:PSLinkCell edit:Nil];
            [row setProperty:@"PackDetails" forKey:@"nextClockPage"]; [row setProperty:pack forKey:@"ncPack"];
            [items addObject:row];
        }
        NSArray *imports=[self nc_loadSpecifiers:@"ManagePacks"];
        if (imports) [items addObjectsFromArray:imports]; _specifiers=items; return _specifiers;
    }
#ifdef NC_LEGACY_BUILD
    _specifiers=[self nc_loadSpecifiers:@"LegacyRoot"];
#else
    _specifiers=[self nc_loadSpecifiers:@"Root"];
#endif
#ifdef NC_PRO_BUILD
    self.title=@"NextClock Pro";
    for (PSSpecifier *row in _specifiers) if ([row.name isEqual:NCText(@"Configure clock")]) row.name=NCText(@"Preview & Profiles");
#endif
    for (PSSpecifier *row in _specifiers) if ([[row propertyForKey:@"key"] isEqual:@"pack"]) {
        NSMutableArray *values=[NSMutableArray array], *titles=[NSMutableArray array];
        for (NSDictionary *pack in NCAllPacks()) {
            [values addObject:pack[@"id"]];
            [titles addObject:pack[@"Name"]];
        }
        [row setValues:values titles:titles shortTitles:titles];
        break;
    }
    return _specifiers;
}
- (void)refreshNextClockSettings { _specifiers=nil; [self reloadSpecifiers]; }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshNextClockSettings];
}
- (void)openProPreview {
    [self.navigationController pushViewController:[NCProController new] animated:YES];
}
- (id)readFavorite:(PSSpecifier *)specifier {
    CFPreferencesAppSynchronize(CFSTR("com.ratnik00.nextclock"));
    NSString *identifier=[specifier propertyForKey:@"favoriteID"];
    NSString *key=[identifier isEqual:@"doubleTapFavorites"] ? identifier : @"favoritePacks";
    id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,CFSTR("com.ratnik00.nextclock")));
    return [key isEqual:@"favoritePacks"] ? @([value isKindOfClass:NSArray.class] && [value containsObject:identifier]) : @([value isKindOfClass:NSNumber.class] && [value boolValue]);
}
- (void)setFavorite:(NSNumber *)on specifier:(PSSpecifier *)specifier {
    CFStringRef domain=CFSTR("com.ratnik00.nextclock"); CFPreferencesAppSynchronize(domain);
    NSString *identifier=[specifier propertyForKey:@"favoriteID"];
    if ([identifier isEqual:@"doubleTapFavorites"]) CFPreferencesSetAppValue(CFSTR("doubleTapFavorites"),(__bridge CFNumberRef)on,domain);
    else {
        id stored=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("favoritePacks"),domain));
        NSMutableArray *values=[NCFavoriteIdentifiers(stored,NCAllPacks()) mutableCopy];
        [values removeObject:identifier]; if (on.boolValue && NCValidIdentifier(identifier)) [values addObject:identifier];
        CFPreferencesSetAppValue(CFSTR("favoritePacks"),(__bridge CFArrayRef)values,domain);
    }
    CFPreferencesAppSynchronize(domain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ratnik00.nextclock/preferenceschanged"),NULL,NULL,YES);
}
- (void)refreshAllPages {
    NSArray *pages = [self.navigationController.viewControllers copy];
    for (UIViewController *page in pages)
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
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:NCText(title) message:NCText(message) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NCText(@"OK") style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)deleteThisPack {
    NSDictionary *pack=[self currentPack]; NSString *identifier=pack[@"id"];
    if (![pack[@"user"] boolValue] || !NCValidIdentifier(identifier)) return;
    NSString *path=[NCUserRoot() stringByAppendingPathComponent:identifier];
    if (![path isEqual:pack[@"path"]]) return;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:NCText(@"Delete pack?")
        message:[NSString stringWithFormat:NCText(@"Delete “%@”? You can import it again later."),pack[@"Name"]] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NCText(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NCText(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        NSError *error=nil;
        if (![NSFileManager.defaultManager removeItemAtPath:path error:&error]) { [self showMessage:error.localizedDescription title:NCText(@"Delete failed")]; return; }
        CFPreferencesAppSynchronize(CFSTR("com.ratnik00.nextclock"));
        id selected=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("pack"),CFSTR("com.ratnik00.nextclock")));
        [self setPack:[selected isKindOfClass:NSString.class] && ![selected isEqual:identifier] ? selected : @"Anime"];
        [self.navigationController popViewControllerAnimated:YES]; [self refreshAllPages];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)importPack {
    if (self.importing || self.presentedViewController) return;
    UIDocumentPickerViewController *picker;
    // Accept unregistered .nextclock types; the importer validates the contents.
    if (@available(iOS 14.0, *)) {
        picker=[[UIDocumentPickerViewController alloc]
            initForOpeningContentTypes:@[UTTypeFolder,UTTypeItem] asCopy:NO];
    }
#if __IPHONE_OS_VERSION_MIN_REQUIRED < 140000
    else {
        // Folder selection arrived in iOS 13. iOS 12 imports ZIP/.nextclock files.
        NSArray *types;
        UIDocumentPickerMode mode;
        if (@available(iOS 13.0, *)) {
            types=@[@"public.folder", @"public.item"];
            mode=UIDocumentPickerModeOpen;
        } else {
            types=@[@"public.item"];
            mode=UIDocumentPickerModeImport;
        }
        picker=[[UIDocumentPickerViewController alloc]
            initWithDocumentTypes:types inMode:mode];
    }
#endif
    picker.delegate=self; picker.allowsMultipleSelection=NO;
    [self presentViewController:picker animated:YES completion:nil];
}
- (NSString *)installPackFromFolder:(NSURL *)url error:(NSError **)error {
    NSFileManager *manager=NSFileManager.defaultManager;
    NSString *source=NCResolvePickedFolder(url.path);
    if (!source) { if (error) *error=NCError(NCText(@"Choose a pack containing all digits 0–9 and colon in static/ or animated/. PNG, GIF and APNG are supported.")); return nil; }
    NSDictionary *info=NCPackInfo(source,source.lastPathComponent,YES,YES);
    if (!info) { if (error) *error=NCError(NCText(@"Copied pack failed validation.")); return nil; }
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
    if (copied && !NCPackInfo(stage,identifier,YES,YES)) { copied=NO; if (error) *error=NCError(NCText(@"Copied pack failed validation.")); }
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
            NSString *message=identifier ? NCText(@"Pack imported and selected.") : (failure ?: coordinationError).localizedDescription ?: NCText(@"Import failed.");
            void (^finish)(void)=^{ if (identifier) [self refreshAllPages]; [self showMessage:message title:@"NextClock"]; };
            if (controller.presentingViewController) [controller dismissViewControllerAnimated:YES completion:finish]; else finish();
        });
    });
}
- (void)exportDiagnostics {
    NSString *path = @"/var/mobile/Library/NextClock-compatibility.txt";
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) {
        [self showMessage:@"No diagnostic report yet. Restart SpringBoard, lock and wake the device, then try again." title:@"NextClock"];
        return;
    }
    NSError *error = nil;
    NSURL *copy = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"NextClock-diagnostics-%@.txt", NSUUID.UUID.UUIDString]]];
    if (![NSFileManager.defaultManager copyItemAtURL:[NSURL fileURLWithPath:path] toURL:copy error:&error]) {
        [self showMessage:error.localizedDescription title:@"NextClock"]; return;
    }
#ifdef NC_AOD_PROBE
    NSString *probe = [NSString stringWithContentsOfFile:@"/var/mobile/Library/NextClock-aod-probe.txt"
        encoding:NSUTF8StringEncoding error:nil];
    if (probe.length) {
        NSString *report = [NSString stringWithContentsOfURL:copy encoding:NSUTF8StringEncoding error:nil] ?: @"";
        [[report stringByAppendingFormat:@"\n\n%@", probe] writeToURL:copy atomically:YES
            encoding:NSUTF8StringEncoding error:nil];
    }
#endif
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[copy] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    share.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *failure) {
        [NSFileManager.defaultManager removeItemAtURL:copy error:nil];
    };
    [self presentViewController:share animated:YES completion:nil];
}
- (void)resetSettings {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:NCText(@"Reset settings?")
        message:NCText(@"All clock settings will return to defaults. Installed packs will be kept.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NCText(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NCText(@"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        CFStringRef domain=CFSTR("com.ratnik00.nextclock");
        for (NSString *key in @[@"wallpaperPacks",@"dateFontDesign",@"dateFontScale",@"dateFontWeight",@"favoritePacks",@"doubleTapFavorites",@"enabled",@"pack",@"animationStyle",@"animationSpeed",@"staticInLowPower",@"clockScale",@"digitSpacing",@"verticalOffset",@"timeFormat",@"hideDate", @"showSeconds",@"colorFilterEnabled",@"tintColor"])
            CFPreferencesSetAppValue((__bridge CFStringRef)key,NULL,domain);
        CFPreferencesAppSynchronize(domain);
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ratnik00.nextclock/preferenceschanged"),NULL,NULL,YES);
        [self refreshAllPages];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)supportDeveloper {
    NSURL *url = [NSURL URLWithString:@"https://buycoffee.to/ratnik00"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showMessage:NCText(@"Unable to open the support page. Please try again later.")
                            title:@"NextClock"];
            });
        }
    }];
}
- (void)restartSpringBoard {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:NCText(@"Restart SpringBoard") message:NCText(@"The Lock Screen will restart. Your settings will be kept.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:NCText(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:NCText(@"Restart SpringBoard") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ratnik00.nextclock/respring"),NULL,NULL,YES);
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
