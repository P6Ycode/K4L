#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIImageFormat) {
    SCIImageFormatUnknown = 0,
    SCIImageFormatJPEG,
    SCIImageFormatPNG,
    SCIImageFormatGIF,
    SCIImageFormatWebP,
    SCIImageFormatMP4,
};

FOUNDATION_EXPORT SCIImageFormat SCIImageFormatForData(NSData * _Nullable data);
FOUNDATION_EXPORT SCIImageFormat SCIImageFormatForFileURL(NSURL * _Nullable fileURL);
FOUNDATION_EXPORT NSString * _Nullable SCIFileExtensionForImageFormat(SCIImageFormat format);
FOUNDATION_EXPORT NSString * _Nullable SCIMIMETypeForImageFormat(SCIImageFormat format);
FOUNDATION_EXPORT NSString * _Nullable SCIFileExtensionForMediaResponse(NSData * _Nullable data,
                                                                        NSURLResponse * _Nullable response,
                                                                        NSURL * _Nullable sourceURL);

NS_ASSUME_NONNULL_END
