#import "SCIDownloadRequest.h"
#import "../Gallery/SCIGallerySaveMetadata.h"

static NSDictionary *SCIDownloadMetadataDict(SCIGallerySaveMetadata *metadata) {
    if (!metadata) return @{};
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"source"] = @(metadata.source);
    if (metadata.sourceUsername) d[@"sourceUsername"] = metadata.sourceUsername;
    if (metadata.sourceUserPK) d[@"sourceUserPK"] = metadata.sourceUserPK;
    if (metadata.sourceMediaPK) d[@"sourceMediaPK"] = metadata.sourceMediaPK;
    if (metadata.sourceMediaCode) d[@"sourceMediaCode"] = metadata.sourceMediaCode;
    if (metadata.sourceMediaURLString) d[@"sourceMediaURLString"] = metadata.sourceMediaURLString;
    if (metadata.customName) d[@"customName"] = metadata.customName;
    return d;
}

static SCIGallerySaveMetadata *SCIDownloadMetadataFromDict(NSDictionary *d) {
    if (![d isKindOfClass:NSDictionary.class] || d.count == 0) return nil;
    SCIGallerySaveMetadata *m = [SCIGallerySaveMetadata new];
    m.source = [d[@"source"] shortValue];
    m.sourceUsername = d[@"sourceUsername"];
    m.sourceUserPK = d[@"sourceUserPK"];
    m.sourceMediaPK = d[@"sourceMediaPK"];
    m.sourceMediaCode = d[@"sourceMediaCode"];
    m.sourceMediaURLString = d[@"sourceMediaURLString"];
    m.customName = d[@"customName"];
    return m;
}

@implementation SCIDownloadItemRequest

+ (instancetype)itemWithRemoteURL:(NSURL *)url mediaKind:(SCIDownloadMediaKind)kind {
    SCIDownloadItemRequest *item = [self new];
    item.itemID = NSUUID.UUID.UUIDString;
    item.remoteURLString = url.absoluteString;
    item.mediaKind = kind;
    return item;
}

+ (instancetype)itemWithLocalPath:(NSString *)path mediaKind:(SCIDownloadMediaKind)kind {
    SCIDownloadItemRequest *item = [self new];
    item.itemID = NSUUID.UUID.UUIDString;
    item.localSourcePath = path;
    item.mediaKind = kind;
    return item;
}

- (id)copyWithZone:(NSZone *)zone {
    SCIDownloadItemRequest *c = [[SCIDownloadItemRequest allocWithZone:zone] init];
    c.itemID = [_itemID copy];
    c.remoteURLString = [_remoteURLString copy];
    c.localSourcePath = [_localSourcePath copy];
    c.mediaKind = _mediaKind;
    c.preferredFileExtension = [_preferredFileExtension copy];
    c.expectedFilenameStem = [_expectedFilenameStem copy];
    c.linkString = [_linkString copy];
    c.metadata = [_metadata copy];
    c.index = _index;
    c.requiresAudioConversion = _requiresAudioConversion;
    c.audioProcessingBasename = [_audioProcessingBasename copy];
    c.requiresDashMerge = _requiresDashMerge;
    c.dashSecondaryURLString = [_dashSecondaryURLString copy];
    c.dashOptionKind = _dashOptionKind;
    c.dashDuration = _dashDuration;
    c.dashWidth = _dashWidth;
    c.dashHeight = _dashHeight;
    c.dashBandwidth = _dashBandwidth;
    return c;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"itemID"] = self.itemID ?: @"";
    if (self.remoteURLString) d[@"remoteURLString"] = self.remoteURLString;
    if (self.localSourcePath) d[@"localSourcePath"] = self.localSourcePath;
    d[@"mediaKind"] = @(self.mediaKind);
    if (self.preferredFileExtension) d[@"preferredFileExtension"] = self.preferredFileExtension;
    if (self.expectedFilenameStem) d[@"expectedFilenameStem"] = self.expectedFilenameStem;
    if (self.linkString) d[@"linkString"] = self.linkString;
    NSDictionary *meta = SCIDownloadMetadataDict(self.metadata);
    if (meta.count) d[@"metadata"] = meta;
    d[@"index"] = @(self.index);
    d[@"requiresAudioConversion"] = @(self.requiresAudioConversion);
    if (self.audioProcessingBasename) d[@"audioProcessingBasename"] = self.audioProcessingBasename;
    d[@"requiresDashMerge"] = @(self.requiresDashMerge);
    if (self.dashSecondaryURLString) d[@"dashSecondaryURLString"] = self.dashSecondaryURLString;
    d[@"dashOptionKind"] = @(self.dashOptionKind);
    d[@"dashDuration"] = @(self.dashDuration);
    d[@"dashWidth"] = @(self.dashWidth);
    d[@"dashHeight"] = @(self.dashHeight);
    d[@"dashBandwidth"] = @(self.dashBandwidth);
    return d;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    SCIDownloadItemRequest *item = [self new];
    item.itemID = dict[@"itemID"] ?: NSUUID.UUID.UUIDString;
    item.remoteURLString = dict[@"remoteURLString"];
    item.localSourcePath = dict[@"localSourcePath"];
    item.mediaKind = [dict[@"mediaKind"] integerValue];
    item.preferredFileExtension = dict[@"preferredFileExtension"];
    item.expectedFilenameStem = dict[@"expectedFilenameStem"];
    item.linkString = dict[@"linkString"];
    item.metadata = SCIDownloadMetadataFromDict(dict[@"metadata"]);
    item.index = [dict[@"index"] integerValue];
    item.requiresAudioConversion = [dict[@"requiresAudioConversion"] boolValue];
    item.audioProcessingBasename = dict[@"audioProcessingBasename"];
    item.requiresDashMerge = [dict[@"requiresDashMerge"] boolValue];
    item.dashSecondaryURLString = dict[@"dashSecondaryURLString"];
    item.dashOptionKind = [dict[@"dashOptionKind"] integerValue];
    item.dashDuration = [dict[@"dashDuration"] doubleValue];
    item.dashWidth = [dict[@"dashWidth"] integerValue];
    item.dashHeight = [dict[@"dashHeight"] integerValue];
    item.dashBandwidth = [dict[@"dashBandwidth"] integerValue];
    return item;
}

