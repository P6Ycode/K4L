# Phase II Status

Phase II recreates the production package architecture, source ownership and implementation gate. Work remains one roadmap step at a time.

## Step 3 — Create package targets

Status: **CONFIRMED**

Declared production targets:

- `K4LSnap` system-process tweak;
- `K4LSnapSpringBoard` SpringBoard tweak;
- `K4LSnapPrefs` PreferenceLoader bundle;
- `k4lsnapd` privileged daemon;
- `k4lsnapctl` control helper;
- `com.p6ycode.k4lsnapd` launchd job identity.

The Makefile contains target metadata and deliberately empty source lists. No inert constructors, no-op services, fake adapters or placeholder executables were created.

## Step 4 — Establish production source ownership

Status: **CONFIRMED WITH BACKBOARD CORRECTION**

The canonical logical source tree assigns one owner to shared Core, typed IPC, process hooks, daemon mechanics, media, preferences, tools and packaging.

Correction applied during Step 5:

- `Hooks/BackBoard` is retained as the production ownership boundary for exact mechanics that execute in `backboardd`;
- `backboardd` remains a proven primary-filter process;
- resolved `SB*`, `FBScene`, lock-screen, home-button and switcher selectors remain owned by SpringBoard;
- no BackBoard source is admitted until its event-tap/HID contract is mapped.

Dependency direction remains:

```text
Core
  ↑
IPC contracts/client
  ↑
Hooks / Prefs / Tools / Media / Daemon
```

Injected targets may not link daemon handlers, SQL, Valdi, keychain, container, media-vault or media-processing implementation. Camera and audio callbacks may not perform disk, SQLite, decoding or synchronous IPC work.

## Step 5 — Import the mechanics implementation gate

Status: **SOURCE COMPLETE — AWAITING CONFIRMATION**

The 90 recovered mechanics are normalized into six repository ledger shards under `docs/ledger/`.

Ledger totals:

- 85 `ADMITTED`;
- 4 `EXCLUDED`;
- 1 `BLOCKED`.

Source totals:

- 2 `SOURCE COMPLETE` package-architecture rows;
- 83 `NOT STARTED` admitted rows;
- 5 `BLOCKED` excluded or unresolved rows.

Explicit exclusions:

- preference/UI residue without a working backend;
- `screenshotSpam`;
- reverse-engineering coverage as a production mechanic;
- compiler-erased original source text.

The sole blocked runtime boundary is the incomplete general XPC contract. No guessed XPC implementation is allowed.

The Snapchat 14.15.0.48 IPA supersedes the previous external-binary block for private selectors. Exact classes, selectors and Objective-C type encodings are now proven for that pinned build; call order and object semantics remain final-device questions.

`INJ-001` preserves the BackBoard process/filter evidence and records the exact remaining question about the event-tap/HID mechanic.

No production feature source, filter, entitlement, preference row, daemon handler, test, logger, trace, placeholder or licensing system was created.

No compilation, packaging, installation, testing, logging or tracing was performed.

## Phase boundary

Step 6 must not begin until Step 5 is reviewed and confirmed.
