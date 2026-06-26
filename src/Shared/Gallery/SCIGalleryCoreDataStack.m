#import "SCIGalleryCoreDataStack.h"
#import "SCIGalleryPaths.h"
#import "../../Utils.h"

@interface SCIGalleryCoreDataStack ()
@property (nonatomic, strong, readwrite) NSPersistentContainer *persistentContainer;
@end

static NSString * const kSCIGalleryEntityName = @"SCIGalleryFile";
static NSString * const kSCIGalleryStoreName = @"gallery.sqlite";

@implementation SCIGalleryCoreDataStack

+ (instancetype)shared {
    static SCIGalleryCoreDataStack *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[SCIGalleryCoreDataStack alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupPersistentContainer];
    }
    return self;
}

- (NSManagedObjectModel *)buildModelWithAccountOwnership:(BOOL)includeAccountOwnership {
    NSManagedObjectModel *model = [[NSManagedObjectModel alloc] init];

    NSEntityDescription *entity = [[NSEntityDescription alloc] init];
    entity.name = kSCIGalleryEntityName;
    entity.managedObjectClassName = @"SCIGalleryFile";

    NSAttributeDescription *identifier = [[NSAttributeDescription alloc] init];
    identifier.name = @"identifier";
    identifier.attributeType = NSStringAttributeType;
    identifier.optional = NO;

    NSAttributeDescription *relativePath = [[NSAttributeDescription alloc] init];
    relativePath.name = @"relativePath";
    relativePath.attributeType = NSStringAttributeType;
    relativePath.optional = NO;

    NSAttributeDescription *mediaType = [[NSAttributeDescription alloc] init];
    mediaType.name = @"mediaType";
    mediaType.attributeType = NSInteger16AttributeType;
    mediaType.optional = NO;
    mediaType.defaultValue = @0;

    NSAttributeDescription *source = [[NSAttributeDescription alloc] init];
    source.name = @"source";
    source.attributeType = NSInteger16AttributeType;
    source.optional = NO;
    source.defaultValue = @0;

    NSAttributeDescription *dateAdded = [[NSAttributeDescription alloc] init];
    dateAdded.name = @"dateAdded";
    dateAdded.attributeType = NSDateAttributeType;
    dateAdded.optional = NO;

    NSAttributeDescription *fileSize = [[NSAttributeDescription alloc] init];
    fileSize.name = @"fileSize";
    fileSize.attributeType = NSInteger64AttributeType;
    fileSize.optional = NO;
    fileSize.defaultValue = @0;

    NSAttributeDescription *isFavorite = [[NSAttributeDescription alloc] init];
    isFavorite.name = @"isFavorite";
    isFavorite.attributeType = NSBooleanAttributeType;
    isFavorite.optional = NO;
    isFavorite.defaultValue = @NO;

    NSAttributeDescription *folderPath = [[NSAttributeDescription alloc] init];
    folderPath.name = @"folderPath";
    folderPath.attributeType = NSStringAttributeType;
    folderPath.optional = YES;

    NSAttributeDescription *customName = [[NSAttributeDescription alloc] init];
    customName.name = @"customName";
    customName.attributeType = NSStringAttributeType;
    customName.optional = YES;

    NSAttributeDescription *sourceUsername = [[NSAttributeDescription alloc] init];
    sourceUsername.name = @"sourceUsername";
    sourceUsername.attributeType = NSStringAttributeType;
    sourceUsername.optional = YES;

    NSAttributeDescription *sourceUserPK = [[NSAttributeDescription alloc] init];
    sourceUserPK.name = @"sourceUserPK";
    sourceUserPK.attributeType = NSStringAttributeType;
    sourceUserPK.optional = YES;

    NSAttributeDescription *sourceProfileURLString = [[NSAttributeDescription alloc] init];
    sourceProfileURLString.name = @"sourceProfileURLString";
    sourceProfileURLString.attributeType = NSStringAttributeType;
    sourceProfileURLString.optional = YES;

    NSAttributeDescription *sourceMediaPK = [[NSAttributeDescription alloc] init];
    sourceMediaPK.name = @"sourceMediaPK";
    sourceMediaPK.attributeType = NSStringAttributeType;
    sourceMediaPK.optional = YES;

    NSAttributeDescription *sourceMediaCode = [[NSAttributeDescription alloc] init];
    sourceMediaCode.name = @"sourceMediaCode";
    sourceMediaCode.attributeType = NSStringAttributeType;
    sourceMediaCode.optional = YES;

    NSAttributeDescription *sourceMediaURLString = [[NSAttributeDescription alloc] init];
    sourceMediaURLString.name = @"sourceMediaURLString";
    sourceMediaURLString.attributeType = NSStringAttributeType;
    sourceMediaURLString.optional = YES;

    NSAttributeDescription *pixelWidth = [[NSAttributeDescription alloc] init];
    pixelWidth.name = @"pixelWidth";
    pixelWidth.attributeType = NSInteger32AttributeType;
    pixelWidth.optional = NO;
    pixelWidth.defaultValue = @0;

    NSAttributeDescription *pixelHeight = [[NSAttributeDescription alloc] init];
    pixelHeight.name = @"pixelHeight";
    pixelHeight.attributeType = NSInteger32AttributeType;
    pixelHeight.optional = NO;
    pixelHeight.defaultValue = @0;

    NSAttributeDescription *durationSeconds = [[NSAttributeDescription alloc] init];
    durationSeconds.name = @"durationSeconds";
    durationSeconds.attributeType = NSDoubleAttributeType;
    durationSeconds.optional = NO;
    durationSeconds.defaultValue = @0.0;

    NSMutableArray<NSPropertyDescription *> *properties = [@[
        identifier, relativePath, mediaType, source, dateAdded, fileSize, isFavorite, folderPath, customName,
        sourceUsername, sourceUserPK, sourceProfileURLString, sourceMediaPK, sourceMediaCode, sourceMediaURLString,
        pixelWidth, pixelHeight, durationSeconds
    ] mutableCopy];

    if (includeAccountOwnership) {
        // Per-account ownership: the logged-in account this file belongs to.
        // Optional so legacy files migrate as nil = "unassigned".
        NSAttributeDescription *ownerAccountPK = [[NSAttributeDescription alloc] init];
        ownerAccountPK.name = @"ownerAccountPK";
        ownerAccountPK.attributeType = NSStringAttributeType;
        ownerAccountPK.optional = YES;

        NSAttributeDescription *ownerUsername = [[NSAttributeDescription alloc] init];
        ownerUsername.name = @"ownerUsername";
        ownerUsername.attributeType = NSStringAttributeType;
        ownerUsername.optional = YES;

        [properties addObjectsFromArray:@[ownerAccountPK, ownerUsername]];
    }

    entity.properties = properties;
    model.entities = @[entity];

    return model;
}

