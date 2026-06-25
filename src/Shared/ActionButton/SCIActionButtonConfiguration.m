#import "SCIActionButtonConfiguration.h"
#import "SCIActionDescriptor.h"
#import "../../Settings/SCIPreferences.h"
#import "../../Utils.h"

static NSArray<NSString *> *SCIFilteredActionArray(NSArray *values, NSArray<NSString *> *supported) {
    NSMutableOrderedSet<NSString *> *filtered = [NSMutableOrderedSet orderedSet];
    for (id value in values) {
        if ([value isKindOfClass:[NSString class]] && [supported containsObject:value]) {
            [filtered addObject:value];
        }
    }
    return filtered.array;
}

static NSArray<NSString *> *SCIFilteredUniqueActionArray(NSArray *values, NSArray<NSString *> *supported) {
    return SCIFilteredActionArray(values, supported);
}

NSString *SCIActionButtonTopicKeyForSource(SCIActionButtonSource source) {
    switch (source) {
        case SCIActionButtonSourceFeed: return @"feed";
        case SCIActionButtonSourceReels: return @"reels";
        case SCIActionButtonSourceStories: return @"stories";
        case SCIActionButtonSourceDirect: return @"msgs";
        case SCIActionButtonSourceProfile: return @"profile";
        case SCIActionButtonSourceInstants: return @"instants";
    }
}

NSString *SCIActionButtonTopicTitleForSource(SCIActionButtonSource source) {
    switch (source) {
        case SCIActionButtonSourceFeed: return @"Feed";
        case SCIActionButtonSourceReels: return @"Reels";
        case SCIActionButtonSourceStories: return @"Stories";
        case SCIActionButtonSourceDirect: return @"Messages";
        case SCIActionButtonSourceProfile: return @"Profile";
        case SCIActionButtonSourceInstants: return @"Instants";
    }
}

NSArray<NSString *> *SCIActionButtonSupportedActionsForSource(SCIActionButtonSource source) {
    switch (source) {
        case SCIActionButtonSourceFeed:
        case SCIActionButtonSourceReels:
            return @[
                kSCIActionDownloadLibrary,
                kSCIActionDownloadShare,
                kSCIActionCopyDownloadLink,
                kSCIActionCopyMedia,
                kSCIActionDownloadGallery,
                kSCIActionTrimSave,
                kSCIActionDownloadAudio,
                kSCIActionDownloadAudioShare,
                kSCIActionDownloadAudioGallery,
                kSCIActionPlayAudio,
                kSCIActionCopyAudioURL,
                kSCIActionExpand,
                kSCIActionViewThumbnail,
                kSCIActionCopyCaption,
                kSCIActionOpenTopicSettings,
                kSCIActionRepost
            ];
        case SCIActionButtonSourceStories:
            return @[
                kSCIActionDownloadLibrary,
                kSCIActionDownloadShare,
                kSCIActionCopyDownloadLink,
                kSCIActionCopyMedia,
                kSCIActionDownloadGallery,
                kSCIActionTrimSave,
                kSCIActionDownloadAudio,
                kSCIActionDownloadAudioShare,
                kSCIActionDownloadAudioGallery,
                kSCIActionPlayAudio,
                kSCIActionCopyAudioURL,
                kSCIActionExpand,
                kSCIActionViewThumbnail,
                kSCIActionStoryMentionsSheet,
                kSCIActionToggleStorySeenUserRule,
                kSCIActionOpenTopicSettings
            ];
        case SCIActionButtonSourceDirect:
            return @[
                kSCIActionDownloadLibrary,
                kSCIActionDownloadShare,
                kSCIActionCopyDownloadLink,
                kSCIActionCopyMedia,
                kSCIActionDownloadGallery,
                kSCIActionTrimSave,
                kSCIActionExpand,
                kSCIActionViewThumbnail,
                kSCIActionDeletedMessagesLog,
                kSCIActionOpenTopicSettings
            ];
        case SCIActionButtonSourceInstants:
            return @[
                kSCIActionDownloadLibrary,
                kSCIActionDownloadShare,
                kSCIActionCopyDownloadLink,
                kSCIActionCopyMedia,
                kSCIActionDownloadGallery,
                kSCIActionTrimSave,
                kSCIActionExpand,
                kSCIActionViewThumbnail,
                kSCIActionOpenTopicSettings
            ];
        case SCIActionButtonSourceProfile:
            return @[
                kSCIActionDownloadLibrary,
                kSCIActionDownloadShare,
                kSCIActionCopyDownloadLink,
                kSCIActionCopyMedia,
                kSCIActionDownloadGallery,
                kSCIActionTrimSave,
                kSCIActionExpand,
                kSCIActionProfileCopyInfo,
                kSCIActionToggleProfileStorySeenUserRule,
                kSCIActionToggleProfileMessagesSeenUserRule,
                kSCIActionOpenTopicSettings
            ];
    }
}

