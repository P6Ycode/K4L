# Production Package Targets

Phase II Step 3 establishes the package component boundary. It does not admit
feature source or inert placeholder implementations.

## Target matrix

| Target | Kind | Architectures | Production responsibility | Logical install location |
|---|---|---|---|---|
| `K4LSnap` | Substrate tweak | arm64, arm64e | Non-SpringBoard system-process mechanics | `/Library/MobileSubstrate/DynamicLibraries/` |
| `K4LSnapSpringBoard` | Substrate tweak | arm64, arm64e | SpringBoard-only mechanics | `/Library/MobileSubstrate/DynamicLibraries/` |
| `K4LSnapPrefs` | PreferenceLoader bundle | arm64, arm64e | User-facing preferences for completed backends | `/Library/PreferenceBundles/` |
| `k4lsnapd` | Privileged daemon executable | arm64 | Evidence-backed privileged operations | `/usr/libexec/` |
| `k4lsnapctl` | Control helper executable | arm64, arm64e | User-invoked lifecycle and typed daemon commands | `/usr/local/bin/` |
| `com.p6ycode.k4lsnapd` | launchd job | n/a | Launch and supervise `k4lsnapd` | `/Library/LaunchDaemons/` |

The paths above are package-relative logical paths. The Theos rootless package
scheme applies the jailbreak root prefix during packaging and installation.

## Stable identifiers

| Component | Identifier |
|---|---|
| Debian package | `com.p6ycode.k4l` |
| Preference bundle | `com.p6ycode.k4l.preferences` |
| Daemon launch label | `com.p6ycode.k4lsnapd` |
| Daemon executable | `k4lsnapd` |
| Control helper | `k4lsnapctl` |

## Ownership rules

- `K4LSnap` never owns SpringBoard-only classes or user interface code.
- `K4LSnapSpringBoard` never owns daemon, SQL, Valdi, media-vault, or keychain implementation.
- `K4LSnapPrefs` contains interface code only and consumes shared contracts plus the typed daemon client.
- `k4lsnapd` owns privileged filesystem, database, location, keychain, patch, archive, backup, maintenance, and lifecycle operations only when admitted by evidence.
- `k4lsnapctl` uses the same typed daemon client as every other client. It does not duplicate privileged implementation.

## Deferred package material

The following files are intentionally not created in Step 3 because their real
production behavior belongs to later roadmap steps:

- tweak filter property lists;
- PreferenceLoader registration and preference resources;
- daemon entitlements;
- launchd property list contents;
- maintainer scripts;
- Choicy and app-injection configuration;
- package migration and uninstall logic.

Creating no-op versions now would be placeholder behavior and is prohibited.