- (NSManagedObjectModel *)buildModel {
    return [self buildModelWithAccountOwnership:YES];
}

- (NSURL *)storeURL {
    NSString *storePath = [[SCIGalleryPaths galleryDirectory] stringByAppendingPathComponent:kSCIGalleryStoreName];
    return [NSURL fileURLWithPath:storePath];
}

- (NSArray<NSURL *> *)sidecarURLsForStoreURL:(NSURL *)storeURL {
    NSString *path = storeURL.path;
    return @[
        [NSURL fileURLWithPath:[path stringByAppendingString:@"-wal"]],
        [NSURL fileURLWithPath:[path stringByAppendingString:@"-shm"]]
    ];
}

- (void)removeStoreSidecarsAtURL:(NSURL *)storeURL {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSURL *url in [self sidecarURLsForStoreURL:storeURL]) {
        if ([fm fileExistsAtPath:url.path]) {
            [fm removeItemAtURL:url error:nil];
        }
    }
}

- (void)backupStoreAtURL:(NSURL *)storeURL suffix:(NSString *)suffix {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithObject:storeURL];
    [urls addObjectsFromArray:[self sidecarURLsForStoreURL:storeURL]];
    for (NSURL *url in urls) {
        if (![fm fileExistsAtPath:url.path]) continue;
        NSString *backupPath = [url.path stringByAppendingFormat:@".%@", suffix];
        [fm removeItemAtPath:backupPath error:nil];
        NSError *error = nil;
        if (![fm copyItemAtPath:url.path toPath:backupPath error:&error]) {
            SCILog(@"General", @"[SCInsta Gallery] Failed to back up store file %@: %@", url.lastPathComponent, error);
        }
    }
}

