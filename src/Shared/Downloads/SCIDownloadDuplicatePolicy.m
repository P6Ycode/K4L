#import "SCIDownloadDuplicatePolicy.h"

#import <Photos/Photos.h>

#import "../../Utils.h"
#import "../Gallery/SCIGalleryCoreDataStack.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../UI/SCIIGAlertPresenter.h"

// Constants
static NSString * const kSCIPhotosSaveLedgerKey = @"general_detect_duplicate_photos_ledger_v2";
static NSUInteger const kSCIPhotosSaveLedgerLimit = 2000;

// Internal decision enums for alerts
typedef NS_ENUM(NSInteger, SCIDownloadDuplicateDecision) {
    SCIDownloadDuplicateDecisionDownloadAgain = 1,
    SCIDownloadDuplicateDecisionDeleteExistingAndDownloadAgain = 2,
    SCIDownloadDuplicateDecisionCancel = 3,
};

typedef NS_ENUM(NSInteger, SCIDownloadBulkDuplicateDecision) {
    SCIDownloadBulkDuplicateDecisionSkipExisting = 1,
    SCIDownloadBulkDuplicateDecisionDownloadAllAnyway,
    SCIDownloadBulkDuplicateDecisionCancel,
};

// Helper functions
static NSString *SCINormalizedMediaURLString(NSString *string) {
    NSURLComponents *components = [NSURLComponents componentsWithString:string];
    if (!components) return string;
    components.query = nil;
    components.fragment = nil;
    return components.string ?: string;
}

static NSString *SCIDuplicateKey(SCIGallerySaveMetadata *metadata, NSInteger mediaType) {
    if (!metadata) return nil;
    NSString *identity = nil;
    if (metadata.sourceMediaPK.length > 0) {
        identity = [@"pk:" stringByAppendingString:metadata.sourceMediaPK];
        // Differentiate carousel slides by their img_index
        if (metadata.sourceMediaURLString.length > 0) {
            NSURLComponents *components = [NSURLComponents componentsWithString:metadata.sourceMediaURLString];
            for (NSURLQueryItem *item in components.queryItems) {
                if ([item.name isEqualToString:@"img_index"] && item.value.length > 0) {
                    identity = [identity stringByAppendingFormat:@"|idx:%@", item.value];
                    break;
                }
            }
        }
    } else if (metadata.sourceMediaURLString.length > 0) {
        identity = [@"url:" stringByAppendingString:SCINormalizedMediaURLString(metadata.sourceMediaURLString)];
    }
    if (identity.length == 0) return nil;
    return [NSString stringWithFormat:@"%ld|%@", (long)mediaType, identity];
}

static NSString *SCIMediaTypeLabel(NSInteger mediaType) {
    switch (mediaType) {
        case SCIGalleryMediaTypeVideo: return @"video";
        case SCIGalleryMediaTypeAudio: return @"audio";
        case SCIGalleryMediaTypeImage:
        default:
            return @"photo";
    }
}

static NSString *SCIDestinationLabel(SCIDownloadDuplicateDestination destination) {
    return destination == SCIDownloadDuplicateDestinationPhotos ? @"Photos" : @"Gallery";
}

static SCIGalleryFile *SCIExistingGalleryFile(SCIGallerySaveMetadata *metadata, NSInteger mediaType) {
    NSString *key = SCIDuplicateKey(metadata, mediaType);
    if (key.length == 0) return nil;
    __block SCIGalleryFile *match = nil;
    NSManagedObjectContext *context = [SCIGalleryCoreDataStack shared].viewContext;
    [context performBlockAndWait:^{
        NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"SCIGalleryFile"];
        request.predicate = [NSPredicate predicateWithFormat:@"mediaType == %d", (int)mediaType];
        NSArray<SCIGalleryFile *> *files = [context executeFetchRequest:request error:nil] ?: @[];
        for (SCIGalleryFile *file in files) {
            SCIGallerySaveMetadata *stored = [[SCIGallerySaveMetadata alloc] init];
            stored.sourceMediaPK = file.sourceMediaPK;
            stored.sourceMediaURLString = file.sourceMediaURLString;
            if ([SCIDuplicateKey(stored, mediaType) isEqualToString:key] && [file fileExists]) {
                match = file;
                break;
            }
        }
    }];
    return match;
}