NSArray<NSString *> *SCIActionButtonBulkDownloadSupportedActionsForSource(SCIActionButtonSource source) {
    switch (source) {
        case SCIActionButtonSourceFeed:
        case SCIActionButtonSourceReels:
        case SCIActionButtonSourceStories:
        case SCIActionButtonSourceInstants:
        case SCIActionButtonSourceDirect:
            return @[
                kSCIActionDownloadAllLibrary,
                kSCIActionDownloadAllShare,
                kSCIActionDownloadAllGallery
            ];
        case SCIActionButtonSourceProfile:
            return @[];
    }
}

NSArray<NSString *> *SCIActionButtonBulkCopySupportedActionsForSource(SCIActionButtonSource source) {
    switch (source) {
        case SCIActionButtonSourceFeed:
        case SCIActionButtonSourceReels:
        case SCIActionButtonSourceStories:
        case SCIActionButtonSourceInstants:
        case SCIActionButtonSourceDirect:
            return @[
                kSCIActionDownloadAllClipboard,
                kSCIActionDownloadAllLinks
            ];
        case SCIActionButtonSourceProfile:
            return @[];
    }
}

// Maps a single-item action identifier to its bulk "all" counterpart, or nil
// when the action has no bulk equivalent.
static NSString *SCIBulkAllIdentifierForBaseAction(NSString *identifier) {
    if ([identifier isEqualToString:kSCIActionDownloadLibrary]) return kSCIActionDownloadAllLibrary;
    if ([identifier isEqualToString:kSCIActionDownloadShare]) return kSCIActionDownloadAllShare;
    if ([identifier isEqualToString:kSCIActionDownloadGallery]) return kSCIActionDownloadAllGallery;
    if ([identifier isEqualToString:kSCIActionCopyMedia]) return kSCIActionDownloadAllClipboard;
    if ([identifier isEqualToString:kSCIActionCopyDownloadLink]) return kSCIActionDownloadAllLinks;
    return nil;
}

// Bulk destinations are derived from the user's single-item action config:
// every enabled single-item download/copy action contributes its bulk-all
// counterpart, in the same order. This keeps the "Bulk" menu in lockstep with
// the rest of the action button (no separate bulk store / editor).
static NSArray<NSString *> *SCIDerivedBulkActionsForSource(SCIActionButtonSource source, NSArray<NSString *> *supportedBulk) {
    if (supportedBulk.count == 0) return @[];
    SCIActionButtonConfiguration *configuration =
        [SCIActionButtonConfiguration configurationForSource:source
                                                  topicTitle:SCIActionButtonTopicTitleForSource(source)
                                            supportedActions:SCIActionButtonSupportedActionsForSource(source)
                                             defaultSections:SCIActionButtonDefaultSectionsForSource(source)];
    NSMutableOrderedSet<NSString *> *result = [NSMutableOrderedSet orderedSet];
    for (SCIActionMenuSection *section in [configuration visibleSections]) {
        for (NSString *identifier in section.actions) {
            NSString *bulk = SCIBulkAllIdentifierForBaseAction(identifier);
            if (bulk && [supportedBulk containsObject:bulk]) {
                [result addObject:bulk];
            }
        }
    }
    return result.array;
}

NSArray<NSString *> *SCIActionButtonConfiguredBulkDownloadActionsForSource(SCIActionButtonSource source) {
    return SCIDerivedBulkActionsForSource(source, SCIActionButtonBulkDownloadSupportedActionsForSource(source));
}

NSArray<NSString *> *SCIActionButtonConfiguredBulkCopyActionsForSource(SCIActionButtonSource source) {
    return SCIDerivedBulkActionsForSource(source, SCIActionButtonBulkCopySupportedActionsForSource(source));
}

