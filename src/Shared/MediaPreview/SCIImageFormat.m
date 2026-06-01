#import "SCIImageFormat.h"

SCIImageFormat SCIImageFormatForData(NSData *data) {
    if (data.length < 4) return SCIImageFormatUnknown;
    const unsigned char *bytes = data.bytes;
    if (data.length >= 6 && (!memcmp(bytes, "GIF87a", 6) || !memcmp(bytes, "GIF89a", 6))) {
        return SCIImageFormatGIF;
    }
    if (data.length >= 12 && !memcmp(bytes, "RIFF", 4) && !memcmp(bytes + 8, "WEBP", 4)) {
        return SCIImageFormatWebP;
    }
    if (data.length >= 8 && !memcmp(bytes, "\x89PNG\r\n\x1a\n", 8)) {
        return SCIImageFormatPNG;
    }
    if (bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff) {
        return SCIImageFormatJPEG;
    }
    if (data.length >= 12 && !memcmp(bytes + 4, "ftyp", 4)) {
        return SCIImageFormatMP4;
    }
    return SCIImageFormatUnknown;
}

SCIImageFormat SCIImageFormatForFileURL(NSURL *fileURL) {
    if (!fileURL.isFileURL) return SCIImageFormatUnknown;
    NSData *data = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:nil];
    return SCIImageFormatForData(data);
}

NSString *SCIFileExtensionForImageFormat(SCIImageFormat format) {
    switch (format) {
        case SCIImageFormatJPEG: return @"jpg";
        case SCIImageFormatPNG:  return @"png";
        case SCIImageFormatGIF:  return @"gif";
        case SCIImageFormatWebP: return @"webp";
        case SCIImageFormatMP4:  return @"mp4";
        default:                 return nil;
    }
}

NSString *SCIMIMETypeForImageFormat(SCIImageFormat format) {
    switch (format) {
        case SCIImageFormatJPEG: return @"image/jpeg";
        case SCIImageFormatPNG:  return @"image/png";
        case SCIImageFormatGIF:  return @"image/gif";
        case SCIImageFormatWebP: return @"image/webp";
        case SCIImageFormatMP4:  return @"video/mp4";
        default:                 return nil;
    }
}

NSString *SCIFileExtensionForMediaResponse(NSData *data, NSURLResponse *response, NSURL *sourceURL) {
    NSString *detected = SCIFileExtensionForImageFormat(SCIImageFormatForData(data));
    if (detected.length) return detected;

    NSString *mime = response.MIMEType.lowercaseString;
    NSDictionary *mimeExtensions = @{
        @"image/gif": @"gif", @"image/webp": @"webp", @"image/jpeg": @"jpg",
        @"image/jpg": @"jpg", @"image/png": @"png", @"video/mp4": @"mp4",
    };
    NSString *fromMIME = mimeExtensions[mime];
    if (fromMIME.length) return fromMIME;

    NSString *suggested = response.suggestedFilename.pathExtension.lowercaseString;
    if (suggested.length) return suggested;
    return sourceURL.pathExtension.lowercaseString;
}