static NSMutableDictionary<NSString *, NSString *> *SCIPhotosSaveLedger(void) {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSCIPhotosSaveLedgerKey];
    return [saved isKindOfClass:NSDictionary.class] ? [saved mutableCopy] : [NSMutableDictionary dictionary];
}

static BOOL SCIHasDuplicate(SCIDownloadDuplicateDestination destination, SCIGallerySaveMetadata *metadata, NSInteger mediaType) {
    NSString *key = SCIDuplicateKey(metadata, mediaType);
    if (key.length == 0) return NO;
    if (destination == SCIDownloadDuplicateDestinationPhotos) {
        return SCIPhotosSaveLedger()[key].length > 0;
    }
    return SCIExistingGalleryFile(metadata, mediaType) != nil;
}

static BOOL SCIPresentSingleDuplicateAlert(SCIDownloadDuplicateDestination destination,
                                            SCIGallerySaveMetadata *metadata,
                                            NSInteger mediaType,
                                            UIViewController *presenter,
                                            void (^continuation)(SCIDownloadDuplicateDecision)) {
    if (!SCIHasDuplicate(destination, metadata, mediaType)) return NO;
    NSString *message = [NSString stringWithFormat:@"This %@ has previously been downloaded to %@.",
                         SCIMediaTypeLabel(mediaType),
                         SCIDestinationLabel(destination)];
    [SCIIGAlertPresenter presentAlertFromViewController:presenter
                                                 title:@"Duplicate Download Detected"
                                               message:message
                                               actions:@[
        [SCIIGAlertAction actionWithTitle:@"Download Anyway" style:SCIIGAlertActionStyleDefault handler:^{
            if (continuation) continuation(SCIDownloadDuplicateDecisionDownloadAgain);
        }],
        [SCIIGAlertAction actionWithTitle:@"Delete Existing and Download" style:SCIIGAlertActionStyleDestructive handler:^{
            if (continuation) continuation(SCIDownloadDuplicateDecisionDeleteExistingAndDownloadAgain);
        }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:^{
            if (continuation) continuation(SCIDownloadDuplicateDecisionCancel);
        }],
    ]];
    return YES;
}

static BOOL SCIPresentBulkDuplicateAlert(NSUInteger duplicateCount,
                                         NSUInteger totalCount,
                                         UIViewController *presenter,
                                         void (^continuation)(SCIDownloadBulkDuplicateDecision)) {
    if (duplicateCount == 0 || !continuation) return NO;
    NSString *message = [NSString stringWithFormat:@"%lu of %lu items were already downloaded.",
                         (unsigned long)duplicateCount, (unsigned long)totalCount];
    [SCIIGAlertPresenter presentAlertFromViewController:presenter ?: topMostController()
                                                 title:@"Duplicate Downloads"
                                               message:message
                                               actions:@[
        [SCIIGAlertAction actionWithTitle:@"Skip Existing" style:SCIIGAlertActionStyleDefault handler:^{
            continuation(SCIDownloadBulkDuplicateDecisionSkipExisting);
        }],
        [SCIIGAlertAction actionWithTitle:@"Download All Anyway" style:SCIIGAlertActionStyleDefault handler:^{
            continuation(SCIDownloadBulkDuplicateDecisionDownloadAllAnyway);
        }],
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:^{
            continuation(SCIDownloadBulkDuplicateDecisionCancel);
        }],
    ]];
    return YES;
}

