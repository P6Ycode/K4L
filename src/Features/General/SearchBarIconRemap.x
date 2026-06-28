#import "../../Utils.h"
#import "../../AssetUtils.h"

// Replace the Meta-AI "gen AI" search glyph (e.g. ig_icon_search_gen_ai_pano_outline_20)
// with the plain search icon when Meta AI in Explore & Search is hidden.
//
// The Explore search bar picks its icon by an IGDSIconAsset enum whose integer
// value is a name-hash (not derivable from headers, with no live "normal" bar to
// copy it from), so swapping the enum is a dead end. Instead we intercept icon
// image loading by name: when a "*search*gen_ai*" asset is requested we drop the
// "gen_ai" marker and load the matching plain variant (same pano/outline/size),
// which we can resolve ourselves. No magic enum values, and reversible the moment
// the pref is off.

static inline BOOL SCISearchIconRemapActive(void) {
    return [SCIUtils getBoolPref:@"general_hide_meta_ai_explore"];
}

static BOOL SCINameIsGenAISearchIcon(NSString *name) {
    return [name isKindOfClass:[NSString class]] &&
           [name containsString:@"gen_ai"] &&
           [name containsString:@"search"];
}

static NSString *SCIPlainSearchIconName(NSString *genAIName) {
    // ig_icon_search_gen_ai_pano_outline_20 -> ig_icon_search_pano_outline_20
    return [genAIName stringByReplacingOccurrencesOfString:@"_gen_ai" withString:@""];
}

%group SCISearchBarIconRemapHooks

%hook UIImage

+ (UIImage *)imageNamed:(NSString *)name inBundle:(NSBundle *)bundle compatibleWithTraitCollection:(UITraitCollection *)traitCollection {
    // Name check first (cheap string scan); pref read only for the rare match.
    if (SCINameIsGenAISearchIcon(name) && SCISearchIconRemapActive()) {
        NSString *plain = SCIPlainSearchIconName(name);
        UIImage *replacement = %orig(plain, bundle, traitCollection)
            ?: %orig(plain, nil, traitCollection)
            ?: [SCIAssetUtils instagramIconNamed:@"search"];
        if (replacement) return replacement;
    }
    return %orig;
}

+ (UIImage *)imageNamed:(NSString *)name inBundle:(NSBundle *)bundle withConfiguration:(UIImageConfiguration *)configuration {
    if (SCINameIsGenAISearchIcon(name) && SCISearchIconRemapActive()) {
        NSString *plain = SCIPlainSearchIconName(name);
        UIImage *replacement = %orig(plain, bundle, configuration)
            ?: %orig(plain, nil, configuration)
            ?: [SCIAssetUtils instagramIconNamed:@"search"];
        if (replacement) return replacement;
    }
    return %orig;
}

+ (UIImage *)imageNamed:(NSString *)name {
    if (SCINameIsGenAISearchIcon(name) && SCISearchIconRemapActive()) {
        NSString *plain = SCIPlainSearchIconName(name);
        UIImage *replacement = %orig(plain) ?: [SCIAssetUtils instagramIconNamed:@"search"];
        if (replacement) return replacement;
    }
    return %orig;
}

%end

%end

void SCIInstallSearchBarIconRemapHooksIfNeeded(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        %init(SCISearchBarIconRemapHooks);
    });
}
