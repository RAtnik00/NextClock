#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dispatch/dispatch.h>

// View-specific guard: nested system callbacks must not re-enter our layout.
// Always release on Objective-C exceptions; never swallow an exception.
static inline void NCPerformGuarded(id owner, const void *key, dispatch_block_t work) {
    if ([objc_getAssociatedObject(owner,key) boolValue]) return;
    objc_setAssociatedObject(owner,key,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    @try { work(); }
    @finally { objc_setAssociatedObject(owner,key,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
}

// A selector's presence alone does not establish a safe hook calling convention.
static inline BOOL NCMethodHasABI(Class cls, SEL selector, const char *result, NSArray<NSString *> *arguments) {
    Method method=cls ? class_getInstanceMethod(cls,selector) : NULL;
    if (!method || method_getNumberOfArguments(method)!=arguments.count+2) return NO;
    char *type=method_copyReturnType(method);
    BOOL matches=type && (strcmp(type,result)==0 || (result[0]=='@' && type[0]=='@'));
    free(type); if (!matches) return NO;
    for (NSUInteger i=0;i<arguments.count;i++) {
        type=method_copyArgumentType(method,(unsigned)i+2);
        const char *wanted=arguments[i].UTF8String;
        matches=type && (strcmp(type,wanted)==0 ||
            (wanted[0]=='@' && type[0]=='@') ||
            (strcmp(wanted,"BOOL")==0 && (strcmp(type,"B")==0 || strcmp(type,"c")==0)));
        free(type); if (!matches) return NO;
    }
    return YES;
}