- (BOOL)migrateStoreAtURLIfNeeded:(NSURL *)storeURL toModel:(NSManagedObjectModel *)destinationModel {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:storeURL.path]) return YES;

    NSError *metadataError = nil;
    NSDictionary *metadata = [NSPersistentStoreCoordinator metadataForPersistentStoreOfType:NSSQLiteStoreType
                                                                                       URL:storeURL
                                                                                   options:nil
                                                                                     error:&metadataError];
    if (!metadata) {
        SCILog(@"General", @"[SCInsta Gallery] Failed reading store metadata: %@", metadataError);
        return NO;
    }

    if ([destinationModel isConfiguration:nil compatibleWithStoreMetadata:metadata]) {
        return YES;
    }

    NSManagedObjectModel *sourceModel = [self buildModelWithAccountOwnership:NO];
    if (![sourceModel isConfiguration:nil compatibleWithStoreMetadata:metadata]) {
        SCILog(@"General", @"[SCInsta Gallery] Store is incompatible with current and pre-account schemas; leaving it untouched");
        return NO;
    }

    NSError *mappingError = nil;
    NSMappingModel *mapping = [NSMappingModel inferredMappingModelForSourceModel:sourceModel
                                                                 destinationModel:destinationModel
                                                                            error:&mappingError];
    if (!mapping) {
        SCILog(@"General", @"[SCInsta Gallery] Failed creating inferred migration mapping: %@", mappingError);
        return NO;
    }

    NSString *tmpName = [NSString stringWithFormat:@"gallery-migration-%@.sqlite", [NSUUID UUID].UUIDString];
    NSURL *tmpURL = [[storeURL URLByDeletingLastPathComponent] URLByAppendingPathComponent:tmpName];
    NSMigrationManager *manager = [[NSMigrationManager alloc] initWithSourceModel:sourceModel destinationModel:destinationModel];
    NSDictionary *destinationOptions = @{ NSSQLitePragmasOption: @{ @"journal_mode": @"DELETE" } };

    NSError *migrationError = nil;
    BOOL migrated = [manager migrateStoreFromURL:storeURL
                                            type:NSSQLiteStoreType
                                         options:nil
                                withMappingModel:mapping
                                toDestinationURL:tmpURL
                                 destinationType:NSSQLiteStoreType
                              destinationOptions:destinationOptions
                                           error:&migrationError];
    if (!migrated) {
        SCILog(@"General", @"[SCInsta Gallery] Failed migrating store to account schema: %@", migrationError);
        [fm removeItemAtURL:tmpURL error:nil];
        [self removeStoreSidecarsAtURL:tmpURL];
        return NO;
    }

    NSString *backupSuffix = [NSString stringWithFormat:@"pre-account-%@", @((long long)[NSDate date].timeIntervalSince1970)];
    [self backupStoreAtURL:storeURL suffix:backupSuffix];
    [fm removeItemAtURL:storeURL error:nil];
    [self removeStoreSidecarsAtURL:storeURL];

    NSError *moveError = nil;
    if (![fm moveItemAtURL:tmpURL toURL:storeURL error:&moveError]) {
        SCILog(@"General", @"[SCInsta Gallery] Failed installing migrated store: %@", moveError);
        [fm removeItemAtURL:tmpURL error:nil];
        [self removeStoreSidecarsAtURL:tmpURL];
        return NO;
    }

    [self removeStoreSidecarsAtURL:tmpURL];
    SCILog(@"General", @"[SCInsta Gallery] Migrated gallery store to account schema");
    return YES;
}

