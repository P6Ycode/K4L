#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>

#import "../../Utils.h"
#import "../../AssetUtils.h"
#import "../../Shared/ActionButton/ActionButtonCore.h"
#import "../../Shared/ActionButton/SCIActionButtonConfiguration.h"
#import "../../Shared/ActionButton/ActionButtonLookupUtils.h"

static NSInteger const kSCIInstantsActionButtonTag = 921399;
static NSInteger const kSCIInstantsGalleryButtonTag = 921401;
static const void *kSCIInstantsActionButtonSignatureKey = &kSCIInstantsActionButtonSignatureKey;
static const void *kSCIInstantsActionFrameKey = &kSCIInstantsActionFrameKey;

@interface SCIInstantsResolvedSnap : NSObject
@property (nonatomic, strong) NSURL *scinstaMediaURL;
@property (nonatomic, copy) NSString *sourceUsername;
@property (nonatomic, copy) NSString *sourceMediaPK;
@property (nonatomic, copy) NSString *sourceMediaURLString;
@property (nonatomic, strong) NSDate *importPostedDate;
@property (nonatomic, strong) id backingMedia;
@end

@implementation SCIInstantsResolvedSnap
- (NSURL *)url { return self.scinstaMediaURL; }
- (NSURL *)imageURL { return self.scinstaMediaURL; }
- (NSDate *)takenAt { return self.importPostedDate; }
- (id)media { return self.backingMedia; }
@end

static UIWindow *SCIInstantsWindowForView(UIView *view) {
    if (view.window) return view.window;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return nil;
}

static void SCIInstantsWalkViews(UIView *root, void (^visitor)(UIView *view, BOOL *stop)) {
    if (!root || !visitor) return;
    BOOL stop = NO;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count > 0 && !stop) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        visitor(view, &stop);
        if (stop) break;
        for (UIView *subview in view.subviews) {
            [queue addObject:subview];
        }
    }
}

static UIImageView *SCIInstantsImageViewInSnap(UIView *snap) {
    if (!snap) return nil;
    Class igImageViewClass = NSClassFromString(@"IGImageView");
    __block UIImageView *fallback = nil;
    __block UIImageView *result = nil;
    SCIInstantsWalkViews(snap, ^(UIView *view, BOOL *stop) {
        if (view.hidden || view.alpha < 0.05) return;
        if (view.bounds.size.width < 8.0 || view.bounds.size.height < 8.0) return;
        BOOL isImageView = [view isKindOfClass:UIImageView.class] ||
                           (igImageViewClass && [view isKindOfClass:igImageViewClass]);
        if (!isImageView) return;

        UIImageView *imageView = (UIImageView *)view;
        if (imageView.image) {
            result = imageView;
            *stop = YES;
            return;
        }

        id spec = nil;
        @try { spec = [imageView valueForKey:@"imageSpecifier"]; } @catch (__unused NSException *exception) {}
        NSURL *url = SCIURLFromValue(SCIObjectForSelector(spec, @"url") ?: SCIKVCObject(spec, @"url"));
        if (url) {
            result = imageView;
            *stop = YES;
            return;
        }
        if (!fallback) fallback = imageView;
    });
    return result ?: fallback;
}

static NSURL *SCIInstantsURLForImageView(UIImageView *imageView) {
    if (!imageView) return nil;
    id spec = nil;
    @try { spec = [imageView valueForKey:@"imageSpecifier"]; } @catch (__unused NSException *exception) {}
    NSURL *url = SCIURLFromValue(SCIObjectForSelector(spec, @"url") ?: SCIKVCObject(spec, @"url"));
    if (url) return url;
    return SCIURLFromValue(SCIObjectForSelector(imageView, @"url") ?: SCIKVCObject(imageView, @"url"));
}

