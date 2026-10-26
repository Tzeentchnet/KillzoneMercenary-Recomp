<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Architecture handoff

This record maps useful evidence from the historical Vita3K hybrid into the
accepted standalone architecture. It is not an active TODO list. Historical
evidence labels are defined in [`README.md`](README.md); this historical
handoff was reconciled against framework
`0e81bb4b275435b2396b01a88c8d767d0104cc8b` and game report
`36fef0e94ab99d1fc6e1903f02a388013eb3585d`.

## Historical system

The prior branch contained three coupled pieces:

1. a C++20/Capstone image analyzer and block emitter;
2. an AOT registry/runtime with an optional Dynarmic fallback; and
3. an opt-in Vita3K CPU backend plus post-link ELF dumping.

- **Verified:** This stack was useful as a correctness laboratory.
- **Verified:** Complete-state comparisons, strict misses, checked memory, and
  synthetic/Dynarmic vectors found real emitter and synchronization defects.
- **Verified:** It also coupled progress to a full emulator tree and duplicated
  functionality now implemented in the canonical standalone framework.

The hybrid is preserved as provenance and evidence only. It is not a dormant
fallback architecture.

## Accepted production boundary

### Framework: `Tzeentchnet/vitarecomp`

The framework owns the production static generated-C path:

- SELF/ELF/relocation parsing, ARM/Thumb discovery, deterministic partitioned C
  emission, reports, and strict traps;
- checked CPU/memory/dispatch behavior, standalone runtime/HLE, threading,
  synchronization, allocators, imports, I/O, VFS, and lifecycle;
- the renderer-neutral versioned C GPU ABI; and
- production DX12 and Vulkan backends plus public conformance tests.

The exact game gitlink is
`0e81bb4b275435b2396b01a88c8d767d0104cc8b`. The complete historical C++ tool
was rejected rather than retained as a second production recompiler.

### Game repository

This repository owns title policy and local workflow glue:

- curated research without private payloads;
- PCSA00107 archive inspection, external Vita3K orchestration, and independent
  deterministic runtime-image manifests;
- content-aware staging of locally generated source;
- strict native-host CLI/content validation and a read-only `app0:` mount;
- Win32 lifecycle and explicit DX12/Vulkan selection; and
- future title-specific bindings and compatibility work.

Generated translated code, reports, private manifests, content, traces, and
captures belong only in ignored local roots.

### External Vita3K

- **Verified:** Vita3K can install/decrypt authorized content and capture
  runtime-addressed modules after relocation and export/import linking.
- **Verified:** The required patch series contains only post-link dump ordering
  and an explicit headless `--dump-elfs` switch.
- **Allowed:** Vita3K source may be read as a code reference; its separately
  executed runtime is used only for the frozen extraction workflow.
- **Rejected:** Vita3K is not vendored, linked, or used for production CPU,
  HLE, graphics, or fallback execution.

The historical AOT CPU bridge remains outside the required patch series.

## Migrated contracts and current Gate 1 integration

| Contract | Current status | Evidence/integration |
|---|---|---|
| Capture after relocation/export/import linking | **Implemented and verified** | Required Vita3K patch 0001; private three-image repeat |
| Explicit headless dump opt-in | **Implemented and verified** | Required Vita3K patch 0002; wrapper capability checks |
| Stable generated-source identities | **Implemented and publicly verified** | Schema-v1 local provenance, validator, content-aware staging, and synthetic regressions |
| Checked guest memory | **Implemented and verified** | Framework runtime and prior-AOT tests |
| Raw CPU/VFP state behavior | **Implemented and verified for represented state** | Framework CPU/runtime tests |
| ARM/Thumb mode-aware discovery and dispatch | **Implemented and verified** | Public discovery/emitter/dispatch regressions |
| Conditional A32 exits and `BLX LR` source capture | **Implemented and verified** | Public decode/emission regressions |
| Aligned-PC `TBB`/`TBH` handling | **Implemented and verified** | Public discovery/emission regressions |
| Lane-aware `VST1` behavior and FPSCR FZ comparison | **Implemented and verified** | Public CPU/emitter regressions |
| Exclusive monitor/write invalidation | **Implemented and verified** | Cross-thread framework runtime test |
| Strict source/target dispatch diagnostics | **Implemented and verified** | Exact diagnostic test; default remains aborting |
| Deterministic runtime-image ordering/overlap rejection | **Implemented and verified in the game manifest layer** | Synthetic and private repeat validation |
| Multi-image `armrecomp` report composition | **Implemented and publicly verified** | ABI-v4 descriptors preserve site-keyed function-import slots and add explicit TLS alignment; schema-v4 module evidence and deterministic registry/aggregate TLS layout composition |
| Strict conditional host entry | **Implemented and publicly verified; privately unclosed** | Retained bytes, strict loader/binder, stack/TLS/CPU preparation, and one-use guest-call tests; no private real-entry evidence |
| Full external-oracle state adapter | **Deferred and optional** | Not required by production or extraction |

The accepted private CPU repeat generated and compiled all three modules. Its
classified named traps keep `productionReady` false but are not structural
entry blockers; if reached, the first one must stop the guest call explicitly.
The historical repeat did not attempt real Gate 1 entry. “Generated
successfully” is not a bootability claim.

## Remaining retained fixtures

Most semantic cases that were initially recorded as deferred were promoted
into canonical executable tests during CPU/runtime and Gate 1 integration.
Retained non-production evidence still covers:

- any state items not represented by the production CPU ABI, including a
  future full external-oracle comparison surface; and
- instruction or transfer shapes still reported by the accepted private trap
  census.

These are explicit future integration points, not claims that a hidden hybrid
path can execute them. New behavior must land in the canonical framework with
public synthetic coverage.

## Rejected historical material

- the full modified Vita3K source tree;
- the complete C++ recompiler/runtime and Dynarmic fallback as production code;
- GUI and Android configuration unrelated to external extraction;
- private title inputs, generated blocks, traces, smoke logs, and addresses;
- the unrelated PS2Recomp backlog note; and
- the old hybrid-specific promotion queue as a project tracker.

Current architecture and ordered work now live in
[`../ARCHITECTURE.md`](../ARCHITECTURE.md) and
[`../ROADMAP.md`](../ROADMAP.md).
