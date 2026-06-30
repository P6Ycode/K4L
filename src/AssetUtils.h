#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPKAssetCatalogSource) {
    SPKAssetCatalogSourceAutomatic = 0,
    SPKAssetCatalogSourceFBSharedFramework = 1,
    SPKAssetCatalogSourceMainApp = 2,
};

typedef NS_ENUM(NSInteger, SPKResolvedImageSource) {
    SPKResolvedImageSourceAutomatic = 0,
    SPKResolvedImageSourceInstagramIcon = 1,
    SPKResolvedImageSourceSystemSymbol = 2,
};

@interface SPKAssetUtils : NSObject

+ (nullable UIImage *)instagramIconNamed:(NSString *)name;
+ (nullable UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize;
+ (nullable UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize renderingMode:(UIImageRenderingMode)renderingMode;

+ (nullable UIImage *)instagramIconNamed:(NSString *)name
                               pointSize:(CGFloat)pointSize
                                  source:(SPKAssetCatalogSource)source
                           renderingMode:(UIImageRenderingMode)renderingMode;

+ (nullable UIImage *)resolvedImageNamed:(NSString *)name
                               pointSize:(CGFloat)pointSize
                                  weight:(UIImageSymbolWeight)weight
                                  source:(SPKResolvedImageSource)source
                           renderingMode:(UIImageRenderingMode)renderingMode;

+ (nullable UIImage *)resolvedImageNamed:(nullable NSString *)name
                      fallbackSystemName:(nullable NSString *)fallbackSystemName
                               pointSize:(CGFloat)pointSize
                                  weight:(UIImageSymbolWeight)weight
                                  source:(SPKResolvedImageSource)source
                           renderingMode:(UIImageRenderingMode)renderingMode;

// Resolves a name (shorthand alias like "carousel"/"action", or a raw
// "ig_icon_*" catalog name) to the canonical Instagram catalog asset name that
// actually renders for it — i.e. the inverse direction of instagramIconNamed:.
// Returns nil if nothing resolves. Used to match a stored icon name against the
// runtime Instagram icon list.
+ (nullable NSString *)resolvedInstagramIconNameForName:(NSString *)name;

@end

NS_ASSUME_NONNULL_END