static NSURL *SCIInstantsTempURLForImage(UIImage *image) {
    if (!image) return nil;
    NSData *data = UIImageJPEGRepresentation(image, 1.0);
    if (!data) return nil;

    NSString *name = [NSString stringWithFormat:@"scinsta-instant-%@.jpg", NSUUID.UUID.UUIDString];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSError *error = nil;
    if (![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        SCILog(@"Instants", @"[SCInsta] Failed to write temp instant image: %@", error.localizedDescription ?: @"unknown");
        return nil;
    }
    return url;
}

static id SCIInstantsFirstObjectForSelectors(id target, NSArray<NSString *> *selectors) {
    if (!target) return nil;
    for (NSString *selectorName in selectors) {
        id value = SCIObjectForSelector(target, selectorName);
        if (!value) value = SCIKVCObject(target, selectorName);
        if (value) return value;
    }
    return nil;
}

static NSTimeInterval SCIInstantsTimestampFromValue(id value) {
    if (!value || [value isKindOfClass:NSNull.class]) return 0.0;
    if ([value isKindOfClass:NSDate.class]) return [(NSDate *)value timeIntervalSince1970];
    if ([value respondsToSelector:@selector(doubleValue)]) {
        double raw = [value doubleValue];
        if (raw > 1e15) raw /= 1000000.0;
        else if (raw > 1e12) raw /= 1000.0;
        return raw > 0.0 ? raw : 0.0;
    }
    return 0.0;
}

static NSDate *SCIInstantsDateFromObject(id object, NSInteger depth) {
    if (!object || depth > 3) return nil;
    for (NSString *key in @[@"takenAt", @"taken_at", @"takenAtDate", @"device_timestamp", @"deviceTimestamp", @"created_at", @"createdAt", @"upload_time", @"uploadTime", @"published_time", @"publishedTime"]) {
        id value = SCIObjectForSelector(object, key);
        if (!value) value = SCIKVCObject(object, key);
        NSTimeInterval timestamp = SCIInstantsTimestampFromValue(value);
        if (timestamp > 0.0) return [NSDate dateWithTimeIntervalSince1970:timestamp];
    }
    for (NSString *nestedName in @[@"media", @"item", @"model", @"viewModel", @"legacyViewModel", @"quickSnapInfo", @"snap", @"instantSnap"]) {
        id nested = SCIObjectForSelector(object, nestedName);
        if (!nested) nested = SCIKVCObject(object, nestedName);
        if (!nested || nested == object) continue;
        NSDate *date = SCIInstantsDateFromObject(nested, depth + 1);
        if (date) return date;
    }
    return nil;
}

static NSString *SCIInstantsMediaIDFromObject(id object, NSInteger depth) {
    if (!object || depth > 3) return nil;
    for (NSString *key in @[@"graphQLID", @"mediaId", @"mediaID", @"pk", @"id"]) {
        NSString *value = SCIStringFromValue(SCIObjectForSelector(object, key));
        if (value.length == 0) value = SCIStringFromValue(SCIKVCObject(object, key));
        if (value.length > 0) return value;
    }
    for (NSString *nestedName in @[@"media", @"item", @"model", @"viewModel", @"legacyViewModel", @"quickSnapInfo", @"snap", @"instantSnap"]) {
        id nested = SCIObjectForSelector(object, nestedName);
        if (!nested) nested = SCIKVCObject(object, nestedName);
        if (!nested || nested == object) continue;
        NSString *value = SCIInstantsMediaIDFromObject(nested, depth + 1);
        if (value.length > 0) return value;
    }
    return nil;
}

static id SCIInstantsBackingObjectFromView(UIView *view, NSInteger depth) {
    if (!view || depth > 4) return nil;
    id candidate = SCIInstantsFirstObjectForSelectors(view, @[@"media", @"item", @"model", @"viewModel", @"legacyViewModel", @"quickSnapInfo", @"snap", @"instantSnap"]);
    if (candidate) return candidate;
    for (UIView *subview in view.subviews) {
        candidate = SCIInstantsBackingObjectFromView(subview, depth + 1);
        if (candidate) return candidate;
    }
    return nil;
}

static NSString *SCIInstantsNormalizeUsername(NSString *username) {
    NSString *trimmed = [SCIStringFromValue(username) stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if ([trimmed hasPrefix:@"@"]) trimmed = [trimmed substringFromIndex:1];
    return trimmed.length > 0 ? trimmed : nil;
}

static NSString *SCIInstantsVisibleAuthorUsername(UIView *root) {
    if (!root) return nil;
    Class authorTextClass = NSClassFromString(@"_TtC32IGQuickSnapConsumptionAuthorInfo36IGQuickSnapConsumptionAuthorTextView");
    __block NSString *username = nil;
    SCIInstantsWalkViews(SCIInstantsWindowForView(root) ?: root, ^(UIView *view, BOOL *stop) {
        if (view.hidden || view.alpha < 0.05) return;
        BOOL isAuthorView = authorTextClass && [view isKindOfClass:authorTextClass];
        if (isAuthorView) {
            username = SCIInstantsNormalizeUsername(SCIStringFromValue(SCIObjectForSelector(view, @"currentUsername") ?: SCIKVCObject(view, @"currentUsername")));
            if (username.length == 0) {
                UILabel *label = (UILabel *)SCIInstantsFirstObjectForSelectors(view, @[@"usernameLabel", @"_usernameLabel"]);
                if ([label isKindOfClass:UILabel.class]) username = SCIInstantsNormalizeUsername(label.text);
            }
            if (username.length > 0) {
                *stop = YES;
                return;
            }
        }
        if (![view isKindOfClass:UILabel.class]) return;
        NSString *text = SCIInstantsNormalizeUsername(((UILabel *)view).text);
        if (text.length == 0 || text.length > 30) return;
        NSCharacterSet *bad = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._"] invertedSet];
        if ([text rangeOfCharacterFromSet:bad].location == NSNotFound &&
            ![@[@"now", @"send", @"reply", @"share", @"new", @"instant", @"download", @"save", @"copy", @"expand", @"gallery", @"photos"] containsObject:text.lowercaseString]) {
            username = text;
            *stop = YES;
        }
    });
    return username;
}

static NSArray<UIView *> *SCIInstantsSnapViewsForHeader(UIView *header) {
    UIWindow *window = SCIInstantsWindowForView(header);
    if (!window) return @[];

    NSMutableArray<UIView *> *snaps = [NSMutableArray array];
    SCIInstantsWalkViews(window, ^(UIView *view, __unused BOOL *stop) {
        if ([NSStringFromClass(view.class) containsString:@"IGQuickSnapImmersiveViewerSingleSnapView"]) {
            [snaps addObject:view];
        }
    });
    return snaps;
}

static UIView *SCIInstantsActiveSnapForHeader(UIView *header) {
    NSArray<UIView *> *snaps = SCIInstantsSnapViewsForHeader(header);
    UIView *best = nil;
    NSUInteger bestIndex = 0;
    for (UIView *snap in snaps) {
        if (snap.hidden || snap.alpha < 0.5) continue;
        UIImageView *imageView = SCIInstantsImageViewInSnap(snap);
        if (!imageView || (!imageView.image && !SCIInstantsURLForImageView(imageView))) continue;

        CGAffineTransform transform = snap.transform;
        CGFloat transformDistance = fabs(transform.a - 1.0) + fabs(transform.b) + fabs(transform.c) + fabs(transform.d - 1.0);
        if (transformDistance > 0.1) continue;

        NSUInteger index = snap.superview ? [snap.superview.subviews indexOfObject:snap] : 0;
        if (!best || index >= bestIndex) {
            best = snap;
            bestIndex = index;
        }
    }
    return best;
}

static SCIInstantsResolvedSnap *SCIInstantsResolvedSnapForHeader(UIView *header) {
    UIView *snap = SCIInstantsActiveSnapForHeader(header);
    if (!snap) return nil;
    UIImageView *imageView = SCIInstantsImageViewInSnap(snap);
    NSURL *url = SCIInstantsURLForImageView(imageView);
    if (!url) url = SCIInstantsTempURLForImage(imageView.image);
    if (!url) return nil;

    id backingMedia = SCIInstantsBackingObjectFromView(snap, 0) ?: SCIInstantsBackingObjectFromView(imageView, 0);
    SCIInstantsResolvedSnap *resolved = [[SCIInstantsResolvedSnap alloc] init];
    resolved.scinstaMediaURL = url;
    resolved.sourceMediaURLString = url.absoluteString;
    resolved.backingMedia = backingMedia;
    resolved.sourceUsername = SCIUsernameFromMediaObject(backingMedia) ?: SCIInstantsVisibleAuthorUsername(snap);
    resolved.sourceMediaPK = SCIInstantsMediaIDFromObject(backingMedia, 0);
    resolved.importPostedDate = SCIInstantsDateFromObject(backingMedia, 0);
    return resolved;
}

static NSString *SCIInstantsMediaSignatureForHeader(UIView *header) {
    UIView *snap = SCIInstantsActiveSnapForHeader(header);
    UIImageView *imageView = SCIInstantsImageViewInSnap(snap);
    NSURL *url = SCIInstantsURLForImageView(imageView);
    if (url.absoluteString.length > 0) {
        return [NSString stringWithFormat:@"url:%@", url.absoluteString];
    }
    if (imageView.image) {
        return [NSString stringWithFormat:@"image:%p", imageView.image];
    }
    return nil;
}

static UIView *SCIInstantsHeaderOwnedView(UIView *header, NSString *key) {
    if (!header || key.length == 0) return nil;
    id view = nil;
    @try { view = [header valueForKey:key]; } @catch (__unused NSException *exception) {}
    if (![view isKindOfClass:UIView.class]) {
        Ivar ivar = class_getInstanceVariable(header.class, key.UTF8String);
        if (ivar) {
            @try { view = object_getIvar(header, ivar); } @catch (__unused NSException *exception) {}
        }
    }
    return [view isKindOfClass:UIView.class] ? (UIView *)view : nil;
}

static UIView *SCIInstantsHeaderArchiveButton(UIView *header) {
    UIView *archiveButton = SCIInstantsHeaderOwnedView(header, @"archiveButton");
    if (archiveButton && archiveButton.superview == header && !archiveButton.hidden && archiveButton.alpha >= 0.01) {
        return archiveButton;
    }
    return nil;
}

static UIView *SCIInstantsFallbackRightAnchor(UIView *header, UIView *button) {
    CGFloat halfWidth = header.bounds.size.width / 2.0;
    UIView *anchor = nil;
    CGFloat minX = CGFLOAT_MAX;
    for (UIView *subview in header.subviews) {
        if (subview == button || subview.tag == kSCIInstantsGalleryButtonTag || subview.hidden || subview.alpha < 0.01) continue;
        if (subview.bounds.size.width < 4.0 || subview.bounds.size.height < 4.0) continue;
        if (CGRectGetMidX(subview.frame) < halfWidth) continue;
        if (CGRectGetMinX(subview.frame) < minX) {
            anchor = subview;
            minX = CGRectGetMinX(subview.frame);
        }
    }
    return anchor;
}

static BOOL SCIInstantsActionFrameMatches(UIButton *button, CGRect frame) {
    if (![button isKindOfClass:UIButton.class] || button.hidden || !button.superview) return NO;
    return ABS(CGRectGetMinX(button.frame) - CGRectGetMinX(frame)) < 0.5 &&
           ABS(CGRectGetMinY(button.frame) - CGRectGetMinY(frame)) < 0.5 &&
           ABS(CGRectGetWidth(button.frame) - CGRectGetWidth(frame)) < 0.5 &&
           ABS(CGRectGetHeight(button.frame) - CGRectGetHeight(frame)) < 0.5;
}

static SCIActionButtonContext *SCIInstantsActionContext(UIView *header, UIButton *button, SCIInstantsResolvedSnap *resolvedSnap) {
    SCIActionButtonContext *context = [[SCIActionButtonContext alloc] init];
    context.source = SCIActionButtonSourceInstants;
    context.view = button ?: header;
    context.controller = [SCIUtils viewControllerForAncestralView:header] ?: topMostController();
    context.settingsTitle = SCIActionButtonTopicTitleForSource(SCIActionButtonSourceInstants);
    context.supportedActions = SCIActionButtonSupportedActionsForSource(SCIActionButtonSourceInstants);
    __weak UIView *weakHeader = header;
    SCIInstantsResolvedSnap *snapForMenu = resolvedSnap;
    context.mediaResolver = ^id (__unused SCIActionButtonContext *resolvedContext) {
        return snapForMenu ?: SCIInstantsResolvedSnapForHeader(weakHeader);
    };
    context.currentIndexResolver = ^NSInteger (__unused SCIActionButtonContext *resolvedContext) {
        return 0;
    };
    return context;
}

static void SCIRemoveInstantsActionButton(UIView *header) {
    UIButton *button = (UIButton *)[header viewWithTag:kSCIInstantsActionButtonTag];
    [button removeFromSuperview];
}

static NSString *SCIInstantsFrameKey(UIView *header, UIView *anchor, CGRect frame) {
    return [NSString stringWithFormat:@"%p|%@|%@",
            anchor ?: header,
            NSStringFromCGRect(anchor ? anchor.frame : CGRectZero),
            NSStringFromCGRect(frame)];
}

static void SCIInstallInstantsActionButton(UIView *header) {
    if (!header) return;
    if (![SCIUtils getBoolPref:@"instants_action_btn"]) {
        SCIRemoveInstantsActionButton(header);
        return;
    }

    NSString *mediaSignature = SCIInstantsMediaSignatureForHeader(header);
    if (mediaSignature.length == 0) {
        SCIRemoveInstantsActionButton(header);
        return;
    }

    UIButton *button = (UIButton *)[header viewWithTag:kSCIInstantsActionButtonTag];
    if (!button) {
        button = SCIActionButtonWithTag(header, kSCIInstantsActionButtonTag);
        button.translatesAutoresizingMaskIntoConstraints = YES;
        [header addSubview:button];
    }

    CGFloat side = 44.0;
    CGFloat gap = 0.0;
    UIView *anchor = SCIInstantsHeaderArchiveButton(header) ?: SCIInstantsFallbackRightAnchor(header, button);

    CGRect frame = CGRectZero;
    if (anchor) {
        frame = CGRectMake(CGRectGetMinX(anchor.frame) - side - gap,
                           CGRectGetMidY(anchor.frame) - side / 2.0,
                           side,
                           side);
    } else {
        frame = CGRectMake(header.bounds.size.width - side - 12.0,
                           (header.bounds.size.height - side) / 2.0,
                           side,
                           side);
    }

    NSString *previousSignature = objc_getAssociatedObject(button, kSCIInstantsActionButtonSignatureKey);
    BOOL needsConfigure = ![previousSignature isEqualToString:mediaSignature] || button.menu == nil || button.hidden;
    NSString *frameKey = SCIInstantsFrameKey(header, anchor, frame);
    NSString *previousFrameKey = objc_getAssociatedObject(button, kSCIInstantsActionFrameKey);
    if (!needsConfigure && [previousFrameKey isEqualToString:frameKey] && SCIInstantsActionFrameMatches(button, frame)) {
        return;
    }

    if (needsConfigure) {
        SCIInstantsResolvedSnap *resolvedSnap = SCIInstantsResolvedSnapForHeader(header);
        if (!resolvedSnap) {
            SCIRemoveInstantsActionButton(header);
            return;
        }
        SCIApplyButtonStyle(button, SCIActionButtonSourceInstants);
        SCIConfigureActionButton(button, SCIInstantsActionContext(header, button, resolvedSnap));
        objc_setAssociatedObject(button, kSCIInstantsActionButtonSignatureKey, mediaSignature, OBJC_ASSOCIATION_COPY_NONATOMIC);
        if (button.hidden) return;
    }

    if (!SCIInstantsActionFrameMatches(button, frame)) {
        button.frame = frame;
    }
    objc_setAssociatedObject(button, kSCIInstantsActionFrameKey, frameKey, OBJC_ASSOCIATION_COPY_NONATOMIC);
    button.hidden = NO;
    button.alpha = 1.0;
    [header bringSubviewToFront:button];
}

typedef void (*SCIInstantsHeaderLayoutIMP)(id, SEL);
static SCIInstantsHeaderLayoutIMP orig_instantsHeaderLayoutSubviews = NULL;

static void replaced_instantsHeaderLayoutSubviews(id self, SEL _cmd) {
    if (orig_instantsHeaderLayoutSubviews) orig_instantsHeaderLayoutSubviews(self, _cmd);
    SCIInstallInstantsActionButton((UIView *)self);
}

static void SCIHookInstanceMethod(const char *className, SEL selector, IMP replacement, IMP *original) {
    Class cls = objc_getClass(className);
    Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
    if (!cls || !method) {
        SCILog(@"Instants", @"[SCInsta] Missing hook target %s %@", className, NSStringFromSelector(selector));
        return;
    }
    MSHookMessageEx(cls, selector, replacement, original);
}

extern "C" void SCIInstallInstantsActionButtonHooksIfEnabled(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        SCIHookInstanceMethod("_TtC45IGQuickSnapNavigationV3HeaderButtonController39IGQuickSnapNavigationV3HeaderButtonView",
                              @selector(layoutSubviews),
                              (IMP)replaced_instantsHeaderLayoutSubviews,
                              (IMP *)&orig_instantsHeaderLayoutSubviews);
        SCILog(@"Instants", @"[SCInsta] Instants action button hooks installed");
    });
}
