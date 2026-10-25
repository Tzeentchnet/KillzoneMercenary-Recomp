<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Vita3K post-link dump patch series

This directory contains the minimal generic Vita3K changes required by the
external content workflow. It does not contain Vita3K source, title bytes,
title addresses, generated code, user-data paths, or game-specific matching.
Vita3K remains a separately built and executed extraction/oracle tool; neither
patch makes it part of the native host or the production CPU path.

## Pinned base

- Repository: <https://github.com/Vita3K/Vita3K>
- Commit: `ee50eb8644b4184996047f04406486281586935b`
- License: GPL-2.0-or-later (the patches preserve Vita3K's licensing)

The base is the exact `origin/master` revision recorded by the verified prior
AOT snapshot. Do not assume the patches apply to another revision merely
because hunks happen to match.

## Required order

Apply the filenames listed in [`series`](series), in order:

1. `0001-dump-modules-after-linking.patch` moves Vita3K's existing ELF dump
   after relocation, export linking, and import linking. This ordering is the
   functional requirement: a pre-link dump can contain stale import bodies.
2. `0002-add-headless-dump-elfs-switch.patch` exposes the existing opt-in dump
   flag as `--dump-elfs` and wires it before modules load. It adds no default
   output path, remains disabled unless explicitly requested, and does not
   clear a dump flag selected through an existing frontend.

Example against a disposable external checkout:

```powershell
git checkout --detach ee50eb8644b4184996047f04406486281586935b
git am C:\path\to\KillzoneMercenary-Recomp\patches\vita3k\0001-dump-modules-after-linking.patch
git am C:\path\to\KillzoneMercenary-Recomp\patches\vita3k\0002-add-headless-dump-elfs-switch.patch
```

`git apply --check` is sufficient when commit metadata is not wanted.

## Optional AOT CPU bridge

The historical branch's AOT CPU bridge is intentionally **not** part of this
required series. It depended on the historical C++ block runtime and Dynarmic
fallback, while the approved production architecture uses the standalone
framework's canonical C API. Copying it would reintroduce a second production
recompiler and entangle content preparation with CPU selection.

Its broadly reusable state, memory, dispatch, and exclusive-monitor cases were
migrated into the canonical framework. At framework
`f3408e1ea73b724c7ba3a644633938c220f2cc2a`, mode-aware CPU/dispatch,
checked/exclusive-memory, and strict-diagnostic cases execute in public tests.
Any future full-state Vita3K oracle adapter must be a separate optional series;
it must not be required to dump modules or run the native application.

## Validation

The migration validation extracts only the four touched files from the pinned
base, applies both patches in sequence with `git apply --check`, and scans this
directory for title identifiers, private paths, and address literals. See the
top-level [`MIGRATION.md`](../../MIGRATION.md) for recorded results.

The accepted private workflow produced a deterministic three-image manifest,
but that verifies extraction only. It does not establish title bootability or
playability; see
[`docs/FOUNDATION_VERIFICATION.md`](../../docs/FOUNDATION_VERIFICATION.md).
