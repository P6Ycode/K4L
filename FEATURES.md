# Sparkle Features

A complete catalog of Sparkle's options, grouped to mirror the in-app settings.

Most toggles take effect immediately. Options that rebuild Instagram UI are
marked **(restart)** and prompt for a relaunch when changed.

---

## General

### Behavior
- **Copy Text**: Long-press text fields across the app to copy them.
- **No Recent Searches**: Stops search bars from saving recent queries.
- **Copy Links Without Tracking**: Strips the username path and tracking parameters from copied links.
- **Hold Send to Copy Link**: Long-press the send/share button to copy the post link.

### Sharing
- **Hide Create Group Button**: Hides the create group button on the Instagram send/share sheet.
- **Confirm Create Group**: Confirmation alert before creating a group on Instagram send/share sheet.
- **Confirm Send**: Confirmation alert before sending a post.

### Recommendations
- **Ads**: Per-surface ad hiding: Feed, Stories, Reels, Explore, plus Reels shopping CTA.
- **Meta AI**: Hide Meta AI in Direct, Explore & Search, Comments, Creation Tools, and global AI chrome. Hiding it in Explore & Search also restores the plain search glyph in the search bar (replacing the gen-AI search icon).
- **Suggested Users**: Hide suggested-user surfaces: Feed, Reels, Direct, Search, Profile, Activity, follow lists, and subscriptions.

### Comments
- **Swipe to Close Comments** + **Swipe Direction**: Adds a horizontal swipe-to-dismiss gesture to comment sheets.
- **Comment Menu Actions**: Adds opt-in comment text copying, plus Photos/Share/Gallery/clipboard actions and link copying for both GIF and photo comments (GIF gets a Giphy link, photo gets a direct image download link). Gallery saves use a dedicated `Comments` source.
- **Confirm Comment Like**.
- **Hide Comment Shopping**: Removes commerce carousels in comment threads.
- **Hide Gifts Button**: Removes the Gifts shortcut from the comment composer and lets the input use the freed space.
- **Upload Photos from Gallery**: Long-press the composer's photo button to attach an image from your Sparkle Gallery (a normal tap still opens Instagram's photo picker).
- Comment options apply everywhere comments appear (feed, reels, etc.).

### Storage
- **Clear Cache**: Clears temporary caches now (shows current cache size). The confirmation notification reports how much was freed.
- **Auto Clear Cache**: Automatic clearing checked whenever Instagram becomes active: `Never`, `Always`, `Daily`, `Weekly`, `Monthly`.

### App
- **App Icon**: Choose an alternate icon from those exposed by the installed Instagram bundle.
- **Open Menu Icon**: Choose the glyph shown on every action button whose default tap action is **Open Menu**. A single global choice (not per-surface), picked from the same unified icon picker used everywhere else. Defaults to the Sparkle action glyph.
- **Disable App Haptics**: Turns off in-app haptics and vibrations.

### Accounts
- **Per-Account Settings**:
  - Gives each logged-in Instagram account its own Sparkle preferences. A newly seen account inherits your current settings until you change something. Switching accounts in-app applies the right set immediately. **(restart)**
  - Some settings stay shared accross accounts. A **How It Works** button lists the shared features in-app.

---

## Interface

### Notifications
Per-feature control of the Sparkle notification pill and its haptics. See **Notifications** below.

### Tabs
- **Launch Tab**: Opens Instagram on Feed, Explore, Reels, Messages, Profile, or Instagram's default tab. **(restart)**
- **Tab Icon Order**: `Default`, `Standard` (Home, Reels, Messages, Explore, Profile), `Classic` (Messages in the top-right), `Alternate` (Home/Reels swapped).
- **Swipe Between Tabs**: `Default`, `Enabled`, or `Disabled`.
- **Hide Tabs**:
  - Individually hide the Feed, Explore, Messages, Reels, Create, and Profile tabs. **(restart)**
  - Settings access is safeguarded: if Quick Settings Access is on but the Home tab is hidden (or taken by the Gallery shortcut), the long-press to open Sparkle Settings automatically moves to another visible tab, so you can't hide your way out of reaching Settings.

