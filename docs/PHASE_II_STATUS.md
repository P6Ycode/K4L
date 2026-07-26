# Phase II Status

Phase II recreates the production package architecture, source ownership, mechanics gate, and shared Core contracts. Work remains one roadmap step at a time.

## Step 3 — Create package targets

Status: **CONFIRMED**

Declared production targets:

- `K4LSnap` system-process tweak;
- `K4LSnapSpringBoard` SpringBoard tweak;
- `K4LSnapPrefs` PreferenceLoader bundle;
- `k4lsnapd` privileged daemon;
- `k4lsnapctl` control helper;
- `com.p6ycode.k4lsnapd` launchd job identity.

The Makefile contains target metadata and deliberately empty target source lists. No inert constructors, no-op services, fake adapters, or placeholder executables were created.

## Step 4 — Establish production source ownership

Status: **CONFIRMED WITH BACKBOARD CORRECTION**

The canonical logical source tree assigns one owner to shared Core, typed IPC, process hooks, daemon mechanics, media, preferences, tools, and packaging.

- `Hooks/BackBoard` is retained for exact mechanics that execute in `backboardd`;
- `backboardd` remains a proven primary-filter process;
- resolved `SB*`, `FBScene`, lock-screen, home-button, and switcher selectors remain owned by SpringBoard;
- no BackBoard source is admitted until its event-tap/HID contract is mapped.

Dependency direction remains:

```text
Core
  ↑
IPC contracts/client
  ↑
Hooks / Prefs / Tools / Media / Daemon
```

## Step 5 — Import the mechanics implementation gate

Status: **CONFIRMED**

The 90 recovered mechanics are normalized into six repository ledger shards under `docs/ledger/`:

- 85 `ADMITTED`;
- 4 `EXCLUDED`;
- 1 `BLOCKED`.

The sole blocked runtime boundary is the incomplete general XPC contract. No guessed XPC implementation is allowed.

The Snapchat 14.15.0.48 IPA supersedes the previous external-binary block for private selectors. Exact classes, selectors, and Objective-C type encodings are proven for that pinned build; call order and object semantics remain final-device questions.

## Step 6 — Build Core models and feature policy

Status: **SOURCE COMPLETE — AWAITING CONFIRMATION**

Added immutable production contracts under `Core/` for:

- 30 admitted feature identifiers and validated feature sets;
- enabled/disabled override sets with deterministic inheritance;
- process roles, including the preserved BackBoard boundary;
- typed capture, recording, content-category, daemon, location, battery, and media values;
- global, account, friend, and category preference policy;
- friend/category → account → global precedence;
- per-account spoof location with restore-after-restart intent;
- media destinations with per-sender folders and albums;
- exact Snapchat 14.15.0.48 capability masking;
- eight active SQL-trigger flags plus cleanup-only legacy-trigger state;
- presence and voice-note Valdi patch state;
- immutable runtime snapshots and atomic whole-snapshot replacement.

Default behavior is fail-closed:

- master disabled;
- no enabled feature identifiers;
- neutral runtime values;
- no private Snapchat capabilities;
- no SQL triggers;
- no applied Valdi patches;
- battery override disabled.

`K4L_CORE_FILES` records the shared source inventory, but no target links it yet. Step 6 therefore does not create inert tweak dylibs, bundles, daemons, or tools.

No preference file I/O, migration engine, process routing, notification transport, hook installation, daemon operation, SQL mutation, Valdi mutation, media processing, interface, test, logger, trace, placeholder, or licensing system was added.

No compilation, packaging, installation, testing, logging, or tracing was performed.

## Phase boundary

Step 7 must not begin until Step 6 is reviewed and confirmed.