@end

@implementation SCIDownloadRequest

+ (instancetype)requestWithItems:(NSArray<SCIDownloadItemRequest *> *)items destination:(SCIDownloadDestination)destination {
    SCIDownloadRequest *request = [self new];
    request.requestID = NSUUID.UUID.UUIDString;
    request.createdAt = NSDate.date.timeIntervalSince1970;
    request.items = items ?: @[];
    request.destination = destination;
    request.presentationMode = SCIDownloadPresentationModeQueuePill;
    request.duplicatePolicy = SCIDownloadDuplicatePolicyAsk;
    request.qualityPolicy = SCIDownloadQualityPolicyDefault;
    return request;
}

- (id)copyWithZone:(NSZone *)zone {
    SCIDownloadRequest *c = [[SCIDownloadRequest allocWithZone:zone] init];
    c.requestID = [_requestID copy];
    c.createdAt = _createdAt;
    c.sourceSurface = _sourceSurface;
    c.destination = _destination;
    c.presentationMode = _presentationMode;
    c.items = [[NSArray alloc] initWithArray:_items copyItems:YES];
    c.metadata = [_metadata copy];
    c.notificationIdentifier = [_notificationIdentifier copy];
    c.duplicatePolicy = _duplicatePolicy;
    c.qualityPolicy = _qualityPolicy;
    c.titleOverride = [_titleOverride copy];
    c.finalizeAsBatchShare = _finalizeAsBatchShare;
    c.finalizeAsBatchClipboard = _finalizeAsBatchClipboard;
    return c;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"requestID"] = self.requestID ?: @"";
    d[@"createdAt"] = @(self.createdAt);
    d[@"sourceSurface"] = @(self.sourceSurface);
    d[@"destination"] = @(self.destination);
    d[@"presentationMode"] = @(self.presentationMode);
    NSMutableArray *items = [NSMutableArray array];
    for (SCIDownloadItemRequest *item in self.items) {
        [items addObject:[item dictionaryRepresentation]];
    }
    d[@"items"] = items;
    NSDictionary *meta = SCIDownloadMetadataDict(self.metadata);
    if (meta.count) d[@"metadata"] = meta;
    if (self.notificationIdentifier) d[@"notificationIdentifier"] = self.notificationIdentifier;
    d[@"duplicatePolicy"] = @(self.duplicatePolicy);
    d[@"qualityPolicy"] = @(self.qualityPolicy);
    if (self.titleOverride) d[@"titleOverride"] = self.titleOverride;
    d[@"finalizeAsBatchShare"] = @(self.finalizeAsBatchShare);
    d[@"finalizeAsBatchClipboard"] = @(self.finalizeAsBatchClipboard);
    return d;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    SCIDownloadRequest *request = [self new];
    request.requestID = dict[@"requestID"] ?: NSUUID.UUID.UUIDString;
    request.createdAt = [dict[@"createdAt"] doubleValue];
    request.sourceSurface = [dict[@"sourceSurface"] integerValue];
    request.destination = [dict[@"destination"] integerValue];
    request.presentationMode = [dict[@"presentationMode"] integerValue];
    request.metadata = SCIDownloadMetadataFromDict(dict[@"metadata"]);
    request.notificationIdentifier = dict[@"notificationIdentifier"];
    request.duplicatePolicy = [dict[@"duplicatePolicy"] integerValue];
    request.qualityPolicy = [dict[@"qualityPolicy"] integerValue];
    request.titleOverride = dict[@"titleOverride"];
    request.finalizeAsBatchShare = [dict[@"finalizeAsBatchShare"] boolValue];
    request.finalizeAsBatchClipboard = [dict[@"finalizeAsBatchClipboard"] boolValue];
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *entry in dict[@"items"] ?: @[]) {
        SCIDownloadItemRequest *item = [SCIDownloadItemRequest fromDictionary:entry];
        if (item) [items addObject:item];
    }
    request.items = items;
    return request;
}

@end