### Explore & Search
- **Hide Explore Posts Grid**: Hides the suggested-post grid on Explore.
- **Hide Trending Searches**: Hides trending searches under the Explore search bar.
- **Open Clipboard Link**: Long-press the Explore tab to open an Instagram URL from the clipboard.

### Capture
- **Hide UI on Capture**: Redacts Sparkle overlay buttons (action button, seen/mentions buttons, etc.) from screenshots, screen recordings, and mirroring.

### Liquid Glass *(iOS 26+)*
- **Liquid Glass**: Force-enables Instagram's native Liquid Glass UI for accounts/devices that don't already have it. **(restart)** Only ever forces it *on*; turning it off never suppresses Liquid Glass that Instagram already renders natively (server-rollout accounts) or that Sparkle's own screens (Gallery, Settings, etc.) pick up automatically from iOS 26: so Sparkle's UI never looks inconsistent with Instagram's regardless of this switch.
- **Tab Bar State**: Controls how the floating Liquid Glass tab bar behaves while scrolling.

---

## Feed

### Action Button
- **Feed Action Button**: Adds an action button to feed posts.
- **Default Tap Action** + **Configure Actions**: Single tap runs the chosen action; long-press opens the full, user-editable menu (sections).
- **Bulk**: On posts that support it (carousels with multiple downloadable items) the menu shows a **Bulk · N** section (N = carousel item count) with **Download All**, **Copy All**, and **Select Media**. Bulk is an ordinary section in **Configure Actions**: drag to reorder it, rename it, change its icon, or toggle collapsible, just like any other section. Its destinations are derived from your single-item action config (enabling/disabling or reordering a Download/Copy action carries straight into Bulk), so there is no separate bulk menu to configure. The section is resolved when the menu opens, so it appears reliably even on the first item of a story/reel. **Select Media** opens a grid picker to hand-pick a subset (tap to toggle, with a Select All/None control), then runs the chosen destination on just those items. Available from the action button and the full-screen media preview toolbar.
- **Single-element submenus inline**: Any section or submenu (built-in or custom: Download All, Copy All, Copy Info, etc.) that resolves to a single action is shown inline instead of as a one-item collapsible submenu.
- **Section icons**: Picking a section or submenu icon (including Bulk) opens the unified icon picker: a single searchable grid of the installed Instagram bundle's icons. There is no separate "shortcuts" row: your current icon is resolved and highlighted directly in the list. The same picker powers the App Icon and Open Menu Icon choosers.

### Layout
- **Main Feed**: `For You` or `Following`. Following mode forces the chronological feed, keeps pagination and cold starts on that source, and removes the For You picker entry. **(restart)**
- **Hide Stories Tray**, **Hide Entire Feed**, **Hide Suggested Posts**, **Hide Suggested Accounts**, **Hide Suggested Reels**, **Hide Suggested Threads**.
- **Hide Repost Button**: Removes the repost button from posts. **(restart)**

### Metrics
- **Hide Like / Comment / Repost / Reshare Count** under feed posts.

### Media
- **Long Press to Expand**: Long-press feed media to open the expanded viewer.
- **Disable Video Autoplay**: Prevents feed videos from auto-playing. **(restart)**
- **Start Expanded Videos Muted**: Expanded videos open muted.

### Refresh
- **Disable Home Tab Refresh**: No refresh when re-tapping the Home tab.
- **Disable Background Refresh**: Prevents background feed refresh.

### Confirmation
- **Confirm Like**, **Confirm Double Tap**, **Confirm Repost**, **Confirm Posting Comment**.

---

## Stories

### Action Button
- **Stories Action Button**, **Default Tap Action**, **Configure Actions**: As with feed; placed above the bottom story bar.

### Seen Receipts
- **Manually Mark Seen**: Suppresses automatic seen receipts and adds an eye button to mark a story seen.
- **Included / Excluded Users**: Two separate per-account lists, selected by Manually Mark Seen: when off, the *Included Users* list (only those users get the eye button / require manual seen); when on, the *Excluded Users* list (those users keep normal automatic seen). Each list is independent and stored per account. Manageable from the eye button, long-press, or the list.
- **Mark Seen on Like**, **Mark Seen on Reply**: disabled unless Manually Mark Seen is on.