static void SCIDeleteExistingDuplicate(SCIDownloadDuplicateDestination destination,
                                       SCIGallerySaveMetadata *metadata,
                                       NSInteger mediaType,
                                       void (^completion)(BOOL, NSError *)) {
    if (destination == SCIDownloadDuplicateDestinationGallery) {
        SCIGalleryFile *file = SCIExistingGalleryFile(metadata, mediaType);
        NSError *error = nil;
        BOOL success = !file || [file removeWithError:&error];
        if (completion) completion(success, error);
        return;
    }
    NSString *key = SCIDuplicateKey(metadata, mediaType);
    NSMutableDictionary<NSString *, NSString *> *ledger = SCIPhotosSaveLedger();
    NSString *localIdentifier = ledger[key];
    PHFetchResult<PHAsset *> *assets = localIdentifier.length > 0
        ? [PHAsset fetchAssetsWithLocalIdentifiers:@[localIdentifier] options:nil]
        : nil;
    if (assets.count == 0) {
        [ledger removeObjectForKey:key];
        [[NSUserDefaults standardUserDefaults] setObject:ledger forKey:kSCIPhotosSaveLedgerKey];
        if (completion) completion(YES, nil);
        return;
    }
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest deleteAssets:assets];
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                NSMutableDictionary<NSString *, NSString *> *updatedLedger = SCIPhotosSaveLedger();
                [updatedLedger removeObjectForKey:key];
                [[NSUserDefaults standardUserDefaults] setObject:updatedLedger forKey:kSCIPhotosSaveLedgerKey];
            }
            if (completion) completion(success, error);
        });
    }];
}
@implementation SCIDownloadDuplicatePolicy

- (BOOL)duplicateDetectionEnabled {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSCIDownloadDetectDuplicatesKey]) return NO;
    return YES;
}

- (BOOL)duplicateDestinationFor:(SCIDownloadDestination)destination outValue:(SCIDownloadDuplicateDestination *)outValue {
    switch (destination) {
        case SCIDownloadDestinationPhotos:
            if (outValue) *outValue = SCIDownloadDuplicateDestinationPhotos;
            return YES;
        case SCIDownloadDestinationGallery:
            if (outValue) *outValue = SCIDownloadDuplicateDestinationGallery;
            return YES;
        default:
            return NO;
    }
}

- (NSInteger)mediaTypeForKind:(SCIDownloadMediaKind)kind {
    switch (kind) {
        case SCIDownloadMediaKindVideo: return SCIGalleryMediaTypeVideo;
        case SCIDownloadMediaKindAudio: return SCIGalleryMediaTypeAudio;
        case SCIDownloadMediaKindImage: return SCIGalleryMediaTypeImage;
        default: return SCIGalleryMediaTypeImage;
    }
}

- (NSUInteger)duplicateCountForRequest:(SCIDownloadRequest *)request destination:(SCIDownloadDuplicateDestination)dest {
    NSUInteger duplicateCount = 0;
    for (SCIDownloadItemRequest *item in request.items) {
        SCIGallerySaveMetadata *metadata = item.metadata ?: request.metadata;
        if (SCIHasDuplicate(dest, metadata, [self mediaTypeForKind:item.mediaKind])) {
            duplicateCount++;
        }
    }
    return duplicateCount;
}

