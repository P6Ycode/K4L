# Rebuild Rules

These rules are permanent for the K4L ground-up rebuild.

## Evidence governs behavior

The private evidence bundle determines what the production tweak does. The
roadmap determines implementation order.

No feature, hook, daemon operation, database mutation, Valdi patch, preference,
notification, path, or package action may enter production source without a
specific evidence contract.

Unknown behavior must remain excluded or fail closed. It must not be filled with
a plausible guess.

## Permanent licensing exclusion

K4L contains no:

- licensing or activation;
- subscriptions or trials;
- receipt validation;
- device binding;
- license sessions;
- remote feature authorization;
- payment or unlock server;
- account entitlement checks;
- licensing-shaped local gates.

Recovered licensing behavior is intentionally excluded.

## No test code during production implementation

Before final integration, the repository contains no:

- test target or test framework;
- mock service or fake daemon;
- fake Snapchat adapter;
- test database or test account;
- sample media provider;
- test-only command;
- placeholder feature;
- observation-only feature;
- simulated success response;
- debug preference row;
- diagnostic overlay or testing menu.

There is no production `Tests/` directory.

## No logging or tracing during production implementation

Before final integration, source contains no:

- general logger;
- selector or hook-call recorder;
- argument tracing;
- event history;
- diagnostic snapshots;
- debug files or notifications;
- hidden diagnostics interface;
- permanent `NSLog` or `os_log` statements.

Genuine product errors and typed command results are allowed. They are normal
behavior, not a tracing system.

Temporary targeted tracing may be introduced only after the entire production
tweak is assembled and installed for final device integration. It must be
removed before the release package is produced.

## No incomplete production features

A feature enters production source only when its complete evidence-backed
mechanic can be implemented.

The source must not contain:

- empty switches;
- disabled placeholder modules;
- speculative selectors;
- mock compatibility entries;
- source files created only to satisfy a folder diagram;
- preference rows without working backends;
- decrypted feature names treated as proof of implementation.

A mechanic that is not ready remains outside the source.

## Development review before final integration

Before the full tweak is assembled, each roadmap step uses only:

- evidence review;
- production contract review;
- source writing;
- ownership and dependency review;
- complete diff review.

Compilation, packaging, installation, runtime testing, logging, and tracing
begin only after the complete production source is assembled.

## One-step execution

For every roadmap step:

1. inspect the governing evidence;
2. define the exact production contract;
3. modify only files owned by that step;
4. review every changed file;
5. confirm dependencies and process ownership;
6. report exactly what changed and what remains;
7. stop for confirmation.

No later step may be folded into an earlier step.

## Release cleanliness

The final release must contain no licensing, test, mock, placeholder, logging,
tracing, debug, or diagnostic system. Temporary integration instrumentation is
removed before the clean release package is built.
