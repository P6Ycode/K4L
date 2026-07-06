#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SPKTableCell) {
    SPKTableCellStatic,
    SPKTableCellLink,
    SPKTableCellSwitch,
    SPKTableCellStepper,
    SPKTableCellButton,
    SPKTableCellMenu,
    SPKTableCellNavigation,
    SPKTableCellTextField,
    SPKTableCellValue,
};

///

@interface SPKSetting : NSObject

@property (nonatomic, readonly) SPKTableCell type;

@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSString *subtitle;

@property (nonatomic, strong, nullable) UIImage *icon;
@property (nonatomic, strong, nullable) UIColor *iconTintColor;
@property (nonatomic, copy, nullable) UIImage * (^iconProvider)(void);
@property (nonatomic, copy, nullable) NSString * (^accessoryTextProvider)(void);
@property (nonatomic, copy, nullable) BOOL (^enabledProvider)(void);
@property (nonatomic, strong, nullable) UIColor *tintColor;
@property (nonatomic, strong) NSString *defaultsKey;

@property (nonatomic, strong) NSURL *url;
@property (nonatomic, strong) NSURL *imageUrl;

/// When set, the row's leading image is a self-healing circular avatar loaded
/// via SPKAvatarCache (keyed by PK). `avatarURLString` is the last-known URL;
/// user PKs (numeric) re-resolve a fresh URL when the stored one expires. Group
/// avatars pass a "grp_<threadId>" key + URL and can't be re-resolved.
@property (nonatomic, copy, nullable) NSString *avatarPK;
@property (nonatomic, copy, nullable) NSString *avatarURLString;
@property (nonatomic) BOOL avatarIsGroup;

@property (nonatomic) BOOL requiresRestart;

/// When this switch is turned on, the bool at this key is forced off (and the table reloads). Used for prefs that share one gesture.
@property (nonatomic, copy, nullable) NSString *mutuallyExclusiveDefaultsKey;

@property (nonatomic) double min;
@property (nonatomic) double max;
@property (nonatomic) double step;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *singularLabel;

@property (nonatomic, copy, nullable) NSString *placeholder;
@property (nonatomic) UIKeyboardType keyboardType;

@property (nonatomic, copy) void (^action)(void);
@property (nonatomic, copy, nullable) BOOL (^switchValueProvider)(void);
@property (nonatomic, copy, nullable) void (^switchChangeHandler)(BOOL isOn);
/// When YES, the table reloads after `switchChangeHandler` runs. Default NO so
/// the switch's native (Liquid Glass) toggle animation isn't cut short by a
/// cell rebuild. Set YES only when the row's appearance must refresh on toggle
/// and the handler doesn't already reload the table itself.
@property (nonatomic) BOOL reloadsTableOnSwitchChange;

@property (nonatomic, strong) UIMenu *baseMenu;
@property (nonatomic, strong, nullable) NSDictionary *userInfo;

@property (nonatomic, strong) NSArray *navSections;
@property (nonatomic, strong) UIViewController *navViewController;
@property (nonatomic, copy, nullable) NSArray * (^searchSectionsProvider)(void);
@property (nonatomic, copy, nullable) NSString *searchKeywords;

+ (instancetype)staticCellWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                               icon:(nullable UIImage *)icon;

+ (instancetype)linkCellWithTitle:(NSString *)title
                         subtitle:(NSString *)subtitle
                             icon:(nullable UIImage *)icon
                              url:(NSString *)url;

+ (instancetype)linkCellWithTitle:(NSString *)title
                         subtitle:(NSString *)subtitle
                         imageUrl:(NSString *)imageUrl
                              url:(NSString *)url;

+ (instancetype)switchCellWithTitle:(NSString *)title
                        defaultsKey:(NSString *)defaultsKey;

+ (instancetype)switchCellWithTitle:(NSString *)title
                        defaultsKey:(NSString *)defaultsKey
                    requiresRestart:(BOOL)requiresRestart;

+ (instancetype)switchCellWithTitle:(NSString *)title
                               icon:(nullable UIImage *)icon
                        defaultsKey:(NSString *)defaultsKey;

+ (instancetype)switchCellWithTitle:(NSString *)title
                               icon:(nullable UIImage *)icon
                        defaultsKey:(NSString *)defaultsKey
                    requiresRestart:(BOOL)requiresRestart;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                        defaultsKey:(NSString *)defaultsKey;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                               icon:(nullable UIImage *)icon
                        defaultsKey:(NSString *)defaultsKey;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                        defaultsKey:(NSString *)defaultsKey
                    requiresRestart:(BOOL)requiresRestart;

+ (instancetype)switchCellWithTitle:(NSString *)title
                           subtitle:(NSString *)subtitle
                        defaultsKey:(NSString *)defaultsKey
                    requiresRestart:(BOOL)requiresRestart
       mutuallyExclusiveDefaultsKey:(nullable NSString *)exclusiveDefaultsKey;

+ (instancetype)stepperCellWithTitle:(NSString *)title
                            subtitle:(NSString *)subtitle
                         defaultsKey:(NSString *)defaultsKey
                                 min:(double)min
                                 max:(double)max
                                step:(double)step
                               label:(NSString *)label
                       singularLabel:(NSString *)singularLabel;

+ (instancetype)stepperCellWithTitle:(NSString *)title
                            subtitle:(NSString *)subtitle
                                icon:(nullable UIImage *)icon
                         defaultsKey:(NSString *)defaultsKey
                                 min:(double)min
                                 max:(double)max
                                step:(double)step
                               label:(NSString *)label
                       singularLabel:(NSString *)singularLabel;

+ (instancetype)buttonCellWithTitle:(NSString *)title
                           subtitle:(nullable NSString *)subtitle
                               icon:(nullable UIImage *)icon
                             action:(void (^)(void))action;

+ (instancetype)menuCellWithTitle:(NSString *)title
                         subtitle:(nullable NSString *)subtitle
                             menu:(UIMenu *)menu;

+ (instancetype)menuCellWithTitle:(NSString *)title
                             icon:(nullable UIImage *)icon
                             menu:(UIMenu *)menu;

+ (instancetype)menuCellWithTitle:(NSString *)title
                         subtitle:(nullable NSString *)subtitle
                             icon:(nullable UIImage *)icon
                             menu:(UIMenu *)menu;

+ (instancetype)navigationCellWithTitle:(NSString *)title
                               subtitle:(nullable NSString *)subtitle
                                   icon:(nullable UIImage *)icon
                            navSections:(NSArray *)navSections;

+ (instancetype)navigationCellWithTitle:(NSString *)title
                               subtitle:(nullable NSString *)subtitle
                                   icon:(nullable UIImage *)icon
                         viewController:(UIViewController *)viewController;

+ (instancetype)textFieldCellWithTitle:(NSString *)title
                           placeholder:(nullable NSString *)placeholder
                          keyboardType:(UIKeyboardType)keyboardType
                           defaultsKey:(NSString *)defaultsKey;

+ (instancetype)valueCellWithTitle:(NSString *)title
                          subtitle:(nullable NSString *)subtitle
                              icon:(nullable UIImage *)icon;

#pragma mark - Instance methods

- (UIMenu *)menuForButton:(UIButton *)button;

@end

NS_ASSUME_NONNULL_END
