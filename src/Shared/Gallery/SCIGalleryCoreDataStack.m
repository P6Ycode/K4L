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

@end
