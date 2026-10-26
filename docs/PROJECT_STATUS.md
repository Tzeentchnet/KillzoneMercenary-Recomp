# Project status

Goal: *Killzone Mercenary*, statically recompiled, running natively on
Windows with DX12 and Vulkan at 30 fps or higher ([GOAL.md](GOAL.md)).

**Current milestone: M1, lift and link** ([ROADMAP.md](ROADMAP.md#m1--lift-and-link-decompile)).

| Milestone | State |
|---|---|
| M0 Foundation | ✅ Done (2026-10-25) |
| M1 Lift and link | ▶ In progress |
| M2 Into title code | Not started. The host still exits 9 (`title_not_implemented`) in title mode |
| M3–M7 | Not started |

The game does not boot yet. No translated Killzone code has been called.

## What exists today

| Area | State |
|---|---|
| Recompiler (`armrecomp`, framework) | All three post-link runtime images lift and compile with MSVC `/W4 /WX`. Coverage is 96.37% of executable bytes. 99.897% of emitted instructions are translated, with **3,770 explicit traps** left. Output is deterministic across runs |
| Linking | Generated C is compiled as objects only. **It is not yet linked into the host** (M1) |
| Runtime/HLE (framework) | Checked memory, ARM/VFP CPU state, baton scheduler, threads and sync, allocators, libc/libm, import registry, I/O/FIOS2 (synchronous), ULT sync subset, VFS/PSARC |
| GXM / GXP / USSE | Not started (M3). This is the largest single piece of work |
| Display, audio, input, movies, saves | Not started (M3–M4) |
| GPU contract and backends (framework) | Production DX12 and Vulkan backends behind one C ABI, with one HLSL source compiled by pinned DXC to DXIL and SPIR-V. Self-test verified on DX12 WARP, DX12 hardware, and Vulkan with validation |
| Windows host (this repository) | Strict CLI, manifest/ELF validation, read-only `app0:` mount, explicit renderer selection with no fallback, and a clear/triangle self-test |
| Content pipeline (this repository) | Archive inspector, isolated Vita3K post-link ELF dump through two patches, deterministic manifest generator, private-content guard |
| CI | Public, source-only Windows jobs: quality, plus Debug/RelWithDebInfo/Release build and test |

## Known blockers, in order

1. Generated code is not linked into the host, and there is no multi-image
   dispatch table (M1).
2. The trap census has not been triaged by boot-path reachability (M1).
3. The title memory map is a 64 MiB placeholder that does not cover the
   manifest load ranges (M2).
4. There is no boot sequence (module start order, main thread), and the
   import inventory has not been measured at run time (M2).
5. Guest `sceGxm`, `sceDisplay`, and the GXP/USSE shader translator are
   missing (M3).

Performance risks to watch, which are addressed in M6 if they bite:

- every guest memory access is a checked function call;
- indirect dispatch is a binary search; and
- the scheduler runs one guest thread at a time.

## Revisions

| Component | Revision |
|---|---|
| Framework pin (`third_party/vitarecomp`, `config/framework.commit`) | `f3408e1ea73b724c7ba3a644633938c220f2cc2a` |
| Upstream base (`sp00nznet/vitarecomp`) | `6ed4a5c59045706292c8ec03dfe5207ecc4033a4`, tagged `upstream-start-6ed4a5c5` in the fork. Upstream has no later commits |
| M0 accepted game revision | `36fef0e94ab99d1fc6e1903f02a388013eb3585d` |
| Vita3K base for the dump patches | `ee50eb8644b4184996047f04406486281586935b` |

## Log

Add one short entry per meaningful step: what now works, and the measured
number if there is one. Do not write separate verification reports.

- **2026-10-26:** Docs and plans refocused on the boot-to-30 fps goal. Added
  [GOAL.md](GOAL.md), rewrote the roadmap into game-facing milestones M0–M7,
  and added agent working rules in [`CLAUDE.md`](../CLAUDE.md).
- **2026-10-25:** M0 accepted. The full matrix and redacted private
  measurements are in [FOUNDATION_VERIFICATION.md](FOUNDATION_VERIFICATION.md)
  (historical record).

## Out of scope

- Key/PFS derivation or extraction, and distributing private content,
  generated code, or builds ([CONTENT_POLICY.md](CONTENT_POLICY.md)).
- A Vita3K fork, Vita3K features, or Vita3K inside the native process.
- Interpreter/JIT/emulator execution, silent success stubs, and automatic
  renderer fallback.
- Online play, PSN/NP, trophies.
