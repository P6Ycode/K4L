#pragma once

#import "ActionButtonCore.h"
#import "SPKActionMenuSection.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPKActionButtonConfiguration : NSObject

@property (nonatomic) SPKActionButtonSource source;
@property (nonatomic, copy) NSString *topicTitle;
@property (nonatomic, copy) NSArray<NSString *> *supportedActions;
@property (nonatomic, strong) NSMutableArray<SPKActionMenuSection *> *sections;
@property (nonatomic, strong) NSMutableArray<NSString *> *disabledActions;
@property (nonatomic, strong) NSMutableArray<NSString *> *unassignedActions;

+ (instancetype)configurationForSource:(SPKActionButtonSource)source
                            topicTitle:(NSString *)topicTitle
                      supportedActions:(NSArray<NSString *> *)supportedActions
                       defaultSections:(NSArray<SPKActionMenuSection *> *)defaultSections;

- (NSString *)configDefaultsKey;
- (NSDictionary *)dictionaryRepresentation;
- (void)save;
- (void)normalize;
- (nullable SPKActionMenuSection *)sectionWithIdentifier:(NSString *)identifier;
- (NSArray<SPKActionMenuSection *> *)visibleSections;
- (NSArray<NSString *> *)assignedActions;
- (nullable NSString *)sectionIdentifierForAction:(NSString *)identifier;
- (void)setAction:(NSString *)identifier assignedToSectionIdentifier:(nullable NSString *)sectionIdentifier;
- (void)moveSectionFromIndex:(NSInteger)sourceIndex toIndex:(NSInteger)destinationIndex;
- (void)moveActionInSectionIdentifier:(NSString *)sectionIdentifier fromIndex:(NSInteger)sourceIndex toIndex:(NSInteger)destinationIndex;

@end

FOUNDATION_EXPORT NSString *SPKActionButtonTopicKeyForSource(SPKActionButtonSource source);
FOUNDATION_EXPORT NSString *SPKActionButtonTopicTitleForSource(SPKActionButtonSource source);
FOUNDATION_EXPORT NSArray<NSString *> *SPKActionButtonSupportedActionsForSource(SPKActionButtonSource source);
FOUNDATION_EXPORT NSArray<SPKActionMenuSection *> *SPKActionButtonDefaultSectionsForSource(SPKActionButtonSource source);
FOUNDATION_EXPORT NSArray<NSString *> *SPKActionButtonBulkDownloadSupportedActionsForSource(SPKActionButtonSource source);
FOUNDATION_EXPORT NSArray<NSString *> *SPKActionButtonBulkCopySupportedActionsForSource(SPKActionButtonSource source);
// Bulk destinations are derived from the configured single-item actions (see
// implementation); there is no separate bulk store to set.
FOUNDATION_EXPORT NSArray<NSString *> *SPKActionButtonConfiguredBulkDownloadActionsForSource(SPKActionButtonSource source);
FOUNDATION_EXPORT NSArray<NSString *> *SPKActionButtonConfiguredBulkCopyActionsForSource(SPKActionButtonSource source);

FOUNDATION_EXPORT NSArray<NSString *> *SPKProfileCopyInfoSupportedActions(void);
FOUNDATION_EXPORT NSArray<NSString *> *SPKProfileConfiguredCopyInfoActions(void);
FOUNDATION_EXPORT void SPKProfileSetConfiguredCopyInfoActions(NSArray<NSString *> *actions);

NS_ASSUME_NONNULL_END