- (void)runPreflightForRequest:(SCIDownloadRequest *)request
                      presenter:(UIViewController *)presenter
                     completion:(SCIDownloadPreflightCompletion)completion {
    if (![self duplicateDetectionEnabled]) {
        completion(SCIDownloadPreflightContinue);
        return;
    }
    if (request.destination != SCIDownloadDestinationPhotos && request.destination != SCIDownloadDestinationGallery) {
        completion(SCIDownloadPreflightContinue);
        return;
    }
    if (request.duplicatePolicy == SCIDownloadDuplicatePolicyAlwaysDownload) {
        completion(SCIDownloadPreflightContinue);
        return;
    }
    if (request.duplicatePolicy == SCIDownloadDuplicatePolicySkipExisting) {
        completion(SCIDownloadPreflightSkipSucceeded);
        return;
    }

    SCIDownloadDuplicateDestination dest = SCIDownloadDuplicateDestinationGallery;
    if (![self duplicateDestinationFor:request.destination outValue:&dest]) {
        completion(SCIDownloadPreflightContinue);
        return;
    }
    if (request.items.count == 1) {
        SCIDownloadItemRequest *item = request.items.firstObject;
        SCIGallerySaveMetadata *metadata = item.metadata ?: request.metadata;
        BOOL presented = SCIPresentSingleDuplicateAlert(dest, metadata, [self mediaTypeForKind:item.mediaKind],
                                                        presenter ?: topMostController(),
                                                        ^(SCIDownloadDuplicateDecision decision) {
            if (decision == SCIDownloadDuplicateDecisionCancel) {
                completion(SCIDownloadPreflightCancelled);
                return;
            }
            if (decision == SCIDownloadDuplicateDecisionDeleteExistingAndDownloadAgain) {
                SCIDeleteExistingDuplicate(dest, metadata, [self mediaTypeForKind:item.mediaKind],
                                          ^(BOOL success, NSError *error) {
                    (void)error;
                    if (success) completion(SCIDownloadPreflightContinue);
                    else completion(SCIDownloadPreflightCancelled);
                });
            } else {
                completion(SCIDownloadPreflightContinue);
            }
        });
        if (!presented) completion(SCIDownloadPreflightContinue);
        return;
    }

    NSUInteger duplicateCount = [self duplicateCountForRequest:request destination:dest];
    if (duplicateCount == 0) {
        completion(SCIDownloadPreflightContinue);
        return;
    }

    BOOL presented = SCIPresentBulkDuplicateAlert(duplicateCount, request.items.count,
                                                  presenter ?: topMostController(),
                                                  ^(SCIDownloadBulkDuplicateDecision decision) {
        switch (decision) {
            case SCIDownloadBulkDuplicateDecisionSkipExisting:
                completion(SCIDownloadPreflightSkipSucceeded);
                break;
            case SCIDownloadBulkDuplicateDecisionDownloadAllAnyway:
                completion(SCIDownloadPreflightContinue);
                break;
            case SCIDownloadBulkDuplicateDecisionCancel:
            default:
                completion(SCIDownloadPreflightCancelled);
                break;
        }
    });
    if (!presented) completion(SCIDownloadPreflightContinue);
}

#pragma mark - Public Utilities

+ (BOOL)hasDuplicateForDestination:(SCIDownloadDuplicateDestination)destination
                          metadata:(SCIGallerySaveMetadata *)metadata
                         mediaType:(NSInteger)mediaType {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:kSCIDownloadDetectDuplicatesKey]) return NO;
    return SCIHasDuplicate(destination, metadata, mediaType);
}

+ (void)recordPhotosSaveWithMetadata:(SCIGallerySaveMetadata *)metadata
                           mediaType:(NSInteger)mediaType
                assetLocalIdentifier:(NSString *)assetLocalIdentifier {
    NSString *key = SCIDuplicateKey(metadata, mediaType);
    if (key.length == 0 || assetLocalIdentifier.length == 0) return;
    @synchronized (self) {
        NSMutableDictionary<NSString *, NSString *> *ledger = SCIPhotosSaveLedger();
        ledger[key] = assetLocalIdentifier;
        if (ledger.count > kSCIPhotosSaveLedgerLimit) {
            NSArray<NSString *> *keys = ledger.allKeys;
            NSUInteger removeCount = ledger.count - kSCIPhotosSaveLedgerLimit;
            [ledger removeObjectsForKeys:[keys subarrayWithRange:NSMakeRange(0, removeCount)]];
        }
        [[NSUserDefaults standardUserDefaults] setObject:ledger forKey:kSCIPhotosSaveLedgerKey];
    }
}

@end
