#import "SCIGalleryGridDensity.h"

NSString * const kSCIGalleryGridColumnsKey = @"gallery_grid_columns";
NSString * const kSCIGalleryGridPinchDisabledKey = @"gallery_grid_pinch_disabled";
NSString * const kSCIGalleryGridShowSourceUsernameDisabledKey = @"gallery_grid_show_source_username_disabled";
NSString * const kSCIGalleryFolderBarPinDisabledKey = @"gallery_folder_bar_pin_disabled";
NSString * const kSCIGalleryGridControlsChangedNotification = @"SCIGalleryGridControlsPreferenceChanged";

BOOL SCIGalleryFolderBarPinned(void) {
    return ![[NSUserDefaults standardUserDefaults] boolForKey:kSCIGalleryFolderBarPinDisabledKey];
}

NSInteger const kSCIGalleryGridColumnsDefault = 3;
NSInteger const kSCIGalleryGridColumnsMin = 2;
NSInteger const kSCIGalleryGridColumnsMax = 5;

// Allowed densities, clamped from pinch.
static NSInteger const kColumnChoices[] = {2, 3, 5};
static NSUInteger const kColumnChoicesCount = sizeof(kColumnChoices) / sizeof(kColumnChoices[0]);

static NSInteger SCIClampColumns(NSInteger columns) {
    return MAX(kSCIGalleryGridColumnsMin, MIN(kSCIGalleryGridColumnsMax, columns));
}

NSInteger SCIGalleryGridColumns(void) {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger stored = [d objectForKey:kSCIGalleryGridColumnsKey] ? [d integerForKey:kSCIGalleryGridColumnsKey] : kSCIGalleryGridColumnsDefault;
    return SCIClampColumns(stored);
}

void SCIGalleryGridSetColumns(NSInteger columns) {
    [[NSUserDefaults standardUserDefaults] setInteger:SCIClampColumns(columns) forKey:kSCIGalleryGridColumnsKey];
}

static NSUInteger SCIColumnChoiceIndex(NSInteger columns) {
    for (NSUInteger i = 0; i < kColumnChoicesCount; i++) {
        if (kColumnChoices[i] == columns) return i;
    }
    return 1; // default to the index of "3"
}

NSInteger SCIGalleryGridColumnsAdjacent(NSInteger columns, BOOL largerCells) {
    NSUInteger index = SCIColumnChoiceIndex(columns);
    if (largerCells) {
        // Fewer columns -> larger cells.
        return index > 0 ? kColumnChoices[index - 1] : columns;
    }
    return index + 1 < kColumnChoicesCount ? kColumnChoices[index + 1] : columns;
}
