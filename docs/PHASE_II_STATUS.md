# Phase II Status

Phase II recreates the production package and source ownership architecture.
Work remains one roadmap step at a time.

## Step 3 — Create package targets

Status: **CONFIRMED**

Declared production targets:

- `K4LSnap` system-process tweak;
- `K4LSnapSpringBoard` SpringBoard tweak;
- `K4LSnapPrefs` PreferenceLoader bundle;
- `k4lsnapd` privileged daemon;
- `k4lsnapctl` control helper;
- `com.p6ycode.k4lsnapd` launchd job identity.

The Makefile contains target metadata and deliberately empty source lists.
Production source is admitted only by its owning roadmap step. No inert
constructors, no-op services, fake adapters, or placeholder executables were
created.

Package metadata establishes:

- Debian package identifier `com.p6ycode.k4l`;
- rootless package scheme;
- minimum iOS 15.0;
- arm64/arm64e tweak, bundle, and helper targets;
- arm64 daemon target;
- dependencies on MobileSubstrate and PreferenceLoader;
- logical rootless install locations.

Deferred to their owning steps:

- tweak filters;
- preference resources and registration;
- daemon entitlements;
- launchd property-list contents;
- maintainer scripts;
- Choicy/app-injection configuration;
- migration and uninstall behavior.

## Step 4 — Establish production source ownership

Status: **SOURCE COMPLETE — AWAITING CONFIRMATION**

The canonical logical source tree now assigns one owner to:

- shared Core contracts;
- typed IPC contracts and client transport;
- SpringBoard, ScreenshotServices, ReplayKit, media-server, audio, camera, power
  and Snapchat hook families;
- daemon command, location, container, keychain, database, SQL-trigger, Valdi,
  media-archive, backup, maintenance and lifecycle mechanics;
- media import, processing, vault, preview, durable send and export mechanics;
- PreferenceLoader, control helper and package assets.

`Hooks/ReplayKit` is explicitly included because ReplayKit is a distinct
recovered mechanic family.

No production `Hooks/BackBoard` owner is created. The historical Hush filter is
preserved as evidence, but the resolved gesture, lock-screen, home-button and
switcher classes belong to SpringBoard.

Dependency direction is fixed:

```text
Core
  ↑
IPC contracts/client
  ↑
Hooks / Prefs / Tools / Media / Daemon
```

Injected targets may not link daemon handlers, SQL, Valdi, keychain, container,
media-vault or media-processing implementation. Camera and audio callbacks may
not perform disk, SQLite, decoding or synchronous IPC work.

The source tree remains logical only. No empty directories, source files,
features, tests, logging, tracing, licensing, filters, entitlements or scripts
were created.

No compilation, packaging, installation, testing, logging, or tracing was
performed.

## Phase boundary

Step 5 must not begin until Step 4 is reviewed and confirmed.
