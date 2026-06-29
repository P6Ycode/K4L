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
+ (nullable UIImage *)instagramIconNamed:(NSString *)name pointSize:(CGFloat)pointSize source:(SPKAssetCatalogSource)source;

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

@end

NS_ASSUME_NONNULL_END