### Story Navigation
- **Stop Auto Advance**: Prevents auto-advancing to the next story.
- **Advance on Eye Button / Story Like / Story Reply**: Advances after the respective mark-seen action.

### Confirmations
- **Confirm Like**, **Confirm Quick Reaction**, **Confirm Sticker Interaction**.

### Other
- **Hide Story Midcards** Removes the "Join a trending" / "Add Yours" promo cards from the stories tray. 
- **Show Story Mentions**: Adds a mentions button listing mentioned users.
- **Show Poll Vote Counts**: Shows vote counts next to poll options.
- **Use Detailed Color Picker**: Long-press the eyedropper for finer text-color control.

---

## Reels

### Action Button
- **Reels Action Button**, **Default Tap Action**, **Configure Actions**.

### Behavior
- **Tap Controls**: `Default`, `Pause/Play`, or `Mute/Unmute`.
- **Show Progress Scrubber**: Always shows the progress bar.
- **Disable Auto-Unmuting Reels**: Prevents unmute on volume/silent-switch changes. **(restart)**
- **Disable Reels Tab Refresh**: No refresh when re-tapping the Reels tab.

### Limits
- **Disable Scrolling Reels**: Blocks scrolling to the next reel. **(restart)**
- **Prevent Doom Scrolling** + **Doom Scrolling Limit**: Caps the number of reels that load (1–100).

### Layout
- **Hide Reels Header**, **Hide Repost Button** **(restart)**, **Hide Suggested Accounts**.

### Metrics
- **Hide Like / Comment / Repost / Reshare / Save Count**.

### Confirmation
- **Confirm Like**, **Confirm Double Tap**, **Confirm Reel Refresh**, **Confirm Repost**.

---

## Messages

### Action Button
- **Messages Action Button**, **Default Tap Action**, **Configure Actions**: For visual messages.

### Messaging
- **Manually Mark Seen**: adds an eye button to mark chats seen.
- **Mark Seen on Message Send / Reply / Reaction**: auto-seen triggers; disabled unless Manually Mark Seen is on.
- **Included / Excluded Chats**: two separate per-account lists (Included when off, Excluded when on), same model as stories.

