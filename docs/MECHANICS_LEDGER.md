# Mechanics Ledger Contract

The authoritative private mechanics dataset is
`Hush_Mechanics_Ledger.tsv`, pinned by SHA-256 in
`docs/EVIDENCE_MANIFEST.md`. It remains outside this repository.

This document defines how evidence rows become clean-room production source.

## Required mechanic record

Every production mechanic must eventually record:

| Field | Meaning |
|---|---|
| Mechanic ID | Stable K4L identifier |
| Evidence source | Exact report, table, row, selector, symbol, SQL, path, command, or notification |
| Evidence state | `PROVEN`, `IMPLEMENTATION-EQUIVALENT`, `FINAL DEVICE CONFIRMATION REQUIRED`, or `PERMANENTLY UNRECOVERABLE` |
| Original artifact | Hush dylib, preference executable, daemon, helper, package file, or Snapchat application |
| Original process | Exact process owning the recovered behavior |
| Recovered contract | Inputs, output, original-call ordering, side effects, persistence, and restoration behavior |
| K4L owner | One production component and one source directory |
| Dependencies | Typed contracts required before implementation |
| Source state | `NOT STARTED`, `SOURCE COMPLETE`, `ASSEMBLED`, `DEVICE VERIFIED`, `BEHAVIOR MATCHED`, or `BLOCKED` |
| Final device question | Exact runtime question remaining, when applicable |

## Admission rule

A production file is admitted only when:

1. its mechanic exists in the evidence bundle;
2. its process and ownership are unambiguous;
3. all required dependencies are ready;
4. the full production behavior can be written;
5. its disable or restoration behavior is defined.

Preference-only strings, abandoned schema residue, unresolved names, and
speculative compatibility claims do not qualify.

## Evidence is not implementation

Evidence and implementation are tracked separately.

Examples:

- A `PROVEN` selector can remain `NOT STARTED`.
- `SOURCE COMPLETE` code can still require `FINAL DEVICE CONFIRMATION REQUIRED`.
- A mechanism can be `BLOCKED` without weakening the evidence supporting its
  known portion.
- Final device behavior may refine call order or object semantics, but may not
  invent a static contract that the evidence does not support.

## Initial repository state

At the end of Phase I:

- zero production mechanics are implemented;
- no feature is represented by source;
- no package target exists;
- no preference row exists;
- no runtime compatibility claim exists.

The full 90-row implementation ledger is imported and normalized in its
dedicated roadmap step, not during repository initialization.