- (void)setupPersistentContainer {
    NSManagedObjectModel *model = [self buildModel];
    self.persistentContainer = [[NSPersistentContainer alloc] initWithName:@"SCIGalleryModel" managedObjectModel:model];

    NSURL *storeURL = [self storeURL];
    [self migrateStoreAtURLIfNeeded:storeURL toModel:model];
    NSPersistentStoreDescription *storeDesc = [[NSPersistentStoreDescription alloc] initWithURL:storeURL];
    storeDesc.shouldMigrateStoreAutomatically = YES;
    storeDesc.shouldInferMappingModelAutomatically = YES;
    self.persistentContainer.persistentStoreDescriptions = @[storeDesc];

    [self.persistentContainer loadPersistentStoresWithCompletionHandler:^(NSPersistentStoreDescription *desc, NSError *error) {
        if (error) {
            SCILog(@"General", @"[SCInsta Gallery] Failed to load Core Data store: %@", error);
        }
    }];

    self.persistentContainer.viewContext.automaticallyMergesChangesFromParent = YES;
}

- (NSManagedObjectContext *)viewContext {
    return self.persistentContainer.viewContext;
}

- (void)saveContext {
    NSManagedObjectContext *ctx = self.viewContext;
    if (![ctx hasChanges]) return;

    NSError *error;
    if (![ctx save:&error]) {
        SCILog(@"General", @"[SCInsta Gallery] Failed to save context: %@", error);
    }
}

- (void)unloadPersistentStores {
    NSPersistentStoreCoordinator *coordinator = self.persistentContainer.persistentStoreCoordinator;
    for (NSPersistentStore *store in [coordinator.persistentStores copy]) {
        NSError *removeError = nil;
        [coordinator removePersistentStore:store error:&removeError];
        if (removeError) {
            SCILog(@"General", @"[SCInsta Gallery] Failed unloading persistent store: %@", removeError);
        }
    }
}

- (void)reloadPersistentContainer {
    [self unloadPersistentStores];
    [self setupPersistentContainer];
}

// Treat nil and empty owner PKs as the same (both "unassigned").
static BOOL SCIGalleryOwnerEqual(NSString *a, NSString *b) {
    if (a.length == 0 && b.length == 0) return YES;
    return [a isEqualToString:b];
}

// Opens an exported bundle's gallery.sqlite read-only against the current model
// (migrating an older-schema archive first). Returns nil + sets *error on failure,
// or nil + no error when the bundle has no store.
- (NSManagedObjectContext *)archiveContextForBundleDirectory:(NSString *)bundleGalleryDirectory error:(NSError * _Nullable * _Nullable)error {
    NSString *archiveStorePath = [bundleGalleryDirectory stringByAppendingPathComponent:kSCIGalleryStoreName];
    if (![[NSFileManager defaultManager] fileExistsAtPath:archiveStorePath]) return nil;

    NSManagedObjectModel *model = [self buildModel];
    NSURL *archiveStoreURL = [NSURL fileURLWithPath:archiveStorePath];
    [self migrateStoreAtURLIfNeeded:archiveStoreURL toModel:model];

    NSPersistentStoreCoordinator *coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSDictionary *options = @{
        NSReadOnlyPersistentStoreOption: @YES,
        NSSQLitePragmasOption: @{ @"journal_mode": @"DELETE" }
    };
    if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:archiveStoreURL options:options error:error]) {
        return nil;
    }
    NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    context.persistentStoreCoordinator = coordinator;  // context retains the coordinator
    return context;
}

