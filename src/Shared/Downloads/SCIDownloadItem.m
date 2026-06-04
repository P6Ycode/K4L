#import "SCIDownloadItem.h"
#import "../Gallery/SCIGallerySaveMetadata.h"

@implementation SCIDownloadItem

- (instancetype)initWithRequest:(SCIDownloadItemRequest *)request {
    if (!(self = [super init])) return nil;
    _request = [request copy];
    _itemID = [_request.itemID copy];
    _index = request.index;
    _mediaKind = request.mediaKind;
    _linkString = [request.linkString copy];
    _metadata = [request.metadata copy];
    _state = SCIDownloadStatePending;
    _progress = 0;
    _retryable = YES;
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    SCIDownloadItem *c = [[SCIDownloadItem allocWithZone:zone] initWithRequest:self.request];
    c.state = _state;
    c.progress = _progress;
    c.bytesWritten = _bytesWritten;
    c.totalBytesExpected = _totalBytesExpected;
    c.stagedPath = [_stagedPath copy];
    c.finalPath = [_finalPath copy];
    c.photosAssetIdentifier = [_photosAssetIdentifier copy];
    c.error = _error;
    c.retryable = _retryable;
    c.detail = [_detail copy];
    return c;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"itemID"] = self.itemID ?: @"";
    d[@"index"] = @(self.index);
    d[@"state"] = @(self.state);
    d[@"progress"] = @(self.progress);
    d[@"bytesWritten"] = @(self.bytesWritten);
    d[@"totalBytesExpected"] = @(self.totalBytesExpected);
    if (self.stagedPath) d[@"stagedPath"] = self.stagedPath;
    if (self.finalPath) d[@"finalPath"] = self.finalPath;
    if (self.photosAssetIdentifier) d[@"photosAssetIdentifier"] = self.photosAssetIdentifier;
    if (self.error) {
        d[@"errorDomain"] = self.error.domain;
        d[@"errorCode"] = @(self.error.code);
        d[@"errorDescription"] = self.error.localizedDescription;
    }
    d[@"mediaKind"] = @(self.mediaKind);
    if (self.linkString) d[@"linkString"] = self.linkString;
    d[@"retryable"] = @(self.retryable);
    if (self.detail) d[@"detail"] = self.detail;
    d[@"request"] = [self.request dictionaryRepresentation];
    return d;
}

+ (instancetype)fromDictionary:(NSDictionary *)dict request:(SCIDownloadItemRequest *)request {
    if (![dict isKindOfClass:NSDictionary.class]) return nil;
    SCIDownloadItemRequest *resolvedRequest = request ?: [SCIDownloadItemRequest fromDictionary:dict[@"request"]];
    if (!resolvedRequest) return nil;
    SCIDownloadItem *item = [[self alloc] initWithRequest:resolvedRequest];
    item.state = [dict[@"state"] integerValue];
    item.progress = [dict[@"progress"] doubleValue];
    item.bytesWritten = [dict[@"bytesWritten"] longLongValue];
    item.totalBytesExpected = [dict[@"totalBytesExpected"] longLongValue];
    item.stagedPath = dict[@"stagedPath"];
    item.finalPath = dict[@"finalPath"];
    item.photosAssetIdentifier = dict[@"photosAssetIdentifier"];
    if (dict[@"errorDescription"]) {
        NSString *domain = dict[@"errorDomain"] ?: SCIDownloadErrorDomain;
        item.error = [NSError errorWithDomain:domain code:[dict[@"errorCode"] integerValue] userInfo:@{NSLocalizedDescriptionKey: dict[@"errorDescription"]}];
    }
    item.mediaKind = [dict[@"mediaKind"] integerValue];
    item.linkString = dict[@"linkString"];
    item.retryable = [dict[@"retryable"] boolValue];
    item.detail = dict[@"detail"];
    return item;
}

@end

@implementation SCIDownloadMutableItemSnapshot
@end
