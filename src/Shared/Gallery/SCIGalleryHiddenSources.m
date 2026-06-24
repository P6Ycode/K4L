#import "SCIGalleryHiddenSources.h"

#import "../Account/SCIAccountManager.h"
#import "../../Utils.h"

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

NSPredicate *SCIGalleryAccountScopePredicate(void) {
    if (![SCIUtils getBoolPref:@"gallery_filter_current_account"]) return nil;  // "All accounts"
    NSString *pk = [SCIAccountManager currentAccountPK];
    if (pk.length == 0) return nil;  // logged out / unresolved — don't hide anything
    // Strictly the current account's files. Pre-existing/unassigned files are
    // not shown here; the settings toggle offers to claim them on enable, and
    // any file can be (re)assigned from its edit-details sheet.
    return [NSPredicate predicateWithFormat:@"ownerAccountPK == %@", pk];
}

NSPredicate *SCIGalleryVisibleSourcesPredicate(void) {
    NSMutableArray<NSPredicate *> *parts = [NSMutableArray array];

    NSArray<NSNumber *> *hidden = SCIGalleryHiddenSources();
    if (hidden.count > 0) [parts addObject:[NSPredicate predicateWithFormat:@"NOT (source IN %@)", hidden]];

    NSPredicate *accountScope = SCIGalleryAccountScopePredicate();
    if (accountScope) [parts addObject:accountScope];

    if (parts.count == 0) return nil;
    if (parts.count == 1) return parts.firstObject;
    return [NSCompoundPredicate andPredicateWithSubpredicates:parts];
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