- (NSInteger)galleryImportConflictCountForBundleDirectory:(NSString *)bundleGalleryDirectory
                                           ownerAccountPK:(nullable NSString *)ownerAccountPK {
    if (ownerAccountPK.length == 0) return 0;
    NSManagedObjectContext *archiveContext = [self archiveContextForBundleDirectory:bundleGalleryDirectory error:nil];
    if (!archiveContext) return 0;

    NSFetchRequest *archiveRequest = [NSFetchRequest fetchRequestWithEntityName:kSCIGalleryEntityName];
    archiveRequest.resultType = NSDictionaryResultType;
    archiveRequest.propertiesToFetch = @[@"identifier"];
    NSMutableSet<NSString *> *archiveIDs = [NSMutableSet set];
    for (NSDictionary *row in [archiveContext executeFetchRequest:archiveRequest error:nil]) {
        NSString *identifier = row[@"identifier"];
        if ([identifier isKindOfClass:[NSString class]]) [archiveIDs addObject:identifier];
    }

    NSFetchRequest *mainRequest = [NSFetchRequest fetchRequestWithEntityName:kSCIGalleryEntityName];
    mainRequest.resultType = NSDictionaryResultType;
    mainRequest.propertiesToFetch = @[@"identifier", @"ownerAccountPK"];
    NSInteger conflicts = 0;
    for (NSDictionary *row in [self.viewContext executeFetchRequest:mainRequest error:nil]) {
        NSString *identifier = row[@"identifier"];
        if (![identifier isKindOfClass:[NSString class]] || ![archiveIDs containsObject:identifier]) continue;
        NSString *owner = row[@"ownerAccountPK"];
        if (![owner isKindOfClass:[NSString class]]) owner = nil;
        if (!SCIGalleryOwnerEqual(owner, ownerAccountPK)) conflicts++;
    }
    return conflicts;
}

