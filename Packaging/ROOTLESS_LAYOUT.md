# Rootless Package Layout Contract

This document defines the logical package layout. Actual files enter the package
only when their owning roadmap step admits complete production behavior.

```text
/Library/MobileSubstrate/DynamicLibraries/
  K4LSnap.dylib
  K4LSnap.plist
  K4LSnapSpringBoard.dylib
  K4LSnapSpringBoard.plist

/Library/PreferenceBundles/
  K4LSnapPrefs.bundle/

/Library/PreferenceLoader/Preferences/
  K4LSnap.plist

/Library/LaunchDaemons/
  com.p6ycode.k4lsnapd.plist

/usr/libexec/
  k4lsnapd

/usr/local/bin/
  k4lsnapctl
```

The Theos rootless package scheme supplies the jailbreak root prefix. Source and
package scripts must not hard-code one jailbreak's root prefix into shared path
contracts.

## Admission ownership

| Package path | Owning roadmap step |
|---|---|
| Tweak dylibs | Steps admitting their complete production source |
| Tweak filters | Process-router step |
| Preference bundle and registration | Preference UI step |
| Daemon executable | Daemon production steps |
| Daemon entitlement profile | Privileged capability steps |
| launchd property list | Package lifecycle step |
| Control helper | Command transport and lifecycle steps |
| Maintainer scripts | Package lifecycle step |
| Choicy/app-injection configuration | Process-router and package lifecycle steps |

No empty bundle, no-op executable, permissive entitlement file, inert launchd
job, or do-nothing maintainer script is admitted merely to occupy a path.
