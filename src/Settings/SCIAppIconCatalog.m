#import "SCIAppIconCatalog.h"

static NSString * const kSCIAppIconPrimaryIdentifier = @"";
static NSString * const kSCIAppIconSelectionDefaultsKey = @"general_app_icon_identifier";

@implementation SCIAppIconItem
@end

static NSString *SCIAppIconDisplayNameFromIdentifier(NSString *identifier, BOOL primary) {
    if (primary || identifier.length == 0) {
        return @"Default";
    }

    NSMutableString *displayName = [[identifier stringByReplacingOccurrencesOfString:@"_" withString:@" "] mutableCopy];
    [displayName replaceOccurrencesOfString:@"-" withString:@" " options:0 range:NSMakeRange(0, displayName.length)];
    [displayName replaceOccurrencesOfString:@"AppIcon" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, displayName.length)];
    [displayName replaceOccurrencesOfString:@"Icon" withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, displayName.length)];
    NSString *trimmed = [displayName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length > 0 ? trimmed.capitalizedString : identifier;
}

static NSArray<NSString *> *SCIAppIconFilesFromDictionary(NSDictionary *dictionary) {
    NSMutableArray<NSString *> *iconFiles = [NSMutableArray array];
    NSString *iconName = dictionary[@"CFBundleIconName"];
    if ([iconName isKindOfClass:[NSString class]] && iconName.length > 0) {
        [iconFiles addObject:iconName];
    }

    NSArray *files = dictionary[@"CFBundleIconFiles"];
    if (![files isKindOfClass:[NSArray class]]) {
        return iconFiles;
    }

    for (id value in files) {
        if (![value isKindOfClass:[NSString class]]) continue;
        NSString *file = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (file.length > 0 && ![iconFiles containsObject:file]) {
            [iconFiles addObject:file];
        }
    }
    return iconFiles;
}

static SCIAppIconItem *SCIAppIconItemFromDictionary(NSString *identifier, NSDictionary *dictionary, BOOL primary) {
    SCIAppIconItem *item = [[SCIAppIconItem alloc] init];
    item.identifier = primary ? kSCIAppIconPrimaryIdentifier : (identifier ?: @"");
    item.displayName = SCIAppIconDisplayNameFromIdentifier(identifier, primary);
    item.iconFiles = SCIAppIconFilesFromDictionary(dictionary);
    item.isPrimary = primary;
    return item;
}

static NSArray<NSDictionary *> *SCIAppIconIconDictionaries(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    NSMutableArray<NSDictionary *> *dictionaries = [NSMutableArray array];
    NSDictionary *icons = info[@"CFBundleIcons"];
    if ([icons isKindOfClass:[NSDictionary class]]) {
        [dictionaries addObject:icons];
    }

    NSDictionary *ipadIcons = info[@"CFBundleIcons~ipad"];
    if ([ipadIcons isKindOfClass:[NSDictionary class]]) {
        [dictionaries addObject:ipadIcons];
    }
    return dictionaries;
}

static UIImage *SCIAppIconImageNamed(NSString *name) {
    if (name.length == 0) return nil;

    NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithObject:name];
    if ([name.pathExtension caseInsensitiveCompare:@"png"] != NSOrderedSame) {
        [candidates addObject:[name stringByAppendingPathExtension:@"png"]];
    }

    for (NSString *candidate in candidates) {
        UIImage *image = [UIImage imageNamed:candidate inBundle:NSBundle.mainBundle compatibleWithTraitCollection:nil];
        if (image) return image;

        NSString *resourceName = candidate.stringByDeletingPathExtension;
        NSString *extension = candidate.pathExtension.length > 0 ? candidate.pathExtension : nil;
        NSString *path = [NSBundle.mainBundle pathForResource:resourceName ofType:extension];
        if (path.length > 0) {
            image = [UIImage imageWithContentsOfFile:path];
            if (image) return image;
        }
    }

    return nil;
}

@implementation SCIAppIconCatalog

