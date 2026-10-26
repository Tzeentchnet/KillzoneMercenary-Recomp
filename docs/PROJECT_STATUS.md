# Project status

Goal: *Killzone Mercenary*, statically recompiled, running natively on
Windows with DX12 and Vulkan at 30 fps or higher ([GOAL.md](GOAL.md)).

**Current milestones: M1 (lift and link) and M2 (into title code)**
([ROADMAP.md](ROADMAP.md)). The code path that builds a local generated
bundle into the host and enters it exists. Its first real-bundle attempt
now passes relocation preflight and binding, then calls translated title code.
The ordered three-module startup now parses and fully family-classifies the
first title vertex GXP, then stops strictly before semantic translation.

| Milestone | State |
|---|---|
| M0 Foundation | ✅ Done (2026-10-25) |
| M1 Lift and link | ▶ Build path done. Trap ranking and symbol map open |
| M2 Into title code | ▶ Ordered startup reaches the first title shader; no frame loop yet |
| M3 First frame | ◌ First vertex GXP fully family-classified; semantic translation and presentation remain |
| M4–M7 | Not started |

The game does not boot yet. All three translated modules start in retained
dependency order, but the strict run stops at vertex shader creation before a
frame loop.

## What exists today

| Area | State |
|---|---|
| Recompiler (`armrecomp`, framework) | All three post-link runtime images lift and compile with MSVC `/W4 /WX`. Coverage is 96.37% of executable bytes. 99.897% of emitted instructions are translated, with **3,770 explicit traps** left. Output is deterministic across runs |
| Linking | `armrecomp compose` builds one registry across modules. `KZMRECOMP_GENERATED_SOURCE_DIR` builds a provenance-validated local bundle into the host ([generated-source-provenance.md](generated-source-provenance.md)). Empty by default and in CI |
| Title entry | The title session loads and binds the retained module set, configures process/TLS/CPU state, and runs support-module starts followed by the entry module inside one strict `vita_guest_call` boundary. Exit 11 = preparation failure, 12 = first strict failure, 13 = exit request; 9 = no bundle ([NATIVE_HOST.md](NATIVE_HOST.md)) |
| Memory plan | Derived from validated load ranges, with 96 MiB main Sysmem, 128 MiB CDRAM, 16 MiB physically contiguous memory, and a 384 MiB maximum guest window |
| Runtime/HLE (framework) | Checked memory, ARM/VFP CPU state, baton scheduler, threads and sync, partitioned allocators, libc/libm, import registry, I/O/FIOS2 (synchronous), ULT sync subset, VFS/PSARC |
| GXM / GXP / USSE | Measured bridge covers initialization, memory/USSE maps, contexts, patcher registration, linear textures, GXP reflection, bounded primary/secondary instruction parsing, and all 35 public top-level USSE family matchers. The first title vertex GXP is fully family-classified: `VMAD` ×4 and one each of `PHAS`, `NOP`, `SPEC`, `V32NMAD`, and `VPCK`; there are no unknown or illegal encodings. No semantic decoder, shader object, translator, or scene/draw path exists yet |
| Display, audio, input, movies, saves | Not started (M3–M4) |
| GPU contract and backends (framework) | Production DX12 and Vulkan backends behind one C ABI, with one HLSL source compiled by pinned DXC to DXIL and SPIR-V. Self-test verified on DX12 WARP, DX12 hardware, and Vulkan with validation |
| Windows host (this repository) | Strict CLI, manifest/ELF validation, read-only `app0:` mount, explicit renderer selection with no fallback, clear/triangle self-test, title session |
| Content pipeline (this repository) | Archive inspector, isolated post-link ELF extraction, deterministic identity normalization with validated variable-target preservation, manifest generator, provenance tools, private-content guard |
| CI | Public, source-only Windows jobs: quality, plus Debug/RelWithDebInfo/Release build and test |

## Known blockers, in order

1. The six measured USSE families need typed semantic decoding and HLSL
   translation; top-level family classification alone cannot create a shader
   object without host-executable output (M3).
2. The strict run has not reached 60 display flips or `sceGxmBeginScene`
   iterations, so M2 remains open.
3. The trap census has not been ranked by boot-path reachability, and
   there is no symbol map for naming failures (M1).
4. Remaining guest `sceGxm`, `sceDisplay`, scene/draw, and presentation work
   is still missing (M2–M3).

Performance risks to watch, which are addressed in M6 if they bite:

- every guest memory access is a checked function call;
- indirect dispatch is a binary search; and
- the scheduler runs one guest thread at a time.

## Title-entry validation

The public, synthetic test selections for the title-entry path (the work
earlier docs call "Gate 1") passed 6/6 (framework) and 5/5 (game/host) on
2026-10-25:

