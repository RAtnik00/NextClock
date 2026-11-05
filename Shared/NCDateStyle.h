#import <Foundation/Foundation.h>
#import <math.h>
static inline NSDictionary *NCDateStyleDefaults(void) {
    return @{@"dateFontDesign":@"system",@"dateFontScale":@1,@"dateFontWeight":@"system"};
}
static inline NSDictionary *NCNormalizeDateStyle(id input) {
    NSDictionary *s=[input isKindOfClass:NSDictionary.class] ? input : @{};
    NSMutableDictionary *out=[NCDateStyleDefaults() mutableCopy];
    if ([@[@"system",@"rounded",@"serif",@"monospaced"] containsObject:s[@"dateFontDesign"] ?: NSNull.null]) out[@"dateFontDesign"]=s[@"dateFontDesign"];
    if ([@[@"system",@"regular",@"medium",@"semibold",@"bold"] containsObject:s[@"dateFontWeight"] ?: NSNull.null]) out[@"dateFontWeight"]=s[@"dateFontWeight"];
    id value=s[@"dateFontScale"]; double scale=[value isKindOfClass:NSNumber.class] ? [value doubleValue] : NAN;
    if (isfinite(scale)) out[@"dateFontScale"]=@(MAX(.6,MIN(1.6,scale)));
    return out;
}
static inline BOOL NCDateStyleIsSystem(NSDictionary *s) { return [NCNormalizeDateStyle(s) isEqual:NCDateStyleDefaults()]; }
