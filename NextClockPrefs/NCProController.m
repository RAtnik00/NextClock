#import "../Shared/NCWallpaperPacks.h"
#import "NCProController.h"
#import <QuartzCore/QuartzCore.h>
#import "../Shared/NCProfiles.h"
#import "../Shared/NCEditorLayout.h"
#import "../Shared/NCDateFont.h"

#import "NCLocalization.h"
static NSString *P(NSString *key) {
    NSDictionary *aliases=@{@"Seconds":@"Show seconds",@"Hide Date":@"Hide date",@"Size":@"DIGIT SIZE",@"Spacing":@"SPACING",@"Vertical Offset":@"VERTICAL OFFSET",@"Animation Speed":@"ANIMATION SPEED"};
#ifdef NC_PRO_BUILD
    NSString *language=[NSBundle preferredLocalizationsFromArray:@[@"en",@"ru"] forPreferences:NSLocale.preferredLanguages].firstObject;
    if ([language isEqual:@"ru"]) {
        NSDictionary *ru=@{@"Save Profile":@"Сохранить профиль",@"Profiles":@"Профили",@"Load":@"Загрузить",@"Rename":@"Переименовать",@"Save":@"Сохранить",@"Error":@"Ошибка",@"Profile name (1–60 characters)":@"Название профиля (1–60 символов)",@"No saved profiles yet.":@"Сохранённых профилей пока нет.",@"Name must contain 1–60 characters.":@"Название должно содержать 1–60 символов.",@"Maximum 20 profiles.":@"Можно сохранить не более 20 профилей.",@"Delete this profile?":@"Удалить этот профиль?"};
        if (ru[key]) return ru[key];
    }
#endif
    return NCLocalizedString([NSBundle bundleForClass:NCProController.class],aliases[key] ?: key);
}
#ifdef NC_PRO_BUILD
static NSString * const NCProfilePath=@"/var/mobile/Library/NextClock/ProProfiles.plist";
#endif
static NSDictionary *NCCurrentAppearance(void) {
    CFPreferencesAppSynchronize(CFSTR("com.ratnik00.nextclock"));
    NSMutableDictionary *values=[NSMutableDictionary dictionary];
    for (NSString *key in NCAppearanceDefaults()) {
        id value=CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,CFSTR("com.ratnik00.nextclock")));
        if (value) values[key]=value;
    }
    return NCNormalizeAppearance(values);
}

@interface NCPreviewGlyph : NSObject
@property(nonatomic,copy) NSArray<UIImage *> *frames;
@property(nonatomic,copy) NSArray<NSNumber *> *times;
@property(nonatomic) double duration;
@property(nonatomic) NSUInteger cost;
@end
@implementation NCPreviewGlyph
@end