NSArray<SCIActionMenuSection *> *SCIActionButtonDefaultSectionsForSource(SCIActionButtonSource source) {
    NSMutableArray<SCIActionMenuSection *> *sections = [NSMutableArray array];
    NSArray<NSString *> *downloadActions = @[
        kSCIActionDownloadLibrary,
        kSCIActionDownloadShare,
        kSCIActionDownloadGallery,
        kSCIActionTrimSave
    ];
    NSArray<NSString *> *audioActions = (source == SCIActionButtonSourceFeed ||
                                         source == SCIActionButtonSourceReels ||
                                         source == SCIActionButtonSourceStories)
        ? @[
            kSCIActionDownloadAudio,
            kSCIActionDownloadAudioShare,
            kSCIActionDownloadAudioGallery,
            kSCIActionPlayAudio,
            kSCIActionCopyAudioURL
        ]
        : @[];
    // Zoom: expand + view thumbnail (profile has no thumbnail).
    NSArray<NSString *> *zoomActions = (source == SCIActionButtonSourceProfile)
        ? @[kSCIActionExpand]
        : @[kSCIActionExpand, kSCIActionViewThumbnail];
    NSArray<NSString *> *copyActions = (source == SCIActionButtonSourceProfile)
            ? @[kSCIActionCopyDownloadLink, kSCIActionCopyMedia, kSCIActionProfileCopyInfo]
        : ((source == SCIActionButtonSourceFeed || source == SCIActionButtonSourceReels)
            ? @[kSCIActionCopyDownloadLink, kSCIActionCopyMedia, kSCIActionCopyCaption]
            : @[kSCIActionCopyDownloadLink, kSCIActionCopyMedia]);
    NSArray<NSString *> *moreActions;
    if (source == SCIActionButtonSourceFeed || source == SCIActionButtonSourceReels) {
        moreActions = @[kSCIActionRepost, kSCIActionOpenTopicSettings];
    } else if (source == SCIActionButtonSourceStories) {
        moreActions = @[kSCIActionStoryMentionsSheet, kSCIActionToggleStorySeenUserRule, kSCIActionOpenTopicSettings];
    } else if (source == SCIActionButtonSourceDirect) {
        moreActions = @[kSCIActionDeletedMessagesLog, kSCIActionOpenTopicSettings];
    } else if (source == SCIActionButtonSourceProfile) {
        moreActions = @[kSCIActionToggleProfileStorySeenUserRule, kSCIActionToggleProfileMessagesSeenUserRule, kSCIActionOpenTopicSettings];
    } else {
        moreActions = @[kSCIActionOpenTopicSettings];
    }

    if (moreActions.count > 0) {
        [sections addObject:[SCIActionMenuSection sectionWithIdentifier:@"more"
                                                                  title:@"More"
                                                               iconName:@"more"
                                                            collapsible:YES
                                                                actions:moreActions]];
    }
    if (audioActions.count > 0) {
        [sections addObject:[SCIActionMenuSection sectionWithIdentifier:@"audio"
                                                                  title:@"Audio"
                                                               iconName:@"audio_download"
                                                            collapsible:YES
                                                                actions:audioActions]];
    }
    if (zoomActions.count > 0) {
        [sections addObject:[SCIActionMenuSection sectionWithIdentifier:@"zoom"
                                                                  title:@"Zoom"
                                                               iconName:@"zoom"
                                                            collapsible:YES
                                                                actions:zoomActions]];
    }
    [sections addObject:[SCIActionMenuSection sectionWithIdentifier:@"copy"
                                                              title:@"Copy"
                                                           iconName:@"copy"
                                                        collapsible:YES
                                                            actions:copyActions]];
    [sections addObject:[SCIActionMenuSection sectionWithIdentifier:@"download"
                                                              title:@"Download"
                                                           iconName:@"download"
                                                        collapsible:YES
                                                            actions:downloadActions]];
    return sections;
}

@implementation SCIActionButtonConfiguration

