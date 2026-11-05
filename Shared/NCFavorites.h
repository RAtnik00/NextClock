#import "NCPacks.h"
static inline NSArray<NSString *> *NCFavoriteIdentifiers(id value, NSArray *packs) {
    if (![value isKindOfClass:NSArray.class] || [value count]>128) return @[];
    NSMutableSet *installed=[NSMutableSet set];
    for (NSDictionary *pack in packs) if (NCValidIdentifier(pack[@"id"])) [installed addObject:pack[@"id"]];
    NSMutableArray *result=[NSMutableArray array];
    for (id identifier in value) if ([identifier isKindOfClass:NSString.class] &&
        [installed containsObject:identifier] && ![result containsObject:identifier]) [result addObject:identifier];
    return result;
}
static inline NSString *NCNextFavorite(NSArray<NSString *> *favorites, NSString *current) {
    if (favorites.count<2) return nil;
    NSUInteger index=[favorites indexOfObject:current];
    return favorites[index==NSNotFound ? 0 : (index+1)%favorites.count];
}
