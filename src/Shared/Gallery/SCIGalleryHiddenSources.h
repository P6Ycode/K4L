#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const kSCIGalleryHiddenSourcesKey;
FOUNDATION_EXPORT NSNotificationName const SCIGalleryHiddenSourcesDidChangeNotification;

NSArray<NSNumber *> *SCIGalleryHiddenSources(void);
NSPredicate * _Nullable SCIGalleryVisibleSourcesPredicate(void);
BOOL SCIGallerySourceIsHidden(NSInteger source);
void SCIGallerySetSourceHidden(NSInteger source, BOOL hidden);

NS_ASSUME_NONNULL_END