+ (instancetype)configurationForSource:(SCIActionButtonSource)source
                            topicTitle:(NSString *)topicTitle
                      supportedActions:(NSArray<NSString *> *)supportedActions
                       defaultSections:(NSArray<SCIActionMenuSection *> *)defaultSections
{
    SCIActionButtonConfiguration *configuration = [[self alloc] init];
    configuration.source = source;
    configuration.topicTitle = topicTitle.length > 0 ? topicTitle : SCIActionButtonTopicTitleForSource(source);
    configuration.supportedActions = supportedActions.count > 0 ? supportedActions : SCIActionButtonSupportedActionsForSource(source);
    configuration.sections = [NSMutableArray array];
    configuration.disabledActions = [NSMutableArray array];
    configuration.unassignedActions = [NSMutableArray array];

    id storedValue = SCIPreferenceObjectForKey([configuration configDefaultsKey]);
    NSDictionary *stored = [storedValue isKindOfClass:[NSDictionary class]] ? storedValue : nil;
    if ([stored isKindOfClass:[NSDictionary class]]) {
        NSArray *storedSections = [stored[@"sections"] isKindOfClass:[NSArray class]] ? stored[@"sections"] : @[];
        for (NSDictionary *dictionary in storedSections) {
            SCIActionMenuSection *section = [SCIActionMenuSection sectionFromDictionary:dictionary];
            if (section) [configuration.sections addObject:section];
        }
        [configuration.disabledActions addObjectsFromArray:SCIFilteredActionArray(stored[@"disabled_actions"], configuration.supportedActions)];
        [configuration.unassignedActions addObjectsFromArray:SCIFilteredActionArray(stored[@"unassigned_actions"], configuration.supportedActions)];
    }

    if (configuration.sections.count == 0) {
        for (SCIActionMenuSection *section in (defaultSections.count > 0 ? defaultSections : SCIActionButtonDefaultSectionsForSource(source))) {
            [configuration.sections addObject:[section copy]];
        }
    }

    // Ensure a reorderable "Bulk" section exists on sources that support bulk
    // downloads. Its contents are derived from the single-item actions, so it has
    // no stored actions of its own; users reorder/rename it like any section.
    // Injected here (not only in the defaults) so existing persisted configs pick
    // it up too. Profile has no bulk support, so it is skipped there.
    if (SCIActionButtonBulkDownloadSupportedActionsForSource(source).count > 0 ||
        SCIActionButtonBulkCopySupportedActionsForSource(source).count > 0) {
        BOOL hasBulkSection = NO;
        for (SCIActionMenuSection *section in configuration.sections) {
            if ([section.identifier isEqualToString:@"bulk"]) { hasBulkSection = YES; break; }
        }
        if (!hasBulkSection) {
            SCIActionMenuSection *bulkSection = [SCIActionMenuSection sectionWithIdentifier:@"bulk"
                                                                                     title:@"Bulk"
                                                                                  iconName:@"carousel"
                                                                               collapsible:YES
                                                                                   actions:@[]];
            // Appended last so the Bulk section is the bottom-most when available.
            [configuration.sections addObject:bulkSection];
        }
    }

    [configuration normalize];
    return configuration;
}

- (NSString *)configDefaultsKey {
    return SCIPrefActionButtonConfigKey(SCIActionButtonTopicKeyForSource(self.source));
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableArray *sectionDictionaries = [NSMutableArray array];
    for (SCIActionMenuSection *section in self.sections) {
        [sectionDictionaries addObject:[section dictionaryRepresentation]];
    }
    return @{
        @"sections": sectionDictionaries,
        @"disabled_actions": [self.disabledActions copy] ?: @[],
        @"unassigned_actions": [self.unassignedActions copy] ?: @[]
    };
}

- (void)save {
    [self normalize];
    SCIPreferenceSetObject([self dictionaryRepresentation], [self configDefaultsKey]);
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIActionButtonConfigurationDidChangeNotification object:nil];
}

- (NSArray<NSString *> *)assignedActions {
    NSMutableOrderedSet<NSString *> *assigned = [NSMutableOrderedSet orderedSet];
    for (SCIActionMenuSection *section in self.sections) {
        for (NSString *identifier in section.actions) {
            if ([self.supportedActions containsObject:identifier]) {
                [assigned addObject:identifier];
            }
        }
    }
    return assigned.array;
}

- (void)normalize {
    NSArray<NSString *> *supported = self.supportedActions ?: @[];
    NSMutableOrderedSet<NSString *> *seen = [NSMutableOrderedSet orderedSet];
    NSMutableArray<SCIActionMenuSection *> *normalizedSections = [NSMutableArray array];

    for (SCIActionMenuSection *section in self.sections ?: @[]) {
        if (![section isKindOfClass:[SCIActionMenuSection class]]) continue;
        if (section.identifier.length == 0) section.identifier = NSUUID.UUID.UUIDString;
        if (section.title.length == 0) section.title = @"Section";
        if (section.iconName.length == 0) section.iconName = @"more";

        NSArray<NSString *> *filteredActions = SCIFilteredActionArray(section.actions, supported);
        NSMutableArray<NSString *> *uniqueActions = [NSMutableArray array];
        for (NSString *identifier in filteredActions) {
            if ([seen containsObject:identifier]) continue;
            [seen addObject:identifier];
            [uniqueActions addObject:identifier];
        }
        section.actions = uniqueActions;
        [normalizedSections addObject:section];
    }

    self.sections = normalizedSections;
    self.disabledActions = [SCIFilteredActionArray(self.disabledActions, supported) mutableCopy];

    NSMutableOrderedSet<NSString *> *unassigned = [NSMutableOrderedSet orderedSetWithArray:SCIFilteredActionArray(self.unassignedActions, supported)];
    for (NSString *identifier in supported) {
        if (![seen containsObject:identifier]) {
            [unassigned addObject:identifier];
        }
    }
    self.unassignedActions = unassigned.array.mutableCopy;
}

