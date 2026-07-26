# Phase I Status

Phase I establishes the clean project boundary. It does not implement or build
the tweak.

## Step 0 — Archive previous repository

Status: **RECORDED WITH LIMITATION**

Known legacy commit and branch identifiers are preserved in
`docs/LEGACY_ARCHIVE_RECORD.md`.

The deleted repository could not be cloned or bundled during this session.
A separately retained private archive is still desirable if one exists.

## Step 1 — Freeze evidence manifest

Status: **COMPLETE**

The governing reports, corpora, historical reports, and pinned Snapchat IPA are
listed with directly verified file sizes and SHA-256 hashes in
`docs/EVIDENCE_MANIFEST.md`.

Raw evidence remains outside the source repository.

## Step 2 — Create clean repository

Status: **COMPLETE**

The repository contains only:

- project identity;
- evidence integrity rules;
- rebuild rules;
- mechanics-ledger contract;
- legacy archive record;
- ignore rules.

It contains no package target, production feature, test system, logger,
diagnostic system, placeholder behavior, or licensing system.

## Phase boundary

Phase II must not begin until Phase I is reviewed and confirmed.
