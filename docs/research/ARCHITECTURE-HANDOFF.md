<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Architecture handoff

This record translates the useful historical architecture into the approved
standalone design. It is not an active TODO list. Evidence labels are defined
in [`README.md`](README.md).

## Historical system

The prior branch contained three coupled pieces:

1. a C++20/Capstone image analyzer and block emitter;
2. an AOT registry/runtime with an optional Dynarmic fallback; and
3. an opt-in Vita3K CPU backend plus post-link ELF dumping.

- **Verified:** This stack was effective as a correctness laboratory.
- **Verified:** Its complete-state comparisons, strict-miss path, checked
  memory adapter, and synthetic/Dynarmic vectors caught real emitter and
  synchronization bugs.
- **Verified:** It also coupled production progress to a full emulator tree and
  duplicated functionality now present in the standalone upstream framework.

## Current repository boundary

### Framework: `vitarecomp`

The canonical upstream C runtime/emitter remains the production path. Reusable
work migrated here consists of:

- focused tests against the existing C CPU, VFP, memory, dispatch, and trap
  APIs;
- machine-readable vectors for behavior whose canonical integration point does
  not exist yet;
- explicit overlap, deterministic ordering, ARM/Thumb key, CPU-state, checked
  memory, strict-miss, and exclusive-monitor contracts; and
- a migration record naming each deferred integration point.

The complete historical C++ tool was rejected. It remains snapshot/reference
material, not a second production recompiler.

### Game repository

This repository owns title policy and local workflow glue:

- curated research without private payloads;
- content-aware staging of locally generated sources;
- minimal patches for an external pinned Vita3K checkout; and
- title-specific host/configuration work added by later checkpoints.

Generated translated code belongs only in ignored local output roots.

### External Vita3K

- **Verified:** Vita3K is needed to install/decrypt authorized content and to
  capture runtime-addressed module images after linking.
- **Derived:** Vita3K may remain an optional semantic oracle during framework
  development.
- **Verified decision:** Vita3K is not vendored and its historical AOT CPU
  bridge is not a production dependency.

The required patch series contains only the generic post-link dump ordering and
an explicit headless switch. The optional AOT CPU bridge is separately
documented and deferred because it depends on the rejected duplicate C++
runtime and on pending canonical CPU selection.

## Contracts retained from the prior branch

| Contract | Evidence | New integration |
|---|---|---|
| Capture after relocation/export/import linking | Verified | Required Vita3K patch 0001 |
| Explicit, headless dump opt-in | Verified | Required Vita3K patch 0002 |
| Stable generated-source identities | Verified | `tools/generated/Stage-GeneratedSources.ps1` |
| Checked guest memory | Verified | Canonical framework tests plus deferred vectors |
| Complete raw CPU/VFP comparison | Verified | Canonical state-surface test plus oracle fixture |
| Mode-aware code identity | Verified | Deferred collision vector pending canonical CPU selection |
| Strict source+target dispatch diagnostics | Verified | Canonical trace diagnostic test |
| Deterministic multi-image composition | Verified | Machine-readable fixture pending image-set API |
| Exclusive monitor/write serialization | Verified | Deferred fixture pending scheduler/CPU ownership |

## Deferred semantic cases

The following current-snapshot fixes are preserved as precise fixtures rather
than inaccurately claimed as running against the present C emitter:

- predicate-false fallthrough for conditional A32 `BL`, register `BLX`, `BX`,
  and `SVC`;
- `BLX LR` source capture before link-register update;
- Thumb PC alignment for `TBB`/`TBH`;
- lane-versus-whole-register `VST1` validation;
- FPSCR flush-to-zero comparison behavior;
- wide non-writeback `LDM` commit ordering;
- exclusive reservation invalidation under the monitor lock; and
- same-aligned-address ARM/Thumb registry entries.

Each fixture names the exact future source/test seam. They should become
executable tests when that seam is implemented, without importing the old
runtime wholesale.

## Rejected historical material

- the full modified Vita3K source tree;
- the complete C++ recompiler/runtime as production code;
- GUI and Android configuration changes unnecessary for the external workflow;
- private title inputs, generated blocks, traces, smoke logs, and addresses;
- the unrelated PS2Recomp backlog note; and
- the old live TODO's hybrid-specific promotion queue.