- (nullable SCIActionMenuSection *)sectionWithIdentifier:(NSString *)identifier {
    for (SCIActionMenuSection *section in self.sections) {
        if ([section.identifier isEqualToString:identifier]) return section;
    }
    return nil;
}

- (NSArray<SCIActionMenuSection *> *)visibleSections {
    NSMutableArray<SCIActionMenuSection *> *visible = [NSMutableArray array];
    for (SCIActionMenuSection *section in self.sections) {
        NSMutableArray<NSString *> *actions = [NSMutableArray array];
        for (NSString *identifier in section.actions) {
            if (![self.disabledActions containsObject:identifier] && ![self.unassignedActions containsObject:identifier]) {
                [actions addObject:identifier];
            }
        }
        if (actions.count == 0) continue;
        [visible addObject:[SCIActionMenuSection sectionWithIdentifier:section.identifier
                                                                 title:section.title
                                                              iconName:section.iconName
                                                           collapsible:section.collapsible
                                                               actions:actions]];
    }
    return visible;
}

- (nullable NSString *)sectionIdentifierForAction:(NSString *)identifier {
    for (SCIActionMenuSection *section in self.sections) {
        if ([section.actions containsObject:identifier]) {
            return section.identifier;
        }
    }
    return nil;
}

- (void)setAction:(NSString *)identifier assignedToSectionIdentifier:(NSString *)sectionIdentifier {
    if (![self.supportedActions containsObject:identifier]) return;

    for (SCIActionMenuSection *section in self.sections) {
        [section.actions removeObject:identifier];
    }
    [self.unassignedActions removeObject:identifier];

    if (sectionIdentifier.length > 0) {
        SCIActionMenuSection *section = [self sectionWithIdentifier:sectionIdentifier];
        if (section && ![section.actions containsObject:identifier]) {
            [section.actions addObject:identifier];
        }
    } else {
        if (![self.unassignedActions containsObject:identifier]) {
            [self.unassignedActions addObject:identifier];
        }
    }
    [self normalize];
}

- (void)moveSectionFromIndex:(NSInteger)sourceIndex toIndex:(NSInteger)destinationIndex {
    if (sourceIndex < 0 || destinationIndex < 0 || sourceIndex >= self.sections.count || destinationIndex >= self.sections.count) return;
    SCIActionMenuSection *section = self.sections[sourceIndex];
    [self.sections removeObjectAtIndex:sourceIndex];
    [self.sections insertObject:section atIndex:destinationIndex];
}

- (void)moveActionInSectionIdentifier:(NSString *)sectionIdentifier fromIndex:(NSInteger)sourceIndex toIndex:(NSInteger)destinationIndex {
    SCIActionMenuSection *section = [self sectionWithIdentifier:sectionIdentifier];
    if (!section) return;
    if (sourceIndex < 0 || destinationIndex < 0 || sourceIndex >= section.actions.count || destinationIndex >= section.actions.count) return;
    NSString *identifier = section.actions[sourceIndex];
    [section.actions removeObjectAtIndex:sourceIndex];
    [section.actions insertObject:identifier atIndex:destinationIndex];
}

@end

NSArray<NSString *> *SCIProfileCopyInfoSupportedActions(void) {
    return @[
        kSCIActionProfileCopyID,
        kSCIActionProfileCopyUsername,
        kSCIActionProfileCopyName,
        kSCIActionProfileCopyBio,
        kSCIActionProfileCopyLink
    ];
}

NSArray<NSString *> *SCIProfileConfiguredCopyInfoActions(void) {
    NSArray<NSString *> *supported = SCIProfileCopyInfoSupportedActions();
    id storedValue = SCIPreferenceObjectForKey(@"profile_action_btn_copy_info_submenu_actions");
    NSArray *stored = [storedValue isKindOfClass:[NSArray class]] ? storedValue : nil;
    NSArray<NSString *> *filtered = SCIFilteredUniqueActionArray(stored, supported);
    return filtered.count > 0 ? filtered : supported;
}

void SCIProfileSetConfiguredCopyInfoActions(NSArray<NSString *> *actions) {
    SCIPreferenceSetObject(SCIFilteredUniqueActionArray(actions, SCIProfileCopyInfoSupportedActions()),
                           @"profile_action_btn_copy_info_submenu_actions");
    [[NSNotificationCenter defaultCenter] postNotificationName:SCIActionButtonConfigurationDidChangeNotification object:nil];
}
