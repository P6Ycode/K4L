# Core Production Contracts

Phase II Step 6 admits the first production source: immutable shared models and
feature policy. Core remains the bottom dependency layer and contains no hooks,
preference persistence engine, daemon execution, interface controller, tests,
logging, tracing, licensing, or Snapchat-private implementation.

## Admitted source

| Source home | Contract |
|---|---|
| `Core/Features` | Stable evidence-backed feature identifiers, validated immutable feature sets, and disjoint enabled/disabled override sets |
| `Core/ProcessRoles` | Exact process-role identities, including the preserved BackBoard boundary |
| `Core/Models` | Neutral tri-state values, capture/recording/content categories, validated location, genuine battery state, battery override, and media-save policy |
| `Core/Preferences` | Immutable global/account/friend/category policy snapshots and deterministic precedence |
| `Core/Capabilities` | Exact Snapchat 14.15.0.48 capability flags, eight active SQL-trigger flags, two Valdi patch flags, and daemon availability |
| `Core/RuntimeState` | Immutable foreground/account, protected-data, capture, recording, camera, audio, location, genuine/override battery, daemon, Snapchat, SQL, and Valdi state |

## Feature admission

Only feature identifiers with an admitted evidence path are declared. The Core
feature set deliberately excludes:

- `screenshotSpam`;
- licensing and entitlement gates;
- preference-only residue;
- score, badge, keyboard, macro, video-call, viewfinder, and similar surfaces
  that are not yet admitted by the normalized mechanics gate.

Adding an identifier later requires its evidence row and complete backend
contract. A decrypted label alone is insufficient.

## Default behavior

The default preference snapshot is master-disabled with an empty feature set.
The default runtime snapshot is neutral:

- no foreground bundle or active account assumption;
- protected-data and screen-capture state unknown;
- recording idle with no output URL;
- camera and audio inactive;
- no active location;
- genuine battery unknown and override disabled;
- daemon status unknown;
- no Snapchat-private capabilities;
- no SQL triggers;
- no Valdi patches.

Unknown or malformed identifiers cannot enable a feature.

## Policy precedence

Feature and media-save resolution is:

```text
friend category override
    ↓ inherit
friend general override
    ↓ inherit
account category override
    ↓ inherit
account general override
    ↓ inherit
global category override
    ↓ inherit
global policy
```

The master switch is evaluated first. When it is off, every feature resolves
disabled regardless of lower policy.

Content categories are typed as chat text, chat media, snap, story, voice note,
Spotlight/Discover, and stranger. Spoofed location is account-specific.

## Exact compatibility boundary

Private Snapchat capabilities are admitted only when all three values match:

```text
bundle:  com.toyopagroup.picaboo
version: 14.15.0
build:   14.15.0.48
```

Any mismatch strips every private capability. This contract does not claim
device verification.

## SQL and Valdi state

The SQL state can represent only the eight active recovered triggers. The
cleanup-only `ucm_read_seq` is represented by a separate
`legacyReadTriggerRemoved` flag and cannot be treated as active.

The Valdi state can represent only:

- the pinned presence module patch;
- the pinned voice-note-speed module patch.

Applied patches are suppressed when the Snapchat build is incompatible.
Original backups may still be recorded so an incompatible or upgraded app can
be restored.

## Battery restoration boundary

Genuine battery state and the configured override are separate immutable
objects. Later power hooks must continually refresh the genuine state so
disabling an override restores the newest Apple values rather than stale
values captured when spoofing began.

## Atomic runtime snapshots

`K4LRuntimeStateSnapshot` is immutable. `K4LRuntimeStateStore` exposes an atomic
copied snapshot property, allowing a process to replace one complete state
object instead of mutating fields that callbacks could observe halfway through
an update.

## Deliberately deferred

Step 6 does not implement:

- preference file paths, reading, writing, or migration;
- process-name detection and hook routing;
- Darwin notifications or command transport;
- private selector installation or runtime capability probing;
- SQL installation;
- Valdi file mutation;
- media processing;
- interface rows.

Those belong to later roadmap steps.
