#import <Foundation/Foundation.h>
#import "../Shared/NCZip.h"

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 3, @"fixture and bundled-pack directory arguments");
        NSString *root = @(argv[1]);
        NSString *pack = [root stringByAppendingPathComponent:@"pack"];
        Check(NCPackInfo(pack, @"test", YES, YES) != nil, @"valid static pack");
        Check(NCResolvePickedFolder(root) != nil, @"enclosed pack folder");
        Check(!NCImageValid([root stringByAppendingPathComponent:@"broken.png"], YES), @"broken image rejected");
        Check(!NCImageValid([root stringByAppendingPathComponent:@"image-link.png"], YES), @"image symlink rejected");
        Check(!NCValidIdentifier(@"../bad") && !NCValidIdentifier(@".incoming-test"), @"invalid identifiers");
        NSArray *good = @[@"stored.zip", @"deflated.zip", @"descriptor.zip"];
        NSArray *bad = @[@"traversal.zip", @"symlink.zip", @"duplicate.zip", @"crc.zip", @"local-flags.zip", @"central-gap.zip", @"double-slash.zip", @"truncated.zip", @"encrypted.zip", @"oversized.zip"];
        for (NSString *name in [good arrayByAddingObjectsFromArray:bad]) {
            NSString *destination = [root stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            [NSFileManager.defaultManager createDirectoryAtPath:destination withIntermediateDirectories:YES attributes:nil error:NULL];
            NSError *error = nil;
            BOOL success = NCExtractZip([root stringByAppendingPathComponent:name], destination, &error);
            BOOL expected = [good containsObject:name];
            Check(success == expected, [NSString stringWithFormat:@"ZIP %@ expected %@: %@", name, @(expected), error]);
            if (success) Check(NCResolvePickedFolder(destination) != nil, [@"extracted pack " stringByAppendingString:name]);
            else Check(error != nil, [@"error returned for " stringByAppendingString:name]);
        }
        NSString *bundledRoot = @(argv[2]);
        NSArray *bundled = [NSFileManager.defaultManager contentsOfDirectoryAtPath:bundledRoot error:NULL];
        NSUInteger checked = 0;
        for (NSString *name in bundled) {
            if (!NCValidIdentifier(name)) continue;
            NSString *path = [bundledRoot stringByAppendingPathComponent:name];
            NSDictionary *info = NCPackInfo(path, name, NO, YES);
            Check(info != nil, [@"bundled pack passes full ImageIO decode: " stringByAppendingString:name]);
            checked++;
        }
        Check(checked >= 6, @"all six bundled packs, including Halloween");
        printf("PASS: %lu bundled packs fully decoded.\n", (unsigned long)checked);
        puts("PASS: pack validation, 3 supported ZIP formats and 10 malformed archives.");
    }
    return 0;
}
