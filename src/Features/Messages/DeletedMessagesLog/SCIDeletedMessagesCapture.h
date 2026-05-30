// In-memory capture pipeline for the deleted-messages log.
//
// KeepDeletedMessages.x already owns the single chokepoint hook on
// `IGDirectCacheUpdatesApplicator._applyThreadUpdates:completion:userAccess:`
// and is the only place we can guarantee ordering relative to the
// remove-keys neutering. Rather than fight install order, that hook calls
// these two C functions directly:
//
//   • `sciDMCaptureNoteInsert(message)` on every insert/replace, so we have a
//     full snapshot of the body BEFORE any unsend can happen.
//   • `sciDMCaptureNoteRemoveSids(sids, ownerPk, threadId)` on every reason==0
//     remove, so we know which captured snapshots became deleted records.
//
// All persistence + media downloading happens here, gated by
// `msgs_deleted_log` (read fresh — never cached).

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

void sciDMCaptureNoteInsert(id _Nullable message);

// `keys` are the IGDirectMessageKey objects from the unsend delta. The
// capture side extracts sids itself, falls back to a sync lookup against
// `applicator.cache messageForKey:` for any sid that's no longer in the
// in-memory weak cache (scrolled-out chats), and finally writes a
// sender-only placeholder if the lookup fails.
void sciDMCaptureNoteRemoveKeys(NSArray * _Nullable keys,
                                 id _Nullable applicator,
                                 NSString * _Nullable ownerPk,
                                 NSString * _Nullable threadId);

NSArray<NSDictionary *> *sciDMCapturePreviewMetadataForKeys(NSArray * _Nullable keys,
                                                            id _Nullable applicator,
                                                            NSString * _Nullable ownerPk,
                                                            NSString * _Nullable threadId);

// Reaction unsend: someone removed a reaction they had placed on a message.
// `reaction` is an IGDirectMessageReaction; `reactorPk` is the user who removed
// it; `targetMessage` (optional) is the message the reaction was on, used to
// build a short preview. Persists a reaction record gated by
// `msgs_deleted_log_reactions`. Returns the saved record's sender display info
// as a dict for the toast (keys: senderPk/senderUsername/senderFullName/emoji),
// or nil when nothing was stored.
NSDictionary * _Nullable sciDMCaptureNoteReactionUnsend(id _Nullable reaction,
                                                        NSString * _Nullable reactorPk,
                                                        id _Nullable targetMessage,
                                                        NSString * _Nullable targetMessageId,
                                                        id _Nullable applicator,
                                                        NSString * _Nullable ownerPk,
                                                        NSString * _Nullable threadId);

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
