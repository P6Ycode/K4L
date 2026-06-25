#pragma once

#import <Foundation/Foundation.h>

/// Tag for views whose content should be hidden from screenshots/recordings
/// when `interface_hide_ui_on_capture` is on. A view carrying this tag has its
/// subviews redirected into a secure (capture-proof) canvas. Add a SCInsta view
/// to the capture-hidden set by giving it this tag before its subviews are added.
FOUNDATION_EXPORT const NSInteger kSCICaptureFollowIndicatorTag;

FOUNDATION_EXPORT void SCIInstallCaptureHidingHooksIfNeeded(void);