- (NSInteger)mergeGalleryFilesFromBundleDirectory:(NSString *)bundleGalleryDirectory
                              remapOwnerAccountPK:(nullable NSString *)remapOwnerAccountPK
                                    ownerUsername:(nullable NSString *)ownerUsername
                                 conflictStrategy:(SCIGalleryImportConflictStrategy)conflictStrategy
                                            error:(NSError * _Nullable * _Nullable)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *openError = nil;
    NSManagedObjectContext *archiveContext = [self archiveContextForBundleDirectory:bundleGalleryDirectory error:&openError];
    if (!archiveContext) {
        if (openError) {
            SCILog(@"General", @"[SCInsta Gallery] Merge: failed opening archive store: %@", openError);
            if (error) *error = openError;
            return -1;
        }
        return 0;  // No store in the bundle — nothing to merge.
    }

    NSError *fetchError = nil;
    NSArray<NSManagedObject *> *archiveRows = [archiveContext executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:kSCIGalleryEntityName] error:&fetchError];
    if (!archiveRows) {
        SCILog(@"General", @"[SCInsta Gallery] Merge: failed fetching archive rows: %@", fetchError);
        if (error) *error = fetchError;
        return -1;
    }

    // Existing rows keyed by identifier (objects, so a conflict can be re-assigned in place).
    NSManagedObjectContext *mainContext = self.viewContext;
    NSMutableDictionary<NSString *, NSManagedObject *> *existingByID = [NSMutableDictionary dictionary];
    for (NSManagedObject *row in [mainContext executeFetchRequest:[NSFetchRequest fetchRequestWithEntityName:kSCIGalleryEntityName] error:nil]) {
        NSString *identifier = [row valueForKey:@"identifier"];
        if (identifier.length > 0) existingByID[identifier] = row;
    }

    NSString *mediaDir = [SCIGalleryPaths galleryMediaDirectory];
    NSString *thumbDir = [SCIGalleryPaths galleryThumbnailsDirectory];
    NSString *archiveFilesDir = [bundleGalleryDirectory stringByAppendingPathComponent:@"Files"];
    NSString *archiveThumbsDir = [bundleGalleryDirectory stringByAppendingPathComponent:@"Thumbnails"];
    NSArray<NSString *> *attributeNames = [self buildModel].entitiesByName[kSCIGalleryEntityName].attributesByName.allKeys;

    // Inserts a fresh copy of `src` under `targetIdentifier`, copying its media (with a
    // collision-safe name) and thumbnail. Returns YES on success.
    BOOL (^insertCopy)(NSManagedObject *, NSString *, NSString *) = ^BOOL(NSManagedObject *src, NSString *srcIdentifier, NSString *targetIdentifier) {
        NSString *relativePath = [src valueForKey:@"relativePath"];
        NSString *srcMediaPath = [archiveFilesDir stringByAppendingPathComponent:relativePath];
        if (![fm fileExistsAtPath:srcMediaPath]) return NO;  // media missing — skip

        NSString *destRelative = relativePath;
        NSString *destMediaPath = [mediaDir stringByAppendingPathComponent:destRelative];
        if ([fm fileExistsAtPath:destMediaPath]) {
            NSString *stem = [relativePath stringByDeletingPathExtension];
            NSString *ext = [relativePath pathExtension];
            NSUInteger suffix = 1;
            do {
                destRelative = ext.length > 0 ? [NSString stringWithFormat:@"%@-%lu.%@", stem, (unsigned long)suffix, ext]
                                              : [NSString stringWithFormat:@"%@-%lu", stem, (unsigned long)suffix];
                destMediaPath = [mediaDir stringByAppendingPathComponent:destRelative];
                suffix++;
            } while ([fm fileExistsAtPath:destMediaPath]);
        }
        if (![fm copyItemAtPath:srcMediaPath toPath:destMediaPath error:nil]) return NO;

        // Thumbnail is keyed by identifier (source named by srcIdentifier → dest by target).
        NSString *srcThumb = [archiveThumbsDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", srcIdentifier]];
        NSString *destThumb = [thumbDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", targetIdentifier]];
        if ([fm fileExistsAtPath:srcThumb] && ![fm fileExistsAtPath:destThumb]) {
            [fm copyItemAtPath:srcThumb toPath:destThumb error:nil];
        }

        NSManagedObject *dst = [NSEntityDescription insertNewObjectForEntityForName:kSCIGalleryEntityName inManagedObjectContext:mainContext];
        for (NSString *attribute in attributeNames) {
            [dst setValue:[src valueForKey:attribute] forKey:attribute];
        }
        [dst setValue:targetIdentifier forKey:@"identifier"];
        [dst setValue:destRelative forKey:@"relativePath"];
        if (remapOwnerAccountPK.length > 0) {
            [dst setValue:remapOwnerAccountPK forKey:@"ownerAccountPK"];
            [dst setValue:(ownerUsername.length > 0 ? ownerUsername : nil) forKey:@"ownerUsername"];
        }
        return YES;
    };

    NSInteger added = 0;
    for (NSManagedObject *src in archiveRows) {
        NSString *identifier = [src valueForKey:@"identifier"];
        NSString *relativePath = [src valueForKey:@"relativePath"];
        if (identifier.length == 0 || relativePath.length == 0) continue;

        NSManagedObject *existing = existingByID[identifier];
        if (existing) {
            // Already on the device. Only a "this account" import with a different owner
            // is a real conflict; otherwise it's a true duplicate we skip.
            NSString *existingOwner = [existing valueForKey:@"ownerAccountPK"];
            BOOL ownerConflict = remapOwnerAccountPK.length > 0 && !SCIGalleryOwnerEqual(existingOwner, remapOwnerAccountPK);
            if (!ownerConflict) continue;

            if (conflictStrategy == SCIGalleryImportConflictStrategyClaim) {
                [existing setValue:remapOwnerAccountPK forKey:@"ownerAccountPK"];
                [existing setValue:(ownerUsername.length > 0 ? ownerUsername : nil) forKey:@"ownerUsername"];
                added++;
            } else if (conflictStrategy == SCIGalleryImportConflictStrategyDuplicate) {
                if (insertCopy(src, identifier, [NSUUID UUID].UUIDString)) added++;
            }
            // Skip strategy: leave the existing file untouched.
            continue;
        }

        if (insertCopy(src, identifier, identifier)) {
            existingByID[identifier] = src;  // guard against duplicate identifiers in the archive
            added++;
        }
    }

    NSError *saveError = nil;
    if (mainContext.hasChanges && ![mainContext save:&saveError]) {
        SCILog(@"General", @"[SCInsta Gallery] Merge: failed saving merged rows: %@", saveError);
        if (error) *error = saveError;
        return -1;
    }

    SCILog(@"General", @"[SCInsta Gallery] Merge: added/updated %ld file(s) from import", (long)added);
    return added;
}

- (BOOL)exportGalleryFilesToBundleDirectory:(NSString *)bundleGalleryDirectory
                             ownerAccountPK:(nullable NSString *)ownerAccountPK
                                      error:(NSError * _Nullable * _Nullable)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *destFiles = [bundleGalleryDirectory stringByAppendingPathComponent:@"Files"];
    NSString *destThumbs = [bundleGalleryDirectory stringByAppendingPathComponent:@"Thumbnails"];
    [fm createDirectoryAtPath:destFiles withIntermediateDirectories:YES attributes:nil error:nil];
    [fm createDirectoryAtPath:destThumbs withIntermediateDirectories:YES attributes:nil error:nil];

    // Fresh destination store carrying only the in-scope rows.
    NSManagedObjectModel *model = [self buildModel];
    NSURL *destStoreURL = [NSURL fileURLWithPath:[bundleGalleryDirectory stringByAppendingPathComponent:kSCIGalleryStoreName]];
    NSPersistentStoreCoordinator *destCoordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
    NSDictionary *options = @{ NSSQLitePragmasOption: @{ @"journal_mode": @"DELETE" } };
    if (![destCoordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:destStoreURL options:options error:error]) {
        return NO;
    }
    NSManagedObjectContext *destContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
    destContext.persistentStoreCoordinator = destCoordinator;

    NSManagedObjectContext *mainContext = self.viewContext;
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:kSCIGalleryEntityName];
    if (ownerAccountPK.length > 0) {
        request.predicate = [NSPredicate predicateWithFormat:@"ownerAccountPK == %@", ownerAccountPK];
    }
    NSError *fetchError = nil;
    NSArray<NSManagedObject *> *rows = [mainContext executeFetchRequest:request error:&fetchError];
    if (!rows) {
        if (error) *error = fetchError;
        return NO;
    }

    NSString *srcFiles = [SCIGalleryPaths galleryMediaDirectory];
    NSString *srcThumbs = [SCIGalleryPaths galleryThumbnailsDirectory];
    NSArray<NSString *> *attributeNames = model.entitiesByName[kSCIGalleryEntityName].attributesByName.allKeys;

    for (NSManagedObject *src in rows) {
        NSString *identifier = [src valueForKey:@"identifier"];
        NSString *relativePath = [src valueForKey:@"relativePath"];
        if (identifier.length == 0 || relativePath.length == 0) continue;
        NSString *srcMediaPath = [srcFiles stringByAppendingPathComponent:relativePath];
        if (![fm fileExistsAtPath:srcMediaPath]) continue;  // skip rows whose media is gone

        [fm copyItemAtPath:srcMediaPath toPath:[destFiles stringByAppendingPathComponent:relativePath] error:nil];
        NSString *srcThumb = [srcThumbs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", identifier]];
        if ([fm fileExistsAtPath:srcThumb]) {
            [fm copyItemAtPath:srcThumb toPath:[destThumbs stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", identifier]] error:nil];
        }

        NSManagedObject *dst = [NSEntityDescription insertNewObjectForEntityForName:kSCIGalleryEntityName inManagedObjectContext:destContext];
        for (NSString *attribute in attributeNames) {
            [dst setValue:[src valueForKey:attribute] forKey:attribute];
        }
    }

    NSError *saveError = nil;
    if (destContext.hasChanges && ![destContext save:&saveError]) {
        if (error) *error = saveError;
        return NO;
    }
    for (NSPersistentStore *store in [destCoordinator.persistentStores copy]) {
        [destCoordinator removePersistentStore:store error:nil];
    }
    return YES;
}

@end
