# K4L

K4L is a clean-room, ground-up reconstruction of the production mechanics
recovered from the Hush package and the pinned Snapchat application:

- bundle identifier: `com.toyopagroup.picaboo`
- version: `14.15.0`
- build: `14.15.0.48`
- architecture: arm64
- minimum iOS: 15.0

## Current phase

Phase I establishes evidence integrity, rebuild rules, and repository history.
There is no tweak, daemon, preference bundle, helper, package target, feature,
test system, or logging system in this repository yet.

Production source begins only after Phase I is confirmed.

## Project boundaries

The rebuild contains no licensing, activation, subscriptions, receipt
validation, device binding, trial logic, remote entitlement checks, or
licensing-shaped feature gates.

During implementation it also contains no test targets, mock features,
placeholder hooks, observation-only features, debug menus, diagnostic overlays,
or logging/tracing framework. Compilation, device testing, and temporary
targeted tracing begin only after the complete production tweak is assembled.

## Evidence

The private evidence bundle is maintained outside the repository. Its artifact
hashes, authority order, and integrity rules are pinned in
[`docs/EVIDENCE_MANIFEST.md`](docs/EVIDENCE_MANIFEST.md).

## Development flow

- `main`: reviewed project state
- `rebuild/foundation`: active ground-up rebuild
- `feature/*`: narrowly scoped production work when needed
- `archive/*`: immutable historical markers

Work proceeds one roadmap step at a time. Each step receives a complete diff
review and stops for confirmation before the next step begins.
