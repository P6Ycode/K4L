# Production Dependency Boundaries

Phase II Step 4 fixes the allowed dependency direction before production source
is admitted.

## Allowed direction

```text
Core
  ↑
IPC contracts and client
  ↑
Hooks / Prefs / Tools / Media / Daemon
```

`Core` is the shared bottom layer. It never imports another K4L production
component.

`IPC` may import `Core`. Its shared client and transport contracts do not import
daemon handlers, hooks, preferences UI, or media implementation.

Feature components may import only the lower layers and narrowly approved
frameworks required by their process.

## Component rules

### Core

Allowed:

- Foundation and CoreFoundation value types;
- immutable models;
- typed feature, policy, role, state, notification and capability contracts.

Forbidden:

- UIKit controllers;
- Substrate or hook APIs;
- SQLite implementation;
- Photos or AVFoundation processing;
- filesystem mutation;
- keychain access;
- daemon execution;
- Snapchat-private classes;
- licensing, tests, logging or tracing.

### IPC

Allowed:

- `Core` contracts;
- Foundation/CoreFoundation serialization and notification primitives;
- strict command, result and transport behavior.

Forbidden:

- feature decisions;
- daemon handler implementation in the client;
- arbitrary command names or payloads;
- diagnostic history;
- speculative XPC service names or dictionary keys.

### Hooks

Allowed:

- `Core` immutable snapshots;
- narrow `IPC/DaemonClient` calls outside real-time callbacks;
- process-specific Apple frameworks;
- exact evidence-backed private contracts for the owning process.

Forbidden:

- linking `Daemon` implementation;
- direct Snapchat database or Valdi mutation;
- keychain or container brokerage;
- media vault or processing implementation;
- synchronous disk, SQLite or IPC work in camera/audio callbacks;
- importing another process family's hook implementation.

### Daemon

Allowed:

- `Core` and IPC contracts;
- privileged framework and filesystem operations admitted by evidence;
- `Media` services required for archive, vault, backup and maintenance.

Forbidden:

- UIKit interface ownership;
- Substrate hooks;
- arbitrary shell, file, SQLite or keychain access exposed to clients;
- Snapchat-private UI behavior;
- licensing or remote authorization.

### Media

Allowed:

- `Core` models;
- Foundation, Photos, AVFoundation, CoreGraphics, ImageIO and SQLite as required
  by admitted media mechanics.

Forbidden:

- process bootstrap or hooks;
- daemon command dispatch;
- privileged container/keychain access;
- PreferenceLoader controllers;
- Snapchat-private method hooks.

### Prefs

Allowed:

- `Core` policy and capability models;
- typed IPC daemon client;
- completed `Media` import/processing interfaces where the user-facing feature
  requires them;
- Preferences and UIKit interface frameworks.

Forbidden:

- hook installation;
- SQL trigger definitions;
- Valdi patch implementation;
- daemon handlers;
- duplicated media-vault storage engines;
- incomplete or unavailable preference rows.

### Tools

Allowed:

- `Core` command/result models;
- typed IPC daemon client;
- package lifecycle operations explicitly assigned to the helper.

Forbidden:

- duplicated privileged implementation;
- arbitrary command execution;
- tests, tracing or hidden debug commands.

### Packaging

Allowed:

- Theos target definitions;
- rootless layout;
- filters, entitlements, launchd, PreferenceLoader registration and maintainer
  scripts at their owning roadmap steps.

Forbidden:

- runtime feature logic;
- no-op scripts or inert jobs created merely to occupy package paths.

## Target inclusion matrix

| Target | May include | Must not include |
|---|---|---|
| `K4LSnap` | Core, narrow IPC client, system-service hook owners | SpringBoard UI, Prefs, Daemon handlers, Media vault/processing |
| `K4LSnapSpringBoard` | Core, narrow IPC client, SpringBoard/ReplayKit/presentation hook owners | SQL, Valdi, container, keychain, daemon or vault implementation |
| `K4LSnapPrefs` | Core, IPC client, Prefs, admitted Media UI/domain interfaces | Hooks, daemon handlers, SQL/Valdi engines |
| `k4lsnapd` | Core, IPC server/transport, Daemon, admitted Media services | UIKit preference UI or Substrate hooks |
| `k4lsnapctl` | Core, IPC client, Tools | Privileged handler implementation or feature hooks |

## Real-time boundary

Camera and audio callbacks may read prepared immutable state and already-prepared
buffers only. They may not:

- allocate or decode media;
- read files;
- access SQLite;
- wait for daemon replies;
- post synchronous cross-process work;
- perform preference parsing.

## Enforcement during later steps

Every new production file must state its owning component and target in the step
report. A later diff that introduces a forbidden dependency must be corrected in
that same step; compatibility shims and duplicated implementations are not an
acceptable temporary state.