+ (NSArray<SCIAppIconItem *> *)availableAppIcons {
    NSMutableArray<SCIAppIconItem *> *items = [NSMutableArray array];
    NSArray<NSDictionary *> *iconDictionaries = SCIAppIconIconDictionaries();

    NSDictionary *primary = iconDictionaries.firstObject[@"CFBundlePrimaryIcon"];
    if ([primary isKindOfClass:[NSDictionary class]]) {
        [items addObject:SCIAppIconItemFromDictionary(@"", primary, YES)];
    } else {
        SCIAppIconItem *fallback = [[SCIAppIconItem alloc] init];
        fallback.identifier = kSCIAppIconPrimaryIdentifier;
        fallback.displayName = @"Default";
        fallback.iconFiles = @[@"Prod60x60", @"Icon-60-Prod", @"Prod"];
        fallback.isPrimary = YES;
        [items addObject:fallback];
    }

    NSMutableDictionary<NSString *, NSDictionary *> *mergedAlternates = [NSMutableDictionary dictionary];
    for (NSDictionary *icons in iconDictionaries) {
        NSDictionary *alternates = icons[@"CFBundleAlternateIcons"];
        if (![alternates isKindOfClass:[NSDictionary class]]) continue;
        for (NSString *identifier in alternates) {
            NSDictionary *dictionary = alternates[identifier];
            if (![dictionary isKindOfClass:[NSDictionary class]]) continue;
            if (!mergedAlternates[identifier]) {
                mergedAlternates[identifier] = dictionary;
            }
        }
    }

    NSArray<NSString *> *sortedKeys = [[mergedAlternates allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *identifier in sortedKeys) {
        [items addObject:SCIAppIconItemFromDictionary(identifier, mergedAlternates[identifier], NO)];
    }

    return items;
}

+ (NSString *)currentAppIconIdentifier {
    // UIApplication.alternateIconName is unreliable on re-signed / injected
    // builds: it frequently reports nil even while an alternate icon is active
    // (the setter still works). So we trust our own persisted record first and
    // only fall back to the system value when we have nothing stored.
    NSString *stored = [self storedSelectedIdentifier];
    if (stored != nil) {
        // Validate against what's actually installable; if the stored icon no
        // longer exists in the bundle, drop back to the system value.
        if (stored.length == 0 || [self appIconWithIdentifier:stored] != nil) {
            return stored.length > 0 ? stored : kSCIAppIconPrimaryIdentifier;
        }
    }

    NSString *alternateIconName = UIApplication.sharedApplication.alternateIconName;
    return alternateIconName.length > 0 ? alternateIconName : kSCIAppIconPrimaryIdentifier;
}

+ (NSString *)storedSelectedIdentifier {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:kSCIAppIconSelectionDefaultsKey];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

+ (void)setStoredSelectedIdentifier:(NSString *)identifier {
    [[NSUserDefaults standardUserDefaults] setObject:(identifier ?: kSCIAppIconPrimaryIdentifier)
                                              forKey:kSCIAppIconSelectionDefaultsKey];
}

+ (SCIAppIconItem *)currentAppIcon {
    return [self appIconWithIdentifier:[self currentAppIconIdentifier]];
}

+ (SCIAppIconItem *)appIconWithIdentifier:(NSString *)identifier {
    NSString *resolvedIdentifier = identifier.length > 0 ? identifier : kSCIAppIconPrimaryIdentifier;
    for (SCIAppIconItem *item in [self availableAppIcons]) {
        if ([item.identifier isEqualToString:resolvedIdentifier]) {
            return item;
        }
    }
    return nil;
}

+ (UIImage *)imageForAppIcon:(SCIAppIconItem *)item {
    for (NSString *file in [item.iconFiles reverseObjectEnumerator]) {
        UIImage *image = SCIAppIconImageNamed(file);
        if (image) return image;
    }

    if (item.isPrimary) {
        for (NSString *fallback in @[@"Prod", @"Prod60x60", @"Icon-60-Prod"]) {
            UIImage *image = SCIAppIconImageNamed(fallback);
            if (image) return image;
        }
    }

    return nil;
}

@end
