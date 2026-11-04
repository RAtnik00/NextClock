#import "../Shared/NCLayoutSafety.h"
@interface NCABIFixture : NSObject
- (NSDate *)date;
- (void)setDate:(NSDate *)value;
- (void)visibility:(double)value flag:(BOOL)flag;
@end
@implementation NCABIFixture
- (NSDate *)date { return nil; }
- (void)setDate:(NSDate *)value {}
- (void)visibility:(double)value flag:(BOOL)flag {}
@end
static char Key;
static void Check(BOOL ok) { if(!ok) exit(1); }
int main(void) { @autoreleasepool {
    Check(NCMethodHasABI(NCABIFixture.class,@selector(date),"@",@[]));
    Check(NCMethodHasABI(NCABIFixture.class,@selector(setDate:),"v",@[@"@"]));
    Check(NCMethodHasABI(NCABIFixture.class,@selector(visibility:flag:),"v",@[@"d",@"BOOL"]));
    Check(!NCMethodHasABI(NCABIFixture.class,@selector(date),"v",@[]));
    Check(!NCMethodHasABI(NCABIFixture.class,@selector(setDate:),"v",@[@"d"]));
    Check(!NCMethodHasABI(NCABIFixture.class,@selector(setDate:),"v",@[]));
    Check(!NCMethodHasABI(Nil,@selector(date),"@",@[]));
    Check(!NCMethodHasABI(NCABIFixture.class,NSSelectorFromString(@"absent"),"@",@[]));
    NSObject *a=[NSObject new],*b=[NSObject new]; __block int calls=0;
    NCPerformGuarded(a,&Key,^{calls++;NCPerformGuarded(a,&Key,^{calls+=100;});NCPerformGuarded(b,&Key,^{calls++;});});
    Check(calls==2);NCPerformGuarded(a,&Key,^{calls++;});Check(calls==3);
    @try { NCPerformGuarded(a,&Key,^{@throw [NSException exceptionWithName:@"fixture" reason:nil userInfo:nil];}); }
    @catch(NSException *error) { Check([error.name isEqual:@"fixture"]); }
    NCPerformGuarded(a,&Key,^{calls++;});Check(calls==4);
    Check(!objc_getAssociatedObject(a,&Key) && !objc_getAssociatedObject(b,&Key));
    puts("PASS: ABI object/scalar/bool contracts and missing/mismatched methods; same-view recursive entry blocked; separate views independent; normal/exception exits release guard.");
} return 0; }