@interface NCPreviewCanvas : UIView
@property(nonatomic,copy) NSDictionary *settings;
@property(nonatomic,strong) NSCache *cache;
@property(nonatomic,strong) UILabel *dateLabel;
@property(nonatomic,strong) UILabel *failure;
@property(nonatomic,strong) NSMutableArray<UIImageView *> *digits;
@property(nonatomic,copy) NSString *signature;
@property(nonatomic,copy) NSDictionary *packInfo;
@property(nonatomic) BOOL active;
- (void)refresh;
- (void)pause;
@end
@implementation NCPreviewCanvas
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.backgroundColor=[UIColor colorWithRed:.07 green:.09 blue:.13 alpha:1];
        self.layer.cornerRadius=20; self.clipsToBounds=YES;
        self.cache=[NSCache new]; self.cache.totalCostLimit=36*1024*1024;
        self.digits=[NSMutableArray array];
        self.dateLabel=[UILabel new]; self.dateLabel.textColor=UIColor.whiteColor;
        self.dateLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; self.dateLabel.adjustsFontForContentSizeCategory=YES; [self addSubview:self.dateLabel];
        self.failure=[UILabel new]; self.failure.textColor=UIColor.whiteColor;
        self.failure.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; self.failure.adjustsFontForContentSizeCategory=YES; self.failure.numberOfLines=0; self.failure.textAlignment=NSTextAlignmentCenter;
        [self addSubview:self.failure];
    } return self;
}
- (void)setSettings:(NSDictionary *)settings {
    NSDictionary *normalized=NCNormalizeAppearance(settings);
    BOOL imageChange=NO;
    for (NSString *key in @[@"pack",@"colorFilterEnabled",@"tintColor"])
        if (![_settings[key] isEqual:normalized[key]]) imageChange=YES;
    _settings=normalized; self.signature=nil;
    if (![self.packInfo[@"id"] isEqual:normalized[@"pack"]]) {
        self.packInfo=nil;
        for (NSDictionary *pack in NCAllPacks()) if ([pack[@"id"] isEqual:normalized[@"pack"]]) { self.packInfo=pack; break; }
    }
    if (imageChange) [self.cache removeAllObjects];
    [self refresh];
}
- (void)pause {
    self.active=NO; self.signature=nil; [self.cache removeAllObjects];
    for (UIImageView *view in self.digits) { [view.layer removeAllAnimations]; view.image=nil; }
}
- (void)layoutSubviews { [super layoutSubviews]; [self refresh]; }
- (NCPreviewGlyph *)glyph:(NSString *)path moving:(BOOL)moving budget:(NSUInteger)budget {
    NSString *key=[NSString stringWithFormat:@"%@:%d",path,moving];
    NCPreviewGlyph *cached=[self.cache objectForKey:key];
    if (cached) return cached.cost<=budget ? cached : nil;
    if (!NCImageValid(path,NO)) return nil;
    CGImageSourceRef source=CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path],NULL);
    if (!source) return nil;
    size_t count=moving ? CGImageSourceGetCount(source) : 1;
    NSMutableArray *frames=[NSMutableArray array], *delays=[NSMutableArray array];
    NSUInteger cost=0; double duration=0;
    for (size_t i=0;i<count;i++) {
        @autoreleasepool {
            CGImageRef cg=CGImageSourceCreateImageAtIndex(source,i,NULL);
            if (!cg) { CFRelease(source); return nil; }
            NSUInteger bytes=CGImageGetBytesPerRow(cg)*CGImageGetHeight(cg);
            if (bytes>budget || cost>budget-bytes) { CGImageRelease(cg); CFRelease(source); return nil; }
            cost+=bytes;
            UIImage *image=[UIImage imageWithCGImage:cg];
            if ([self.settings[@"colorFilterEnabled"] boolValue]) {
                unsigned value=0; [[NSScanner scannerWithString:[self.settings[@"tintColor"] substringFromIndex:1]] scanHexInt:&value];
                UIGraphicsBeginImageContextWithOptions(image.size,NO,image.scale);
                CGContextRef ctx=UIGraphicsGetCurrentContext();
                if (ctx) {
                    CGRect rect=(CGRect){CGPointZero,image.size};
                    CGContextTranslateCTM(ctx,0,image.size.height); CGContextScaleCTM(ctx,1,-1);
                    CGContextDrawImage(ctx,rect,cg); CGContextClipToMask(ctx,rect,cg);
                    CGContextSetBlendMode(ctx,kCGBlendModeColor);
                    CGContextSetFillColorWithColor(ctx,[UIColor colorWithRed:((value>>16)&255)/255.0
                        green:((value>>8)&255)/255.0 blue:(value&255)/255.0 alpha:1].CGColor);
                    CGContextFillRect(ctx,rect); image=UIGraphicsGetImageFromCurrentImageContext() ?: image;
                } UIGraphicsEndImageContext();
            }
            CGImageRelease(cg); [frames addObject:image];
            NSDictionary *props=CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source,i,NULL));
            NSDictionary *gif=props[(__bridge NSString *)kCGImagePropertyGIFDictionary];
            NSDictionary *png=props[(__bridge NSString *)kCGImagePropertyPNGDictionary];
            NSNumber *delay=gif[(__bridge NSString *)kCGImagePropertyGIFUnclampedDelayTime] ?:
                gif[(__bridge NSString *)kCGImagePropertyGIFDelayTime] ?:
                png[(__bridge NSString *)kCGImagePropertyAPNGUnclampedDelayTime] ?: png[(__bridge NSString *)kCGImagePropertyAPNGDelayTime];
            double seconds=delay.doubleValue; if (!isfinite(seconds)||seconds<=0) seconds=.1;
            seconds=MAX(.01,seconds); [delays addObject:@(seconds)]; duration+=seconds;
        }
    }
    CFRelease(source); if (!frames.count || !isfinite(duration)) return nil;
    NSMutableArray *times=[NSMutableArray array]; double elapsed=0;
    for (NSNumber *delay in delays) { [times addObject:@(elapsed/duration)]; elapsed+=delay.doubleValue; }
    [times addObject:@1];
    NCPreviewGlyph *glyph=[NCPreviewGlyph new]; glyph.frames=frames; glyph.times=times;
    glyph.duration=duration; glyph.cost=cost; [self.cache setObject:glyph forKey:key cost:cost]; return glyph;
}
- (void)refresh {
    if (!self.active || !self.settings || self.bounds.size.width<1) return;
    NSDictionary *s=self.settings; NSDate *now=NSDate.date;
    NSDateFormatter *formatter=[NSDateFormatter new]; formatter.locale=[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    BOOL use24=![s[@"timeFormat"] isEqual:@"12hour"];
    if ([s[@"timeFormat"] isEqual:@"system"]) {
        NSString *pattern=[NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:NSLocale.currentLocale];
        use24=[pattern containsString:@"H"] || [pattern containsString:@"k"];
    }
    formatter.dateFormat=[s[@"showSeconds"] boolValue] ? (use24 ? @"HH:mm:ss":@"h:mm:ss") : (use24 ? @"HH:mm":@"h:mm");
    NSString *time=[formatter stringFromDate:now];
    self.accessibilityValue=[NSString stringWithFormat:@"%@, %@",self.packInfo[@"Name"] ?: s[@"pack"],time];
    BOOL moving=!UIAccessibilityIsReduceMotionEnabled() && [s[@"animationStyle"] isEqual:@"animated"] &&
        !([s[@"staticInLowPower"] boolValue] && NSProcessInfo.processInfo.lowPowerModeEnabled);
    formatter.locale=NSLocale.currentLocale; formatter.dateStyle=NSDateFormatterFullStyle; formatter.timeStyle=NSDateFormatterNoStyle;
    self.dateLabel.font=NCDateFont(s,[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]);
    self.dateLabel.text=[formatter stringFromDate:now]; self.dateLabel.hidden=[s[@"hideDate"] boolValue];
    NSString *signature=[NSString stringWithFormat:@"%@:%@:%d",time,NSStringFromCGSize(self.bounds.size),moving];
    if ([signature isEqual:self.signature]) return;
    NSString *folder=nil;
    NSDictionary *pack=self.packInfo;
    if (pack) {
        for (NSString *variant in (moving ? @[@"animated",@"static"]:@[@"static",@"animated"]))
            if ([pack[@"variants"] containsObject:variant]) { folder=[pack[@"path"] stringByAppendingPathComponent:variant]; break; }
    }
    NSMutableArray *glyphs=[NSMutableArray array]; NSMutableDictionary *loaded=[NSMutableDictionary dictionary];
    NSUInteger remaining=48*1024*1024;
    for (NSUInteger i=0;folder && i<time.length;i++) {
        NSString *symbol=[time substringWithRange:NSMakeRange(i,1)];
        NSString *path=NCGlyphPath(folder,[symbol isEqual:@":"] ? @"colon" : symbol);
        NCPreviewGlyph *glyph=path ? loaded[path] : nil;
        if (!glyph && path) { glyph=[self glyph:path moving:moving budget:remaining]; if (glyph) {loaded[path]=glyph;remaining-=glyph.cost;} }
        if (!glyph) { [glyphs removeAllObjects]; break; } [glyphs addObject:glyph];
    }
    for (UIImageView *digit in self.digits) { digit.hidden=YES; digit.image=nil; [digit.layer removeAllAnimations]; }
    self.failure.hidden=glyphs.count>0; self.failure.text=P(folder ? @"Preview unavailable. Try a static pack.":@"Missing pack. Install it or choose another pack.");
    self.failure.frame=CGRectInset(self.bounds,16,20);
    self.dateLabel.hidden=self.dateLabel.hidden || !glyphs.count;
    if (!glyphs.count) { self.signature=nil; return; }
    CGFloat ratio=0; for (NCPreviewGlyph *g in glyphs) ratio+=g.frames[0].size.width/g.frames[0].size.height;
    CGFloat spacing=[s[@"digitSpacing"] doubleValue], gaps=spacing*(glyphs.count-1);
    CGFloat height=MIN(84*[s[@"clockScale"] doubleValue],(self.bounds.size.width-32-gaps)/ratio);
    if (!isfinite(height) || height<=0) { self.failure.hidden=NO; self.dateLabel.hidden=YES; self.signature=nil;return; }
    CGFloat width=height*ratio+gaps, x=(self.bounds.size.width-width)/2;
    CGFloat y=130-height/2+[s[@"verticalOffset"] doubleValue];
    while (self.digits.count<glyphs.count) { UIImageView *digit=[UIImageView new]; digit.contentMode=UIViewContentModeScaleAspectFit; [self addSubview:digit]; [self.digits addObject:digit]; }
    for (NSUInteger i=0;i<glyphs.count;i++) {
        NCPreviewGlyph *g=glyphs[i]; UIImageView *digit=self.digits[i]; CGFloat w=height*g.frames[0].size.width/g.frames[0].size.height;
        digit.frame=CGRectMake(x,y,w,height); digit.hidden=NO; digit.image=g.frames[0]; x+=w+spacing;
        if (moving && g.frames.count>1) {
            NSMutableArray *contents=[NSMutableArray array]; for (UIImage *f in g.frames) [contents addObject:(__bridge id)f.CGImage];
            [contents addObject:contents[0]]; CAKeyframeAnimation *a=[CAKeyframeAnimation animationWithKeyPath:@"contents"];
            a.values=contents; a.keyTimes=g.times; a.calculationMode=kCAAnimationDiscrete;
            a.duration=g.duration/[s[@"animationSpeed"] doubleValue]; a.repeatCount=HUGE_VALF;
            CFTimeInterval now=CACurrentMediaTime();
            a.beginTime=[digit.layer convertTime:now fromLayer:nil]-fmod(now,a.duration);
            [digit.layer addAnimation:a forKey:@"NextClock.preview"];
        }
    }
    self.dateLabel.frame=CGRectMake(12,y+height+10,self.bounds.size.width-24,MAX(30,self.dateLabel.font.lineHeight));
    self.dateLabel.textAlignment=NSTextAlignmentCenter; self.dateLabel.adjustsFontSizeToFitWidth=YES;
    self.signature=signature;
}
@end

@interface NCEditorChoices : UITableViewController
@property(nonatomic,copy) NSArray *choices;
@property(nonatomic,copy) NSString *selected;
@property(nonatomic,copy) void (^choose)(NSString *value);
@end
@implementation NCEditorChoices
- (void)viewDidLoad { [super viewDidLoad]; self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=44; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.choices.count; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"choice"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"choice"];
    NSDictionary *choice=self.choices[index.row]; cell.textLabel.text=choice[@"name"];
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory=YES; cell.textLabel.numberOfLines=0;
    BOOL selected=[self.selected isEqual:choice[@"value"]];
    cell.accessoryType=selected ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.accessibilityTraits=UIAccessibilityTraitButton | (selected ? UIAccessibilityTraitSelected : 0);
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    self.selected=self.choices[index.row][@"value"]; [table reloadData];
    if (self.choose) self.choose(self.selected);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface NCProController ()
@property(nonatomic,strong) NSMutableDictionary *draft;
@property(nonatomic,copy) NSDictionary *appliedBaseline;
@property(nonatomic,strong) NCPreviewCanvas *canvas;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic) BOOL pageVisible;
@property(nonatomic,copy) NSArray *sections;
@end
@implementation NCProController
- (void)message:(NSString *)message title:(NSString *)title {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:P(title) message:P(message) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (instancetype)init {
    UITableViewStyle style=UITableViewStyleGrouped;
    if (@available(iOS 13.0,*)) style=UITableViewStyleInsetGrouped;
    return [super initWithStyle:style];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=P(@"Configure clock");
#ifdef NC_PRO_BUILD
    self.title=P(@"Preview & Profiles"); self.sections=NCEditorSections(YES);
#else
    self.sections=NCEditorSections(NO);
#endif
    if (@available(iOS 16.0, *)) {
        self.sections = [self.sections arrayByAddingObject:@{
            @"title": @"Lock Screen wallpaper",
            @"rows": @[
                NCEditorRow(@"applyWallpaperPack", @"Apply to current Lock Screen", @"action"),
                NCEditorRow(@"clearWallpaperPack", @"Use global pack on this Lock Screen", @"action")
            ]
        }];
    }
    self.appliedBaseline=NCCurrentAppearance(); self.draft=[self.appliedBaseline mutableCopy];
    self.tableView.rowHeight=UITableViewAutomaticDimension; self.tableView.estimatedRowHeight=64;
    self.canvas=[NCPreviewCanvas new]; [self.canvas.heightAnchor constraintEqualToConstant:300].active=YES; self.canvas.settings=self.draft;
    self.canvas.isAccessibilityElement=YES; self.canvas.accessibilityLabel=P(@"Preview");
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:P(@"Apply") style:UIBarButtonItemStyleDone target:self action:@selector(apply)];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(powerChanged:) name:NSProcessInfoPowerStateDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(powerChanged:) name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(background:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(foreground:) name:UIApplicationWillEnterForegroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(textSizeChanged:) name:UIContentSizeCategoryDidChangeNotification object:nil];
    [self updateDraft];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return P(self.sections[section][@"title"]); }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section { NSString *text=self.sections[section][@"footer"]; return text ? P(text) : nil; }
