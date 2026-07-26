# Production Source Ownership

Phase II Step 4 assigns every production responsibility to one source home and
one process owner. This is a source contract, not a directory scaffold. A
physical directory is created only when its first complete production mechanic
is admitted by the mechanics ledger.

## Canonical logical tree

```text
Core/
  Features/
  Preferences/
  RuntimeState/
  ProcessRoles/
  Notifications/
  Models/
  Capabilities/

IPC/
  Commands/
  Results/
  DaemonClient/
  FileTransport/
  XPCBoundary/

Hooks/
  Bootstrap/
  SpringBoard/
  ScreenshotServices/
  ReplayKit/
  MediaServer/
  AudioMixer/
  CameraCapture/
  Power/
  Snapchat/

Daemon/
  Bootstrap/
  CommandDispatcher/
  Location/
  Containers/
  Keychain/
  Databases/
  SQLTriggers/
  ValdiPatches/
  MediaArchive/
  Backup/
  Maintenance/
  Lifecycle/

Media/
  Models/
  Import/
  Processing/
  Vault/
  Preview/
  PendingSend/
  Export/

Prefs/
Tools/
Packaging/
docs/
```

`Hooks/ReplayKit/` is explicit because ReplayKit is a distinct recovered
mechanic family with its own selectors, state machine, sample handling, and
restoration behavior.

## Shared production ownership

| Logical home | Owns | Must not own |
|---|---|---|
| `Core/Features` | Stable feature identifiers and feature-family metadata | Preference persistence, hooks, daemon execution, UI |
| `Core/Preferences` | Typed immutable preference contracts and policy values | Property-list I/O implementation inside callbacks, UI controllers |
| `Core/RuntimeState` | Immutable foreground, lock, capture, recording, location, power, daemon and Snapchat capability state | Process hooks, logging, persistence engines |
| `Core/ProcessRoles` | Process-role identifiers and exact role resolution contracts | Hook installation or process-specific framework use |
| `Core/Notifications` | Typed names and payload contracts for evidence-backed state propagation | Diagnostic or tracing notifications |
| `Core/Models` | Cross-component value objects | Privileged operations or framework-heavy processing |
| `Core/Capabilities` | Exact iOS and Snapchat capability contracts | Broad version guesses or private hook installation |
| `IPC/Commands` | Typed daemon command names and payload models | Command execution |
| `IPC/Results` | Typed product result and error models | Logging and diagnostic history |
| `IPC/DaemonClient` | Shared client API used by hooks, preferences and helper | Daemon-side privileged implementation |
| `IPC/FileTransport` | Versioned command/result/status file transport | Feature policy and privileged mechanics |
| `IPC/XPCBoundary` | A future exact XPC contract only after evidence admits it | Placeholder or guessed XPC implementation |
| `Media/*` | Media models, import, processing, vault, preview, durable send state and export | Process hooks, privileged container/keychain access, Snapchat-private hooks |
| `Prefs/` | PreferenceLoader interface for completed production backends | Hook, SQL, Valdi, daemon or media-processing implementation |
| `Tools/` | User-invoked typed daemon commands and package lifecycle entry points | Privileged implementation or duplicated daemon handlers |
| `Packaging/` | Rootless layout, filters, launchd, entitlements, migration and removal assets at their owning steps | Runtime feature logic |

## Hook ownership by process

| Original process or surface | K4L target | Source owner | Recovered mechanic families |
|---|---|---|---|
| SpringBoard | `K4LSnapSpringBoard` | `Hooks/Bootstrap`, `Hooks/SpringBoard`, SpringBoard-facing portions of `Hooks/ScreenshotServices`, `Hooks/ReplayKit`, and `Hooks/Power` | Foreground state, switcher/home cleanup, lock state, screenshot action filtering, ReplayKit, battery presentation |
| ScreenshotServicesService | `K4LSnap` | `Hooks/Bootstrap`, `Hooks/ScreenshotServices` | Snapshot suppression and encoded screenshot archive |
| mediaserverd | `K4LSnap` | `Hooks/Bootstrap`, `Hooks/MediaServer`, `Hooks/CameraCapture`, `Hooks/AudioMixer` | Camera sample interception, audio IOProc wrapping and media-service recovery |
| audiomxd | `K4LSnap` | `Hooks/Bootstrap`, `Hooks/AudioMixer` | CoreAudio IOProc lifecycle and stream-usage observation |
| cameracaptured | `K4LSnap` | `Hooks/Bootstrap`, `Hooks/CameraCapture` | Camera sample-buffer interception and replacement |
| powerd | `K4LSnap` | `Hooks/Bootstrap`, `Hooks/Power` | IOPS dictionary and native power-state mechanics |
| Snapchat 14.15.0.48 | dedicated secondary injection | `Hooks/Bootstrap`, `Hooks/Snapchat` | Pinned private classes/selectors, replay, save/unsave, Story receipts, typing/viewing policy and private handoff surfaces |

A target may compile shared `Core` and narrow `IPC/DaemonClient` contracts. It may
not compile another process owner's implementation merely because the symbols
are convenient.

## Daemon ownership

| Logical home | Production responsibility |
|---|---|
| `Daemon/Bootstrap` | Daemon process initialization and owned service startup |
| `Daemon/CommandDispatcher` | Strict command validation and dispatch |
| `Daemon/Location` | Recovered CLSimulationManager operation ordering and restoration state |
| `Daemon/Containers` | Narrow Snapchat container discovery and validated path resolution |
| `Daemon/Keychain` | Evidence-backed typed keychain operations only |
| `Daemon/Databases` | Snapchat database discovery, schema validation and transaction ownership |
| `Daemon/SQLTriggers` | Exact eight active trigger definitions plus legacy cleanup-only names |
| `Daemon/ValdiPatches` | Version- and hash-pinned module replacement, backup and restoration |
| `Daemon/MediaArchive` | Privileged archive placement and Snapchat cache/database coordination |
| `Daemon/Backup` | Evidence-backed backup and restoration mechanics |
| `Daemon/Maintenance` | Pruning, reconciliation and repair mechanics admitted by evidence |
| `Daemon/Lifecycle` | Install, upgrade, removal and restoration operations owned by the daemon/helper contract |

The daemon is the only owner of privileged container, keychain, Snapchat SQLite,
Valdi mutation, and privileged archive operations. Injected processes request
those operations through typed IPC; they never link the daemon implementation.

## Media ownership

`Media/` is production domain code that may be linked only where the owning
feature requires it:

- `K4LSnapPrefs` may use import, processing, preview and vault interfaces;
- `k4lsnapd` may use vault, archive, backup and reconciliation services;
- injected system and Snapchat targets may exchange durable item identifiers and
  typed metadata through Core/IPC, but do not link the media vault or processing
  implementation.

This keeps SQLite, Photos, AVFoundation export, thumbnails and filesystem work
out of real-time hook processes.

## BackBoard correction

The recovered Hush filter listed `backboardd`, but the resolved gesture,
home-button, lock-screen and switcher classes are SpringBoard classes. K4L does
not create a production `Hooks/BackBoard` owner and does not inject into
`backboardd` unless later evidence proves a distinct behavior that cannot be
owned by SpringBoard.

Historical filter evidence remains in the mechanics ledger. Historical process
presence is not permission to invent a current module.

## Admission rule

No directory or source file is created from this map alone. Its first source is
admitted only when:

1. the governing mechanic is present in the evidence bundle;
2. the production behavior is complete;
3. the owner and target are unambiguous;
4. dependencies are already admitted;
5. disable and restoration behavior are defined.
