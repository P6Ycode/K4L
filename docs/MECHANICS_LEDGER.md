# Mechanics Ledger Contract

The authoritative private mechanics dataset is `Hush_Mechanics_Ledger.tsv`, pinned by SHA-256 in `docs/EVIDENCE_MANIFEST.md`. It remains outside this repository.

Phase II Step 5 converts its 90 recovered mechanics into repository-owned clean-room contracts under [`docs/ledger/`](ledger/INDEX.md).

## Required mechanic record

Every normalized row records:

| Field | Meaning |
|---|---|
| Mechanic ID | Stable evidence identifier |
| Evidence source | Exact report, table row or supplemental Snapchat artifact |
| Evidence state | `PROVEN`, `IMPLEMENTATION-EQUIVALENT`, `FINAL DEVICE CONFIRMATION REQUIRED`, or `PERMANENTLY UNRECOVERABLE` |
| Original artifact | Recovered package component, class, trigger, resource or binary surface |
| Original process | Exact process or package phase owning the recovered behavior |
| Recovered contract | Static behavior that K4L may reproduce |
| K4L owner | One production component and source directory |
| Dependencies | Contracts that must exist first |
| Admission | `ADMITTED`, `EXCLUDED`, or `BLOCKED` |
| Source state | `NOT STARTED`, `SOURCE COMPLETE`, `ASSEMBLED`, `DEVICE VERIFIED`, `BEHAVIOR MATCHED`, or `BLOCKED` |
| Final device question | Exact runtime question remaining, when applicable |

## Admission rule

A production file is admitted only when:

1. its mechanic exists in the normalized ledger;
2. its row is `ADMITTED`;
3. its process and owner are unambiguous;
4. all required dependencies are ready;
5. the complete production behavior can be written;
6. disable and restoration behavior are defined.

Preference-only strings, abandoned schema residue, unresolved names and speculative compatibility claims do not qualify.

## Evidence is not implementation

Evidence and implementation remain separate axes.

- A `PROVEN` selector may remain `NOT STARTED`.
- `SOURCE COMPLETE` code may still require final device confirmation.
- A row may be `BLOCKED` without weakening its known static evidence.
- Final device behavior may refine call order or object semantics, but may not invent a static contract.

`PROVEN` means the listed static contract is proven. It does not mean K4L has compiled, installed or behaved correctly on-device.

## Current ledger state

The six ledger shards contain exactly 90 rows:

- 85 `ADMITTED`;
- 4 `EXCLUDED`;
- 1 `BLOCKED`.

Source states:

- 2 `SOURCE COMPLETE` package-architecture rows;
- 83 admitted rows `NOT STARTED`;
- 5 excluded or blocked rows marked `BLOCKED`.

No runtime feature mechanic is source-complete.

## Explicit corrections

### Snapchat private API boundary

The supplied decrypted Snapchat IPA supersedes the former `.deb`-only `EXTERNAL BINARY REQUIRED` boundary for `VER-002`.

Exact classes, selectors and Objective-C type encodings are now `PROVEN` for:

- bundle `com.toyopagroup.picaboo`;
- version `14.15.0`;
- build `14.15.0.48`;
- arm64.

Runtime call order, object semantics and completion behavior remain final-device questions.

### BackBoard ownership

`INJ-001` preserves `backboardd` as a proven primary-filter process. SpringBoard selectors remain in `Hooks/SpringBoard`; exact BackBoard event-tap/HID mechanics belong to `Hooks/BackBoard` once mapped.

No BackBoard source may be guessed merely from the filter entry.

### Proven negative

`screenshotSpam` has no active Hush 1.0.1 backend and is excluded. It is not a production feature, preference or placeholder.

### General XPC boundary

`IPC-002` remains blocked. No complete general Hush XPC service, request dictionary or reply contract is statically recovered. K4L uses no guessed XPC implementation.

## Ledger integrity

The shard names, row counts and SHA-256 hashes are recorded in [`docs/ledger/INDEX.md`](ledger/INDEX.md). Any row change must identify the superseding evidence and update the corresponding shard hash.