- (NSDictionary *)row:(NSIndexPath *)index { return self.sections[index.section][@"rows"][index.row]; }
- (NSString *)valueText:(NSString *)key {
    if ([key isEqual:@"pack"]) { for (NSDictionary *pack in NCAllPacks()) if ([pack[@"id"] isEqual:self.draft[key]]) return pack[@"Name"]; }
    if ([key isEqual:@"tintColor"]) { for (NSDictionary *color in [self colorChoices]) if ([color[@"value"] isEqual:self.draft[key]]) return P(color[@"name"]); }
    if ([key isEqual:@"dateFontDesign"]) return P(@{@"system":@"System",@"rounded":@"Rounded",@"serif":@"Serif",@"monospaced":@"Monospaced"}[self.draft[key]] ?: @"System");
    if ([key isEqual:@"dateFontWeight"]) return P(@{@"system":@"System",@"regular":@"Regular",@"medium":@"Medium",@"semibold":@"Semibold",@"bold":@"Bold"}[self.draft[key]] ?: @"System");
    if ([key isEqual:@"timeFormat"]) return P(@{@"system":@"System",@"12hour":@"12-hour",@"24hour":@"24-hour"}[self.draft[key]] ?: @"System");
    return self.draft[key] ?: @"";
}
- (NSString *)displayNumber:(NSNumber *)number key:(NSString *)key {
    if (![key isEqual:@"dateFontScale"]) return [self numberText:number];
    NSNumberFormatter *formatter=[NSNumberFormatter new]; formatter.numberStyle=NSNumberFormatterPercentStyle;
    formatter.maximumFractionDigits=0; return [formatter stringFromNumber:number];
}
- (NSString *)numberText:(NSNumber *)number {
    NSNumberFormatter *formatter=[NSNumberFormatter new]; formatter.numberStyle=NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits=0; formatter.maximumFractionDigits=2;
    return [formatter stringFromNumber:number];
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    NSDictionary *row=[self row:index]; NSString *key=row[@"key"],*kind=row[@"kind"];
    // Cells with embedded controls have independent lifetimes, avoiding stale targets
    // and constraints when Dynamic Type changes or Pro loads an entire profile.
    UITableViewCell *cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; cell.textLabel.adjustsFontForContentSizeCategory=YES; cell.textLabel.numberOfLines=0;
    cell.detailTextLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; cell.detailTextLabel.adjustsFontForContentSizeCategory=YES; cell.detailTextLabel.numberOfLines=0;
    cell.textLabel.text=P(row[@"title"]); cell.selectionStyle=UITableViewCellSelectionStyleNone;
    if ([kind isEqual:@"preview"]) {
        cell.textLabel.text=nil; [self.canvas removeFromSuperview]; self.canvas.translatesAutoresizingMaskIntoConstraints=NO;
        [cell.contentView addSubview:self.canvas]; UILayoutGuide *m=cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[[self.canvas.topAnchor constraintEqualToAnchor:m.topAnchor], [self.canvas.bottomAnchor constraintEqualToAnchor:m.bottomAnchor], [self.canvas.leadingAnchor constraintEqualToAnchor:m.leadingAnchor], [self.canvas.trailingAnchor constraintEqualToAnchor:m.trailingAnchor]]];
        return cell;
    }
    if ([kind isEqual:@"toggle"]) {
        UISwitch *toggle=[UISwitch new]; toggle.accessibilityLabel=P(row[@"title"]); toggle.accessibilityIdentifier=key;
        toggle.on=[key isEqual:@"animationStyle"] ? [self.draft[key] isEqual:@"animated"] : [self.draft[key] boolValue];
        [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView=toggle;
        // VoiceOver visits the switch with its complete label and native on/off state.
        cell.isAccessibilityElement=NO; cell.textLabel.isAccessibilityElement=NO;
    } else if ([kind isEqual:@"slider"]) {
        cell.textLabel.text=nil; UILabel *label=[UILabel new]; label.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody]; label.adjustsFontForContentSizeCategory=YES; label.numberOfLines=0;
        label.text=[NSString stringWithFormat:@"%@: %@",P(row[@"title"]),[self displayNumber:self.draft[key] key:key]]; label.isAccessibilityElement=NO;
        UISlider *slider=[UISlider new]; NSDictionary *limits=@{@"clockScale":@[@0.3,@2.5],@"digitSpacing":@[@(-25),@40],@"verticalOffset":@[@(-120),@120],@"animationSpeed":@[@0.25,@3],@"dateFontScale":@[@0.6,@1.6]};
        slider.minimumValue=[limits[key][0] floatValue]; slider.maximumValue=[limits[key][1] floatValue]; slider.value=[self.draft[key] floatValue];
        slider.accessibilityLabel=P(row[@"title"]); slider.accessibilityValue=[self displayNumber:self.draft[key] key:key]; slider.accessibilityIdentifier=key;
        [slider addTarget:self action:@selector(slide:) forControlEvents:UIControlEventValueChanged];
        UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[label,slider]]; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=8; stack.translatesAutoresizingMaskIntoConstraints=NO;
        [cell.contentView addSubview:stack]; UILayoutGuide *m=cell.contentView.layoutMarginsGuide;
        [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:m.topAnchor], [stack.bottomAnchor constraintEqualToAnchor:m.bottomAnchor], [stack.leadingAnchor constraintEqualToAnchor:m.leadingAnchor], [stack.trailingAnchor constraintEqualToAnchor:m.trailingAnchor], [slider.heightAnchor constraintGreaterThanOrEqualToConstant:44]]];
    } else {
        cell.accessoryType=[kind isEqual:@"choice"] ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone; cell.selectionStyle=UITableViewCellSelectionStyleDefault;
        if ([kind isEqual:@"action"]) cell.textLabel.textColor=cell.tintColor;
        cell.accessibilityTraits=UIAccessibilityTraitButton;
        if ([kind isEqual:@"choice"]) cell.detailTextLabel.text=[self valueText:key];
    }
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES]; NSDictionary *row=[self row:index]; NSString *key=row[@"key"];
    if ([row[@"kind"] isEqual:@"choice"]) {
        if ([key isEqual:@"pack"]) [self choosePack];
        else if ([key isEqual:@"tintColor"]) [self chooseColor];
        else if ([key isEqual:@"dateFontDesign"] || [key isEqual:@"dateFontWeight"]) [self chooseDateOption:key];
        else [self chooseFormat];
    }
    else if ([row[@"kind"] isEqual:@"action"]) {
        if ([key isEqual:@"applyWallpaperPack"]) [self saveWallpaperPack:YES];
        else if ([key isEqual:@"clearWallpaperPack"]) [self saveWallpaperPack:NO];
#ifdef NC_PRO_BUILD
        else if ([key isEqual:@"saveProfile"]) [self saveProfile];
        else if ([key isEqual:@"showProfiles"]) [self showProfiles];
#endif
    }
}
- (void)tableView:(UITableView *)table willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)index {
    if (index.section==0 && index.row==0) {
        __weak NCProController *weakSelf=self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf startPreview]; });
    }
}
- (void)tableView:(UITableView *)table didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)index {
    if (index.section==0 && index.row==0) [self stopPreview];
}
- (void)syncControls { [self.tableView reloadData]; [self updateDraft]; }
- (void)updateDraft { self.canvas.settings=self.draft; self.navigationItem.rightBarButtonItem.enabled=![NCNormalizeAppearance(self.draft) isEqual:self.appliedBaseline]; }
- (void)textSizeChanged:(NSNotification *)note { self.canvas.signature=nil; [self.tableView reloadData]; [self.canvas refresh]; }
- (void)toggle:(UISwitch *)sender {
    self.draft[sender.accessibilityIdentifier]=[sender.accessibilityIdentifier isEqual:@"animationStyle"] ? (sender.on ? @"animated":@"static") : @(sender.on); [self updateDraft];
}
- (void)slide:(UISlider *)sender {
    NSString *key=sender.accessibilityIdentifier; self.draft[key]=@(sender.value); sender.accessibilityValue=[self displayNumber:@(sender.value) key:key];
    UIStackView *stack=[sender.superview isKindOfClass:UIStackView.class] ? (UIStackView *)sender.superview : nil;
    UILabel *label=[stack.arrangedSubviews.firstObject isKindOfClass:UILabel.class] ? (UILabel *)stack.arrangedSubviews.firstObject : nil;
    label.text=[NSString stringWithFormat:@"%@: %@",sender.accessibilityLabel,sender.accessibilityValue]; [self updateDraft];
}
- (void)showChoices:(NSArray *)choices key:(NSString *)key title:(NSString *)title {
    UITableViewStyle style=UITableViewStyleGrouped; if (@available(iOS 13.0,*)) style=UITableViewStyleInsetGrouped;
    NCEditorChoices *controller=[[NCEditorChoices alloc] initWithStyle:style]; controller.title=P(title);
    controller.choices=choices; controller.selected=self.draft[key]; __weak NCProController *weakSelf=self;
    controller.choose=^(NSString *value){ weakSelf.draft[key]=value; [weakSelf syncControls]; };
    [self.navigationController pushViewController:controller animated:YES];
}
- (void)chooseDateOption:(NSString *)key {
    BOOL design=[key isEqual:@"dateFontDesign"];
    NSArray *values=design ? @[@"system",@"rounded",@"serif",@"monospaced"] : @[@"system",@"regular",@"medium",@"semibold",@"bold"];
    NSArray *names=design ? @[@"System",@"Rounded",@"Serif",@"Monospaced"] : @[@"System",@"Regular",@"Medium",@"Semibold",@"Bold"];
    NSMutableArray *choices=[NSMutableArray array];
    for (NSUInteger i=0;i<values.count;i++) [choices addObject:@{@"name":P(names[i]),@"value":values[i]}];
    [self showChoices:choices key:key title:design ? @"Date font" : @"Date weight"];
}
- (void)chooseFormat { [self showChoices:@[@{@"name":P(@"System"),@"value":@"system"},@{@"name":P(@"12-hour"),@"value":@"12hour"},@{@"name":P(@"24-hour"),@"value":@"24hour"}] key:@"timeFormat" title:@"Format"]; }
- (NSArray *)colorChoices { return @[@{@"name":@"Orange",@"value":@"#FF9500"},@{@"name":@"Red",@"value":@"#FF3B30"},@{@"name":@"Pink",@"value":@"#FF2D55"},@{@"name":@"Purple",@"value":@"#AF52DE"},@{@"name":@"Indigo",@"value":@"#5856D6"},@{@"name":@"Blue",@"value":@"#007AFF"},@{@"name":@"Green",@"value":@"#34C759"},@{@"name":@"Yellow",@"value":@"#FFCC00"},@{@"name":@"Teal",@"value":@"#00C7BE"},@{@"name":@"Black & white",@"value":@"#FFFFFF"},@{@"name":@"Grey",@"value":@"#8E8E93"}]; }
- (void)chooseColor {
    NSMutableArray *choices=[NSMutableArray array];
    for (NSDictionary *color in [self colorChoices]) [choices addObject:@{@"name":P(color[@"name"]),@"value":color[@"value"]}];
    [self showChoices:choices key:@"tintColor" title:@"Color"];
}
- (void)choosePack {
    NSMutableArray *choices=[NSMutableArray array];
    for (NSDictionary *pack in NCAllPacks()) [choices addObject:@{@"name":pack[@"Name"],@"value":pack[@"id"]}];
    [self showChoices:choices key:@"pack" title:@"Pack"];
}
- (void)presentSheet:(UIAlertController *)alert {
    [alert addAction:[UIAlertAction actionWithTitle:P(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    alert.popoverPresentationController.sourceView=self.view;
    alert.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)packExists:(NSString *)identifier { for (NSDictionary *pack in NCAllPacks()) if ([pack[@"id"] isEqual:identifier]) return YES; return NO; }
- (void)saveWallpaperPack:(BOOL)assign {
    NSString *identifier = NCSelectedWallpaper();
    if (!identifier) {
        [self message:@"Could not read the selected Lock Screen." title:@"Error"];
        return;
    }
    NSString *pack = self.draft[@"pack"];
    if (assign && ![self packExists:pack]) {
        [self message:@"Missing pack. Install it or choose another pack." title:@"Error"];
        return;
    }
    CFStringRef domain = CFSTR("com.ratnik00.nextclock");
    CFPreferencesAppSynchronize(domain);
    NSMutableDictionary *bindings = NCWallpaperPackBindings();
    if (assign && !bindings[identifier] && bindings.count >= 128) {
        [self message:@"Remove a wallpaper pack assignment before adding another." title:@"Error"];
        return;
    }
    if (assign) bindings[identifier] = pack;
    else [bindings removeObjectForKey:identifier];
    CFPreferencesSetAppValue(CFSTR("wallpaperPacks"), (__bridge CFPropertyListRef)bindings, domain);
    if (!CFPreferencesAppSynchronize(domain)) {
        [self message:@"Could not save settings." title:@"Error"];
        return;
    }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.ratnik00.nextclock/preferenceschanged"), NULL, NULL, YES);
    [self message:assign ? @"Pack saved for the current Lock Screen." :
        @"This Lock Screen uses the global pack." title:@"Applied"];
}
- (void)apply {
    if (![self packExists:self.draft[@"pack"]]) { [self message:@"Missing pack. Install it or choose another pack." title:@"Error"]; return; }
    NSDictionary *values=NCNormalizeAppearance(self.draft);
    for (NSString *key in values) CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)values[key],CFSTR("com.ratnik00.nextclock"));
    if (!CFPreferencesAppSynchronize(CFSTR("com.ratnik00.nextclock"))) { [self message:@"Could not save settings." title:@"Error"]; return; }
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.ratnik00.nextclock/preferenceschanged"),NULL,NULL,YES);
    self.appliedBaseline=values; [self updateDraft];
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,P(@"Applied"));
}
#ifdef NC_PRO_BUILD
- (NSMutableArray *)profiles {
    NSError *error=nil; NSArray *profiles=NCReadProfiles(NCProfilePath,&error);
    if (!profiles) { [self message:error.localizedDescription title:@"Error"]; return nil; } return [profiles mutableCopy];
}
- (void)writeProfiles:(NSArray *)profiles { NSError *error=nil; if (!NCWriteProfiles(NCProfilePath,profiles,&error)) [self message:error.localizedDescription ?: @"Could not save profiles." title:@"Error"]; }
- (void)nameProfile:(NSDictionary *)existing {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:P(existing ? @"Rename":@"Save Profile") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=P(@"Profile name (1–60 characters)");field.text=existing[@"name"];}];
    __weak UIAlertController *weakAlert=alert;
    [alert addAction:[UIAlertAction actionWithTitle:P(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:P(@"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        NSString *name=NCProfileName(weakAlert.textFields[0].text);
        if (!name) { [self message:@"Name must contain 1–60 characters." title:@"Error"]; return; }
        NSMutableArray *profiles=[self profiles]; if (!profiles) return;
        if (existing) {
            for (NSUInteger i=0;i<profiles.count;i++) if ([profiles[i][@"id"] isEqual:existing[@"id"]]) {
                NSMutableDictionary *record=[profiles[i] mutableCopy];record[@"name"]=name;profiles[i]=record;[self writeProfiles:profiles];return;
            }
        } else {
            if (profiles.count>=20) { [self message:@"Maximum 20 profiles." title:@"Error"];return; }
            [profiles addObject:@{@"id":NSUUID.UUID.UUIDString,@"name":name,@"settings":NCNormalizeAppearance(self.draft)}]; [self writeProfiles:profiles];
        }
    }]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)saveProfile { [self nameProfile:nil]; }
- (void)showProfiles {
    NSArray *profiles=[self profiles]; if (!profiles) return;
    if (!profiles.count) { [self message:@"No saved profiles yet." title:@"Profiles"];return; }
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:P(@"Profiles") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *profile in profiles) [sheet addAction:[UIAlertAction actionWithTitle:profile[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self manageProfile:profile];}]];
    [self presentSheet:sheet];
}
- (void)manageProfile:(NSDictionary *)profile {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:profile[@"name"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:P(@"Load") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        if (![self packExists:profile[@"settings"][@"pack"]]) { [self message:@"Missing pack. Install it or choose another pack." title:@"Error"];return; }
        self.draft=[NCNormalizeAppearance(profile[@"settings"]) mutableCopy];[self syncControls];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:P(@"Rename") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self nameProfile:profile];}]];
    [sheet addAction:[UIAlertAction actionWithTitle:P(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:P(@"Delete this profile?") message:profile[@"name"] preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:P(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:P(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
            NSMutableArray *current=[self profiles]; if (!current) return;
            NSIndexSet *matches=[current indexesOfObjectsPassingTest:^BOOL(NSDictionary *record,NSUInteger i,BOOL *stop){return [record[@"id"] isEqual:profile[@"id"]];}];
            [current removeObjectsAtIndexes:matches];[self writeProfiles:current];
        }]]; [self presentViewController:confirm animated:YES completion:nil];
    }]]; [self presentSheet:sheet];
}
#endif
- (void)powerChanged:(NSNotification *)note {
    __weak NCProController *weakSelf=self;
    dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf.pageVisible) [weakSelf.canvas refresh]; });
}
- (void)startPreview {
    if (self.timer || !self.pageVisible || !self.view.window || !self.canvas.window) return; self.canvas.active=YES; [self.canvas refresh];
    __weak NCProController *weakSelf=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *timer){[weakSelf.canvas refresh];}];
    self.timer.tolerance=.1;
}
- (void)stopPreview { [self.timer invalidate]; self.timer=nil; [self.canvas pause]; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; self.pageVisible=YES; [self startPreview]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; self.pageVisible=NO; [self stopPreview]; }
- (void)background:(NSNotification *)note { [self stopPreview]; }
- (void)foreground:(NSNotification *)note { [self startPreview]; }
- (void)dealloc { [self.timer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
