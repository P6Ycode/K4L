#import "SCIGalleryHiddenSources.h"

NSString * const kSCIGalleryHiddenSourcesKey = @"gallery_hidden_sources";
NSNotificationName const SCIGalleryHiddenSourcesDidChangeNotification = @"SCIGalleryHiddenSourcesDidChangeNotification";

NSArray<NSNumber *> *SCIGalleryHiddenSources(void) {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:kSCIGalleryHiddenSourcesKey];
    NSMutableArray<NSNumber *> *sources = [NSMutableArray array];
    for (id value in stored ?: @[]) {
        if ([value isKindOfClass:NSNumber.class]) [sources addObject:value];
    }
    return [sources copy];
}

NSPredicate *SCIGalleryVisibleSourcesPredicate(void) {
    NSArray<NSNumber *> *hidden = SCIGalleryHiddenSources();
    return hidden.count > 0 ? [NSPredicate predicateWithFormat:@"NOT (source IN %@)", hidden] : nil;
}

BOOL SCIGallerySourceIsHidden(NSInteger source) {
    return [SCIGalleryHiddenSources() containsObject:@(source)];
}

void SCIGallerySetSourceHidden(NSInteger source, BOOL hidden) {
    NSMutableSet<NSNumber *> *sources = [NSMutableSet setWithArray:SCIGalleryHiddenSources()];
    if (hidden) [sources addObject:@(source)];
    else [sources removeObject:@(source)];
    NSArray *sorted = [sources.allObjects sortedArrayUsingSelector:@selector(compare:)];
    [[NSUserDefaults standardUserDefaults] setObject:sorted forKey:kSCIGalleryHiddenSourcesKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIGalleryHiddenSourcesDidChangeNotification object:nil];
}
