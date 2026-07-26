# K4L Implementation Ledger Index

Phase II Step 5 normalizes the 90 recovered mechanics into repository-owned clean-room contracts. The authoritative private source remains `Hush_Mechanics_Ledger.tsv`, pinned in `docs/EVIDENCE_MANIFEST.md`.

The ledger is sharded only for reviewability. Together the six TSV files form one implementation gate.

## Shards

| File | Families | Rows | SHA-256 of normalized TSV |
|---|---|---:|---|
| `01_package_injection_preferences.tsv` | Package, Injection, Preferences | 17 | `94e8a1ecb69c6d54559ea746954b1f76f23e00bd2a292cf44f86b8c0855d037b` |
| `02_springboard_screenshot_replaykit.tsv` | SpringBoard, Screenshot, ReplayKit | 17 | `04490b2ec45e7b6f520056da2fc2f28300dff9cac9af657488514e1206649e4c` |
| `03_camera_audio_power_location.tsv` | Camera, Audio, Power, Location | 22 | `7af3b2e207fffeee1b3bb8ec7f46178c6eed2e54abbccfe92434b5f9e23b16c0` |
| `04_media_and_public_send.tsv` | Media, Snapchat public | 11 | `ce8acc78a3f88540cff01d903010fdbd0b730bf855f11c13b325222fbd8d1ef4` |
| `05_snapchat_private_mechanics.tsv` | Snapchat database, Valdi, private APIs, compatibility | 18 | `140ea32e7618983a681e7c079435541e251a2294332367d05d44eade935a5d0a` |
| `06_maintenance_ipc_reverse_limits.tsv` | Maintenance, IPC, reverse coverage and limits | 5 | `3b9fc9d1ca95a2986b967c647ea39f3ae2168200f6f148fef85dd0dec3ee396b` |

Total: **90 mechanics**.

## Admission summary

- `ADMITTED`: 85
- `EXCLUDED`: 4
- `BLOCKED`: 1

The explicit exclusions are:

- `PREF-006`: preference/UI residue without an active backend;
- `SHOT-005`: `screenshotSpam`, which has no working Hush 1.0.1 backend;
- `REV-001`: reverse-engineering coverage is documentation, not production behavior;
- `REV-002`: compiler-erased original source text cannot become a production mechanic.

`IPC-002` is the sole blocked row. No complete general Hush XPC service, dictionary or reply contract is statically recovered, so no guessed XPC implementation may enter production.

## Source-state summary

- `SOURCE COMPLETE`: 2
- `NOT STARTED`: 83
- `BLOCKED`: 5

Only `PKG-001` and `PKG-002` are source-complete because Phase II Step 3 established the component and architecture matrices. No runtime feature mechanic is marked complete.

## Snapchat 14.15.0.48 correction

The earlier `.deb`-only boundary for `VER-002` is superseded by the supplied decrypted IPA. Exact private class names, selectors and Objective-C type encodings are now `PROVEN` for Snapchat version `14.15.0`, build `14.15.0.48`.

This does not claim device verification. Selector call order, object semantics and completion behavior remain final-device questions.

The IPA also resolves:

- `content_type = 9` as `STATUS_SAVE_TO_CAMERA_ROLL`;
- `content_type = 30` as `STATUS_SNAP_REMIX_CAPTURE`;
- `mutation_type = 3` as the UpdateConversation orchestration category;
- the pinned Story receipt surfaces;
- the Valdi presence bit layout.

## BackBoard correction

`INJ-001` preserves `backboardd` as a proven primary-filter process. SpringBoard classes remain owned by `Hooks/SpringBoard`, while `Hooks/BackBoard` is the reserved owner for exact event-tap/HID mechanics associated with the recovered BackBoard artifacts.

No BackBoard source is admitted until that exact mechanic is mapped. Preserving the owner does not authorize a guessed hook.

## Gate rule

A production source file may be introduced only when its ledger row is `ADMITTED`, its dependencies are present, its owner is unambiguous, and its complete disable/restoration behavior can be written.
