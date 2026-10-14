#import <Foundation/Foundation.h>
#import <zlib.h>
#import "NCPacks.h"

static inline uint16_t NCLE16(const uint8_t *b) { return b[0] | ((uint16_t)b[1] << 8); }
static inline uint32_t NCLE32(const uint8_t *b) { return NCLE16(b) | ((uint32_t)NCLE16(b + 2) << 16); }
// Bounded ZIP reader: stored/deflated files only, no encryption, ZIP64 or symlinks.
// Only pack metadata and glyph files are written. All archive names are checked first.
static inline BOOL NCExtractZip(NSString *archive, NSString *target, NSError **error) {
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:archive error:error];
    if ([attrs[NSFileSize] unsignedLongLongValue] > 64 * 1024 * 1024) { if (error) *error=NCError(@"Archive exceeds 64 MB."); return NO; }
    NSData *data = [NSData dataWithContentsOfFile:archive options:NSDataReadingMappedIfSafe error:error];
    if (!data || data.length < 22) { if (error && !*error) *error=NCError(@"Not a supported ZIP or .nextclock archive."); return NO; }
    const uint8_t *b = data.bytes; NSUInteger length = data.length;
    NSInteger end = -1;
    for (NSInteger i = (NSInteger)length-22; i >= MAX(0, (NSInteger)length-65557); i--) {
        if (NCLE32(b+i)==0x06054b50 && (NSUInteger)i+22+NCLE16(b+i+20)==length) { end=i; break; }
    }
    if (end < 0 || NCLE16(b+end+4) || NCLE16(b+end+6) || NCLE16(b+end+8)!=NCLE16(b+end+10)) {
        if (error) *error=NCError(@"Unsupported ZIP structure."); return NO;
    }
    NSUInteger count=NCLE16(b+end+10), size=NCLE32(b+end+12), offset=NCLE32(b+end+16);
    if (!count || count>512 || offset>(NSUInteger)end || size>(NSUInteger)end-offset) { if (error) *error=NCError(@"Invalid ZIP directory."); return NO; }
    NSUInteger cursor=offset, total=0; NSMutableArray *entries=[NSMutableArray array]; NSMutableSet *seen=[NSMutableSet set];
    for (NSUInteger i=0; i<count; i++) {
        if (cursor>length || length-cursor<46 || NCLE32(b+cursor)!=0x02014b50) goto invalid;
        NSUInteger nameLength=NCLE16(b+cursor+28), extra=NCLE16(b+cursor+30), comment=NCLE16(b+cursor+32);
        NSUInteger entryLength=46+nameLength+extra+comment;
        if (entryLength>length-cursor || cursor+entryLength>offset+size) goto invalid;
        NSString *name=[[NSString alloc] initWithBytes:b+cursor+46 length:nameLength encoding:NSUTF8StringEncoding];
        if (!name.length || [name hasPrefix:@"/"] || [name containsString:@"\\"] || [name rangeOfString:@"\0"].location!=NSNotFound) goto invalid;
        for (NSString *component in [name componentsSeparatedByString:@"/"]) if ([component isEqual:@".."] || [component isEqual:@"."]) goto invalid;
        if ([seen containsObject:name]) goto invalid; [seen addObject:name];
        uint32_t mode=NCLE32(b+cursor+38)>>16;
        if ((mode & 0170000)==0120000) goto invalid;
        NSUInteger compressed=NCLE32(b+cursor+20), expanded=NCLE32(b+cursor+24);
        NSUInteger method=NCLE16(b+cursor+10), flags=NCLE16(b+cursor+8), local=NCLE32(b+cursor+42);
        if ((flags & 1) || (method!=0 && method!=8) || expanded>8*1024*1024 || compressed>64*1024*1024 || local>=length) goto invalid;
        if (total>64*1024*1024-expanded) goto invalid; total+=expanded;
        NSString *leaf=name.lastPathComponent, *parent=name.stringByDeletingLastPathComponent.lastPathComponent;
        BOOL wanted=[leaf isEqual:@"Info.plist"] ||
            ([@[@"static",@"animated"] containsObject:parent] &&
             [NCGlyphNames() containsObject:leaf.stringByDeletingPathExtension] &&
             [@[@"gif",@"png"] containsObject:leaf.pathExtension.lowercaseString]);
        if (wanted && ![name hasSuffix:@"/"]) [entries addObject:@{@"name":name,@"compressed":@(compressed),@"expanded":@(expanded),@"method":@(method),@"local":@(local),@"crc":@(NCLE32(b+cursor+16))}];
        cursor+=entryLength;
    }
    if (!entries.count) goto invalid;
    for (NSDictionary *entry in entries) {
        NSUInteger local=[entry[@"local"] unsignedIntegerValue], compressed=[entry[@"compressed"] unsignedIntegerValue], expanded=[entry[@"expanded"] unsignedIntegerValue];
        if (local>length || length-local<30 || NCLE32(b+local)!=0x04034b50) goto invalid;
        NSUInteger nameLength=NCLE16(b+local+26), extra=NCLE16(b+local+28);
        if (30+nameLength+extra>length-local) goto invalid;
        NSString *localName=[[NSString alloc] initWithBytes:b+local+30 length:nameLength encoding:NSUTF8StringEncoding];
        if (![localName isEqual:entry[@"name"]] || NCLE16(b+local+8)!=[entry[@"method"] unsignedIntValue]) goto invalid;
        NSUInteger start=local+30+nameLength+extra; if (compressed>length-start) goto invalid;
        NSMutableData *out=[NSMutableData dataWithLength:MAX((NSUInteger)1,expanded)];
        if ([entry[@"method"] unsignedIntValue]==0) {
            if (compressed!=expanded) goto invalid; memcpy(out.mutableBytes,b+start,expanded);
        } else {
            z_stream stream={0}; stream.next_in=(Bytef *)(b+start); stream.avail_in=(uInt)compressed;
            stream.next_out=out.mutableBytes; stream.avail_out=(uInt)out.length;
            if (inflateInit2(&stream,-MAX_WBITS)!=Z_OK) goto invalid;
            int result=inflate(&stream,Z_FINISH); BOOL ok=result==Z_STREAM_END && stream.total_out==expanded && stream.total_in==compressed;
            inflateEnd(&stream); if (!ok) goto invalid;
        }
        out.length=expanded;
        if ((uint32_t)crc32(0,out.bytes,(uInt)expanded)!=[entry[@"crc"] unsignedIntValue]) goto invalid;
        NSString *path=[target stringByAppendingPathComponent:entry[@"name"]];
        if (![NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error] ||
            ![out writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    }
    return YES;
invalid:
    if (error) *error=NCError(@"Archive is damaged or uses an unsupported format. Use a normal ZIP containing Info.plist and static/ or animated/.");
    return NO;
}
