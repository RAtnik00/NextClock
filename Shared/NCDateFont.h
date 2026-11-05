#import <UIKit/UIKit.h>
#import "NCDateStyle.h"
static inline UIFont *NCDateFont(NSDictionary *input, UIFont *original) {
    if (!original || NCDateStyleIsSystem(input)) return original;
    NSDictionary *s=NCNormalizeDateStyle(input); CGFloat size=MAX(8,MIN(80,original.pointSize*[s[@"dateFontScale"] doubleValue]));
    NSString *design=s[@"dateFontDesign"],*weightName=s[@"dateFontWeight"];
    if ([design isEqual:@"system"] && [weightName isEqual:@"system"]) return [original fontWithSize:size];
    id nativeWeight=original.fontDescriptor.fontAttributes[UIFontDescriptorTraitsAttribute][UIFontWeightTrait];
    CGFloat weight=[nativeWeight isKindOfClass:NSNumber.class] ? [nativeWeight doubleValue] : UIFontWeightRegular;
    NSDictionary *weights=@{@"regular":@(UIFontWeightRegular),@"medium":@(UIFontWeightMedium),@"semibold":@(UIFontWeightSemibold),@"bold":@(UIFontWeightBold)};
    if (weights[weightName]) weight=[weights[weightName] doubleValue];
    UIFont *font=[UIFont systemFontOfSize:size weight:weight];
    if (@available(iOS 13.0,*)) {
        UIFontDescriptorSystemDesign family=@{@"rounded":UIFontDescriptorSystemDesignRounded,@"serif":UIFontDescriptorSystemDesignSerif,@"monospaced":UIFontDescriptorSystemDesignMonospaced}[design];
        if (family) { UIFontDescriptor *descriptor=[font.fontDescriptor fontDescriptorWithDesign:family]; if (descriptor) font=[UIFont fontWithDescriptor:descriptor size:size]; }
    }
    return font ?: original;
}