### Deleted Messages
- **Keep Deleted Messages**: Preserves remotely-unsent messages in the chat, marked with an undo-circle indicator.
- **Log Deleted Messages**: Records normalized message snapshots before removal, then reconciles unsends after cold launches or later cache refreshes.
- **Log Removed Reactions**: Records removed reactions.
- **Respect Seen Chat List**: Skips log capture, ephemeral-media staging, and unsent notifications for chats in your manual-seen include/exclude list. Keep Deleted Messages preservation remains independent.
- **Deleted Messages Log**: Browsable log of preserved messages. 1:1 chats are grouped by sender; group chats collapse into a single entry titled with the real group name (resolved from IG's thread metadata: the custom name, or participant names for untitled groups). Group rows show the group's custom photo when set (else a group glyph), and group detail labels each unsent message with its sender.
- **Media Recovery Cache**: Pre-caches view-once/view-twice photos and videos, GIFs, and stickers until manually cleared from the Deleted Messages storage page. Media for messages that were never unsent is excluded from exports; clearing it retains lightweight metadata for best-effort fallback downloads.
- **Refresh Profile Pictures**: Avatars self-heal: expired CDN URLs are silently re-resolved from Instagram, so reopening the log restores missing pictures. The log and sender-detail ⋯ menus force-refresh them all, and individual placeholders can be tapped to retry. Profile pictures are a shared cache managed under **Data & Settings › Storage**.
- **Confirm Inbox Refresh**: Confirmation before pull-to-refresh in the inbox, which would reload threads and drop preserved messages.

### Interface
- **Hide Typing Status**: Suppresses your typing indicator.
- **Hide Reels Blend Button**, **Hide Audio Call Button**, **Hide Video Call Button**, **No Suggested Chats**. Call-button visibility changes apply after reopening the DM thread.

### Visual Messages
- **Manually Mark Seen** + **Advance After Manual Seen**.
- **Stop Auto Advance**: Keeps the current visual message on screen instead of auto-advancing when it ends.
- **Disable View-Once Limitations**: Treats view-once messages as normal visual messages.
- **Disable Screenshot Detection**: Allows screen capture of visual messages.

### Vanish Mode
- **Disable Swipe-Up Gesture**: Disables the gesture that enables vanish mode.
- **Disable Screenshot Detection**: Allows screen capture while vanish mode is active.

### Notes
- **Hide Notes Tray**, **Hide Friends Map**.
- **Download Notes Audio**: Long-press a note in the tray to add a "Save audio" row to its menu (Save Audio to Files, Share Audio, Save Audio to Gallery, Play Audio, or Copy Audio Download URL). Only appears on notes that carry audio. **(restart)**
- **Copy Note Text**: Long-press a note to add a "Copy text" row to its menu. Only appears on text notes. **(restart)**
- _Note actions are not supported on IG 410.1.0 (yet)._

### Audio
- **Download Audio Messages**: Adds audio actions to voice/audio message views. **(restart)**
- **Upload Audio Messages**: Converts a selected audio/video clip to M4A and sends it as a voice message. **(restart)**
- **Trim Before Sending**: When uploading an audio message, offer to trim the audio in the trim editor before it's sent (Send now, or Trim & Send).

### Media
- **Send Photo from Gallery**: Adds a "Send Photo" option to the composer plus (+) menu that sends a photo from the Sparkle Gallery into the chat. **(restart)**

### Confirmation
- **Confirm Audio Call**, **Confirm Video Call**, **Confirm Double Tap**, **Confirm Reactions**, **Confirm Voice Messages**, **Confirm Follow Requests**, **Confirm Vanish Mode**, **Confirm Changing Theme**.

---

## Instants

### Action Button
- **Instants Action Button**, **Default Tap Action**, **Configure Actions**: Actions resolve the currently visible Instant, preserve each Instant's author in bulk jobs, support photo/video media, and can operate on multiple pending Instants.

### Privacy
- **Allow Screenshots**: Bypasses screenshot/screen-recording detection in the Instants viewer.

### Creation
- **Disable Instants Creation**: Hard-blocks the Instant shutter (photo and video); the shutter is darkened and capture is blocked, with an optional notification + haptic. Received Instants still work.
- **Skip Camera After Instants**: Skips the camera page Instagram opens after viewing the last Instant.
- **Disable Camera Control**: Stops the hardware Camera Control button (iPhone 16/17) from taking an Instant. Only available on devices that have Camera Control.
- **Upload from Gallery**: Adds a gallery button to the Instants camera to upload from Photos, Files, or the Sparkle Gallery.

### Confirmation
- **Confirm Instant Capture**: Freezes the preview on the exact frame you captured and asks before sending it, so the sent frame is what you saw (cancel resumes the live camera). **Currently unavailable.**
- **Confirm Instant Reaction**: Asks before an Instant reaction is sent.

---

## Profile

### Action Button
- **Profile Action Button** + **Default Tap Action**: `None`, `Copy Info`, `View Picture`, `Share Picture`, `Save to Gallery`, or `Profile Settings`. Sits in the profile nav bar just left of Instagram's own buttons (More/Follow/notify), tracking them as they morph and collapse on scroll; on your own profile it is omitted. On iOS 26 it grows a matching Liquid Glass bubble that fades in with scroll, and long usernames truncate so they never run under it.
- **Copy Info Default**: What Copy Info copies: `ID`, `Username`, `Name`, `Bio`, or `Profile Link`.

### Profile Picture
- **Long Press to Expand**: Long-press a profile picture to open it expanded.

### Indicators
- **Show Following Indicator**: Shows whether the profile follows you.
- **Hide Notes Bubble**: Removes the notes thought-bubble over the profile picture.
- **Hide Threads Button**: Removes the Threads switch button from the profile header.

### Confirmation
- **Confirm Follow**, **Confirm Unfollow**.

---

## Gallery

Sparkle's built-in media library: a private, on-device gallery with folders,
metadata, search, and an optional passcode/biometric lock. Media saved through
the action buttons or media preview lands here. Gallery data, deleted-message
logs, and Profile Analyzer data live locally under `Documents/Sparkle/`.

### Access
- **Open Gallery**: Opens the Gallery from settings.
- **Quick Gallery Access**: Choose a tab whose long-press opens the Gallery (or `None`).

### Browsing
- **Show Favorites at Top**: Pins favorites within the current sort/folder.
- **Grid density**: Pinch the grid to switch between 2 / 3 / 5 columns (persisted).
- **Folder chips**: Subfolders appear as a horizontally-scrolling chip strip above the media.
- **Source & username overlays**: Grid items can show the source-type icon and `@username` (toggleable; username shows at lower densities). Video/audio items show a duration label.
- **Grid / list view** and **sort / filter** controls in the bottom toolbar.
- **Item actions**: Each item's menu can **Open Story / Reel / Post** (the label and link match the saved source: stories open `instagram.com/stories/...`; posts/reels open their canonical `instagram.com/p/...` or `instagram.com/reel/...` permalink when available, with the authenticated media deep link kept as a fallback) and **Open Profile**, plus favorite, rename, move, share, **Trim** (videos and audio), **Edit** (photos: see Editing), and delete.
- **Automatic Live Text**: Static image previews enable native text selection on supported iOS versions. Animated GIF/WebP previews and iOS 15 skip analysis.

### Trimming
- **Trim editor**: Trim a video down to a clip, a single still frame, or **audio only**, with a filmstrip scrubber, draggable in/out handles, and mode chips. Reachable from a Gallery video or audio's **Trim** menu action, the **media preview** bottom toolbar (videos and audio), and the **Trim & Save** action button (see below). Picking **Audio Only** on a video switches the editor into the audio trimmer (waveform + artwork) and exports the selected range as an M4A, discarding the picture: if you don't touch the scrubber it saves the whole audio; the chip is hidden for silent videos. Trimming an audio file (or expanded audio) opens the same waveform editor directly. Frame-accurate re-encode via the FFmpeg pipeline honoring your **Download Encoding** settings (codec/CRF/bitrate/preset/resolution; falls back to AVFoundation); single-frame extraction is exported as HEIC/JPEG, turning a "photo + song" video into a real photo; audio exports as native AAC. Rendering runs in the background behind a progress pill: the app stays usable.
- **Ask to Replace Original**: When trimming or editing a Gallery item, ask whether to replace the original in place or save a copy. Off always saves a copy and keeps the original.

### Editing
- **Photo editor**: Crop, pan/zoom, rotate (±90°), and horizontal flip for photos, with a selectable crop aspect. Reachable from: the **media preview** bottom toolbar's **Edit** button (Gallery photos *and* any expanded Instagram photo); a Gallery photo's **Edit** menu action; and the **Edit & Save** action button (see below). For a Gallery photo, saving honors **Ask to Replace Original** (replace in place or save a copy); for an expanded Instagram photo it offers a Done menu of destinations (**Photos / Gallery / Share / Copy**). The same editor powers Instants "Upload from Gallery" positioning in a locked-square mode. *(Note: editing an animated GIF flattens it to a still image.)*
- **Trim & Save (action button)**: An opt-in, video-only action you can add to any action-button menu via the customizer (works on feed-inline reels too). It sources the video at your configured **download video quality** (progressive "ready-to-play" or merged DASH; prompts when set to "always ask"), opens the trim editor, then offers a Done menu of destinations (**Photos / Gallery / Share / Copy**; when the output is audio, **Save to Files** replaces Photos). DASH-quality trims download the streams and merge + cut in one pass, encoding only the selected window.
- **Edit & Save (action button)**: The photo counterpart to Trim & Save: an opt-in, image-only action for any action-button menu. It fetches the photo, opens the editor, then offers a Done menu of destinations (**Photos / Gallery / Share / Copy**).

### Gallery Settings
- **Pinch to Zoom**: Enables grid density pinching.
- **Show Source & Username**: Toggles the grid overlays above.
- **This Account Only**: Scopes the Gallery to media saved while logged into the current account (plus older unassigned files); enabling it offers to claim existing unassigned files for the current account. Each saved file is tagged with the account that saved it; reassign a file to another logged-in account from its **Edit Details → Account** row (e.g. to stash media into a different account's Gallery). Non-destructive: turn it off to see everything.
- **Hidden Sources**: Hides selected sources, from Gallery browsing and Gallery picker sheets without deleting files or excluding them from maintenance and duplicate tracking.
- **Enable Passcode Lock** + **Change Passcode**: 4–6 digit passcode with Face ID / Touch ID unlock. Hashes are stored in the keychain (PBKDF2-HMAC-SHA256). Enforced globally when opening the Gallery itself and all gallery picker sheets (e.g., when uploading media in Direct Messages or Instants).
- **Storage**: Total / image / video / audio counts and total size.
- **Delete Files**: Bulk-delete tooling: by everything, by type (images/videos/thumbnails), by source (feed/stories/reels/DMs/profile pictures), or by user.

---

## Downloads

Tapping **Downloads** opens the download manager directly. A gear button in the
top bar opens **Downloads Settings** (below). Settings remain searchable from
the main settings search.

- **Downloads**: Action-based download manager with chip filters for All, Active, Queued, Failed, and Recent. Each row represents the user action, not an internal transport task. Multi-item actions expand inline, failed items can be retried individually, Gallery and Photos saves open their matching destination, and single-file results preview locally when applicable. Supports cancellation, destructive-action confirmations, clearing history without deleting saved media, and best-effort retry for reconstructable actions. With **Per-Account Settings** on, the history is scoped to the current account (each download keeps the account that started it); the limit and max-concurrent settings stay global.
- **Global Queue Pill**: Parallel and queued download work shares one aggregate Downloads pill instead of spawning one pill per item or separate queue-finished toasts.

### Behavior
- **Detect Duplicate Downloads**: Skips media already saved: Gallery checks are exact by persistent media identity; Photos checks cover saves Sparkle recorded while tracking is enabled. Existing Photos-library items cannot be discovered retroactively.
- **Parallel Downloads**: Limits concurrent download work from 1–4 (default 2) across direct saves, carousel items, conversions, and DASH merge pipelines.
- **History Limit**: Caps saved download actions at a configurable history limit (default 300 entries).

### Quality
- **Enhanced Media Resolution**: Requests higher-resolution media for downloads.
- **Default Photo Quality**: `High` / `Low` (or always ask).
- **Default Video Quality**: Save/share quality. `High` merges DASH video + audio; `Default` uses ready-to-play files; `Always Ask` prompts each time. **Requires FFmpegKit** for the merge/quality options.
- **Encoding Settings**: Advanced codec / preset / bitrate / CRF / resolution / audio overrides for the merge step (requires FFmpegKit).
- **View Encoding Logs**: Inspect and share the FFmpeg loader/merge logs.

### Audio
- **Audio Downloads**: Adds audio actions (save/share/copy download URL) to supported media.
- **Audio Page Button**: Adds an action button to the music/audio page.
- **Audio Page Default Action**: Default tap action for the audio page button: `Save Audio to Files`, `Share Audio`, `Save Audio to Gallery`, `Play Audio`, `Copy Audio Download URL`, or `None`.

---

## Profile Analyzer

Fetches your account's full followers and following lists through Instagram's
private API, stores a local snapshot, and surfaces relationship insights. Runs
in the background: start an analysis and keep using the app; a notification pill
reports progress and completion. Data is stored locally per account and never
uploaded. Accounts with more than 13,000 total connections (followers + following)
can't be analyzed because a single scan would hit Instagram's rate limits.

### Analyzer
- **Open Profile Analyzer**: Dashboard with your profile header (avatar, posts/followers/following), a Run/Re-run Analysis button, and the insight categories below.
- **Insights** (always available after a scan):
  - **Mutual Followers**: accounts you follow that also follow you.
  - **Not Following You Back**: accounts you follow that don't follow you.
  - **You Don't Follow Back**: accounts that follow you that you don't follow.
- **Changes** (accumulate across scans: re-running never wipes the history):
  - **New Followers** / **Lost Followers**: everyone gained or lost since tracking began.
  - **You Started Following** / **You Unfollowed**: your following changes over time.
  - **Profile Updates**: username, name, or profile-picture changes for tracked accounts.
  - Each category badges the number of changes you haven't looked at yet; inside, unseen changes are grouped under **Latest** above previously-seen ones under **Previous**. Opening a category clears its badge.
- Each list supports search, sorting (A–Z / Z–A / default), tapping a row to open the profile, and inline **Follow / Unfollow** with live follow-state resolution.

### Tracking
- **Track Visited Profiles**: Records the profiles you open so you can review who you visit most (with first/last-seen and a visit count). Most-recent, most-visited, and alphabetical sorts; swipe to remove an entry. Stored locally.

### Maintenance
- **Reset Profile Analyzer Data**: Deletes all stored snapshots, the change history, and visited-profile history.
- **Refresh Profile Pictures**: Avatars self-heal: when a stored CDN URL has expired, Sparkle silently re-resolves a fresh one from Instagram, so simply reopening a list restores missing pictures. A list's **More** menu force-refreshes them all, and individual placeholders can be tapped to retry. Profile pictures are a shared cache managed under **Data & Settings › Storage**.

### Notifications
- **Profile Analyzer Complete**: Pill + haptic when an analysis finishes (toggleable under Notifications).

---

## Notifications

The Sparkle notification pill is configurable.

### Appearance
- **Glow**: Glow effect around notifications.
- **Liquid Glass**: Renders the notification pill with iOS 26 Liquid Glass (adaptive text/icons). Requires iOS 26; falls back to the standard material on iOS 18 and lower.
- **Download Progress**: Subtitle style for download-progress pills.
- **Duration**: Auto-dismiss delay (0.5–5.0s).

### Preview
- **Test Notification**: Cycles success / error / info previews.

### Per-feature toggles
Every notification category has an independent **visibility** toggle and a
matching **haptic** toggle (under Haptics), covering downloads, copies,
story/message seen actions, gallery actions, settings export/import, cache
clearing, and more.

---

## Tools

### FLEX
- **Open FLEX Now**, **Three-finger Hold**, **Open on App Launch**, **Open on App Focus**. Requires `libFLEX.dylib` to be bundled (build the ipa with `--flex` flag or install `libFLEX.dylib` if jailbroken).

### Tweak
- **Quick Settings Access**: Long-press the Home tab to open Sparkle Settings. **(restart)** If the Home tab is hidden or claimed by the Gallery shortcut, the long-press automatically falls back to another visible tab so Settings is always reachable.
- **Show Settings on App Launch**.
- **Disable All Settings**: Master kill switch; only Settings access remains. **(restart)**
- **Reset Onboarding Completion State**.
- **Reset Safe Startup Mode**: Clears Sparkle's failed-launch counters and re-enables feature hooks after the launch failsafe kicked in.

### Settings Lock
- **Enable Settings Passcode Lock** + **Change Settings Passcode**: Uses an independent keychain-backed passcode and Face ID / Touch ID unlock. Protects full Settings and topic sheets opened from action buttons; Settings remains unlocked until its modal is dismissed.

### Instagram
- **Hide TestFlight Popup**: Suppresses the Instagram Beta update popup. **(restart)**
- **Fix Duplicate Notifications**: Drops the duplicate in-app banner sideloaded Instagram posts while the notification extension is already delivering the same push. Only acts while the app is foregrounded.
- **Disable Safe Mode**: Prevents Instagram from resetting settings after repeated crashes (use with care).

---

## Data & Settings

### Storage
- **Storage Usage**: Total on-device space used by all Sparkle data, with a per-feature breakdown (Gallery, Downloads, Deleted Messages, Profile Analyzer, and the shared Profile Pictures cache). Includes **Clear Cached Profile Pictures**, which frees the app-wide avatar cache (pictures re-download as needed). Instagram's own cache is not included.

### Backup & Transfer
- **Export / Import**: Export/import any combination of **Settings**, **Gallery** media + metadata, **Deleted Messages**, and **Profile Analyzer** data to a single `.zip` file. Media Recovery Cache assets are intentionally excluded until they belong to an unsent message. Imports also accept backups re-compressed by Files, iCloud, or desktop tools.

### Reset
- **Reset All Settings**: Restore every preference to its default value.