```powershell
ctest --test-dir out\build\vitarecomp-public-debug -C Debug `
  --output-on-failure `
  -R "^(emit|compose-generated-image-set|runtime|entry-state|loader-strict|module-set-binding)$"

ctest --test-dir out\build\windows-x64-debug -C Debug `
  --output-on-failure `
  -R ("^(generated-provenance-synthetic|" +
      "generated-bundle-build-synthetic|" +
      "generated-bundle-adapter-unit|title-session-unit|" +
      "native-host-unit)$")
```

They cover composition, structural blockers, provenance and staging
failures, retained bytes, every preparation stage (zero entry calls on
failure), one-use entry, clean return, explicit exit, and first strict
failure. All inputs were public or synthetic.

## Revisions

| Component | Revision |
|---|---|
| Framework pin (`third_party/vitarecomp`, `config/framework.commit`) | `95c9bd8bd296c5bae5d5d82a72742d7a7d2a7779`: complete top-level USSE family classification, explicit unknown/illegal separation, and safe aggregate shader diagnostics. Windows quality and 24/24 CTests pass |
| M0 framework pin | `f3408e1ea73b724c7ba3a644633938c220f2cc2a` |
| Upstream base (`sp00nznet/vitarecomp`) | `6ed4a5c59045706292c8ec03dfe5207ecc4033a4`, tagged `upstream-start-6ed4a5c5` in the fork. Upstream has no later commits |
| M0 accepted game revision | `36fef0e94ab99d1fc6e1903f02a388013eb3585d` |
| Vita3K base for the dump patches | `ee50eb8644b4184996047f04406486281586935b` |

## Log

Add one short entry per meaningful step: what now works, and the measured
number if there is one. Do not write separate verification reports.

- **2026-10-26:** The complete public top-level USSE classifier identifies all
  9 instructions in the first title vertex GXP: `VMAD` ×4 and one each of
  `PHAS`, `NOP`, `SPEC`, `V32NMAD`, and `VPCK`, with 0 unknown and 0 illegal.
  The strict DX12 WARP run exits 12 at semantic translation without allocating
  a shader object; framework quality and 24/24 CTests pass.
- **2026-10-26:** The first title vertex GXP now reaches a bounded,
  title-neutral USSE census: 9 instructions total, 1 classified `PHAS`, 8
  unknown, first unknown at primary instruction 1. Vertex creation exits 12
  without allocating or returning a shader object; framework quality and
  24/24 CTests pass.
- **2026-10-26:** Ordered startup of all three translated modules now reaches
  `sceGxmShaderPatcherCreateVertexProgram` under strict DX12 WARP after
  partitioned Sysmem and the measured GXM/GXP reflection path. Framework
  quality and 22/22 CTests pass; no frame loop or shader translation is
  claimed.
- **2026-10-26:** Regenerated the preserved three-module bundle with the pinned
  public VitaSDK 3.60 NID database. The prior raw-NID stop resolved to the
  existing `SceLibc::__cxa_set_dso_handle_main` HLE, and three consecutive
  DX12 WARP title runs returned 0 after one selected entry call. No frame loop
  is claimed; dependency-ordered supporting-module starts are next.
- **2026-10-26:** The preserved three-module DX12 bundle completed relocation
  preflight and strict binding, prepared the main stack, called translated
  title entry once, and exited 12 at `nid_BE43BB07::nid_BFE02B3A` from
  `0x818C37A8`. Unresolved variable storage remains named and strict-on-access;
  no dead-beef success stub or emulator fallback was introduced.
- **2026-10-26:** The first provenance-validated three-module real-bundle
  DX12 title attempt validated 3 modules and 6 segments, initialized the
  runtime and read-only mount, then exited 11 at `module_preflight`
  (status -29, module index 0, record index 6, zero entry calls). The
  relocation verifier found 858/9,429 records non-identity, first at record
  6; no instruction, transfer, or import strict failure was reached.
- **2026-10-26:** Merged `main`'s strict title-entry work into the refocused
  docs. The roadmap now ticks the generated-bundle build, the memory plan
  from load ranges, and the host's load → bind → prepare →
  `vita_guest_call` path. The first real-bundle run is the next step.
- **2026-10-26:** Wrote two framework fixes that could not be pushed to the
  fork from this session (no GitHub access), so they are parked in
  [`patches/vitarecomp`](../patches/vitarecomp/README.md). One makes the
  build warnings-clean on Linux clang/GCC (19/19 tests), and it also fixes
  NID names over 63 bytes being truncated into wrong HLE symbols, and
  silent FIOS path truncation. The other fixes the Windows quality gate's
  `git-clang-format.bat` failure.
- **2026-10-26:** Docs and plans refocused on the boot-to-30 fps goal. Added
  [GOAL.md](GOAL.md), rewrote the roadmap into game-facing milestones M0–M7,
  and added agent working rules in [`CLAUDE.md`](../CLAUDE.md).
- **2026-10-25:** Strict title-entry path implemented (framework `0e81bb4`,
  game `17046af`), with public synthetic coverage.
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
