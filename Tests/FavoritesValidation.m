#import "../Shared/NCFavorites.h"
static void Check(BOOL ok) { if (!ok) exit(1); }
int main(void) { @autoreleasepool {
    NSArray *packs=@[@{@"id":@"Anime"},@{@"id":@"Pixel.flexpack"},@{@"id":@"Circuit"}];
    Check(NCFavoriteIdentifiers(@"bad",packs).count==0);
    Check([NCFavoriteIdentifiers(@[@"Anime",@"deleted",@"Anime",@4,@"../escape",@"Circuit"],packs) isEqual:@[@"Anime",@"Circuit"]]);
    Check(!NCNextFavorite(@[],@"Anime")); Check(!NCNextFavorite(@[@"Anime"],@"Anime"));
    Check([NCNextFavorite(@[@"Anime",@"Circuit"],@"Anime") isEqual:@"Circuit"]);
    Check([NCNextFavorite(@[@"Anime",@"Circuit"],@"Circuit") isEqual:@"Anime"]);
    Check([NCNextFavorite(@[@"Anime",@"Circuit"],@"deleted") isEqual:@"Anime"]);
    Check(NCFavoriteIdentifiers([@[@"Anime"] arrayByAddingObjectsFromArray:[@"x" componentsSeparatedByString:@"-"]],packs).count==1);
    NSMutableArray *huge=[NSMutableArray array];for(int i=0;i<129;i++)[huge addObject:@"Anime"];
    Check(NCFavoriteIdentifiers(huge,packs).count==0);
    puts("PASS: favorites malformed input, deduplication, missing packs, cycle/wrap, fewer than two and bounded list.");
} return 0; }
