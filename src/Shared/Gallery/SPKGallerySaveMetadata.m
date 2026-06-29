#import "SPKGallerySaveMetadata.h"
#import "SPKGalleryFile.h"

@implementation SPKGallerySaveMetadata

- (instancetype)init {
    if ((self = [super init])) {
        _source = (int16_t)SPKGallerySourceFeed;
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    SPKGallerySaveMetadata *c = [[SPKGallerySaveMetadata allocWithZone:zone] init];
    c.sourceUsername = [self.sourceUsername copy];
    c.sourceUserPK = [self.sourceUserPK copy];
    c.sourceProfileURLString = [self.sourceProfileURLString copy];
    c.sourceMediaPK = [self.sourceMediaPK copy];
    c.sourceMediaCode = [self.sourceMediaCode copy];
    c.sourceMediaURLString = [self.sourceMediaURLString copy];
    c.source = self.source;
    c.pixelWidth = self.pixelWidth;
    c.pixelHeight = self.pixelHeight;
    c.durationSeconds = self.durationSeconds;
    c.importFileNameStem = [self.importFileNameStem copy];
    c.customName = [self.customName copy];
    c.importCapturedDate = self.importCapturedDate;
    c.importPostedDate = self.importPostedDate;
    return c;
}

@end
