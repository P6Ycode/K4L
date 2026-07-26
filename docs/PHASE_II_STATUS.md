# Phase II Status

Phase II recreates the production package and source ownership architecture.
Work remains one roadmap step at a time.

## Step 3 — Create package targets

Status: **SOURCE COMPLETE — AWAITING CONFIRMATION**

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

No compilation, packaging, installation, testing, logging, or tracing was
performed.

## Phase boundary

Step 4 must not begin until Step 3 is reviewed and confirmed.
