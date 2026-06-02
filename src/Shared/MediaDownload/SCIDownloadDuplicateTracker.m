#import "SCIDownloadDuplicateTracker.h"

#import <Photos/Photos.h>

#import "../Gallery/SCIGalleryCoreDataStack.h"
#import "../Gallery/SCIGalleryFile.h"
#import "../Gallery/SCIGallerySaveMetadata.h"
#import "../UI/SCIIGAlertPresenter.h"
#import "../../Utils.h"

static NSString * const kSCIDetectDuplicateDownloadsKey = @"general_detect_duplicate_downloads";
static NSString * const kSCIPhotosSaveLedgerKey = @"general_detect_duplicate_photos_ledger_v2";
static NSUInteger const kSCIPhotosSaveLedgerLimit = 2000;

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
    if (![SCIUtils getBoolPref:kSCIDetectDuplicateDownloadsKey]) return NO;
    NSString *key = SCIDuplicateKey(metadata, mediaType);
    if (key.length == 0) return NO;
    if (destination == SCIDownloadDuplicateDestinationPhotos) {
        return SCIPhotosSaveLedger()[key].length > 0;
    }
    return SCIExistingGalleryFile(metadata, mediaType) != nil;
}

@implementation SCIDownloadDuplicateTracker

+ (BOOL)presentPreflightIfNeededForDestination:(SCIDownloadDuplicateDestination)destination
                                      metadata:(SCIGallerySaveMetadata *)metadata
                                     mediaType:(NSInteger)mediaType
                                     presenter:(UIViewController *)presenter
                                  continuation:(void (^)(SCIDownloadDuplicateDecision))continuation {
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
        [SCIIGAlertAction actionWithTitle:@"Cancel" style:SCIIGAlertActionStyleCancel handler:nil],
    ]];
    return YES;
}

+ (void)deleteExistingForDestination:(SCIDownloadDuplicateDestination)destination
                            metadata:(SCIGallerySaveMetadata *)metadata
                           mediaType:(NSInteger)mediaType
                          completion:(void (^)(BOOL, NSError *))completion {
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
