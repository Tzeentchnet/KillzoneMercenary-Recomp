# Project Status and Handoff

Checkpoint: 2026-10-25

## Current boundary

The canonical CPU, standalone runtime/HLE, DX12, and Vulkan work is merged on
framework `main` at `8bf490e`. This game repository now contains the native
Windows x64 host scaffold and framework conformance path.

Do not infer title bootability or playability from this checkpoint. Valid
external content is checked and mounted read-only, but translated Killzone
code is neither loaded nor executed. Non-self-test title mode exits through a
documented `not implemented` path until generated-code provenance, strict
import coverage, and title HLE/GXM preconditions are measurable.

## Repository state

### Framework

- Repository: `D:\Github\vitarecomp`
- Remote: `Tzeentchnet/vitarecomp`
- Mainline: `8bf490e` (`Merge runtime foundation`)
- Upstream pin: `6ed4a5c`
- Mainline is clean, pushed, and synchronized with `origin/main`.
- License: GPL-2.0-or-later for the combined derivative, with upstream MIT
  license and provenance retained.

Historical renderer branches merged into current main:

| Purpose | Commit | State |
|---|---|---|
| DX12 backend | `a19d340` | Complete in isolated branch |
| Vulkan backend | `d2e0c8b` | Complete in isolated branch |
| Combined renderers | `b1754cd` | Merged and validated |

The renderer branches were rebased through the canonical CPU work and merged
with the standalone runtime foundation. The game submodule is pinned to exact
commit `8bf490e6702eae69d07a74dd9397c1e32e7a6dbc`.

### Game project

- Repository: `D:\Github\KillzoneMercenary-Recomp`
- Remote: `Tzeentchnet/KillzoneMercenary-Recomp`
- The public `main` branch contains the source-only foundation and native host
  checkpoint.
- Content pipeline, research migration, Vita3K patch series, staging tools,
  host sources, tests, and documentation are preserved together.
- `third_party/vitarecomp` is pinned to `8bf490e`.

### Preserved prior work

The previous dirty Vita3K/AOT branch was captured as a private-free session
artifact without modifying its source repository. The snapshot contains six
committed patches, three dirty-state patches, metadata, checksums, path
classification, and the 45 reusable changed files. Private game data,
generated title sources, traces, keys, and build output were excluded.

## Completed work

### Repository and provenance foundation

- Forked `sp00nznet/vitarecomp` to `Tzeentchnet/vitarecomp`.
- Preserved `origin`, `upstream`, and comparison remotes.
- Added combined-work licensing, notices, provenance, and an upstream start
  tag.
- Initialized the separate game repository and framework submodule.
- Added Windows x64 CMake presets, content policy, ignore rules, and a staged
  private-content guard.

### Prior-material migration

- Curated verified findings, architecture handoff, and asset-format research.
- Migrated content-aware generated-source staging with synthetic tests.
- Added a minimal two-patch Vita3K series for post-link ELF dumping.
- Converted broadly reusable AOT findings into canonical runtime tests and 17
  machine-readable semantic vectors.
- Explicitly rejected the duplicate production C++ recompiler, complete
  Vita3K vendoring, stale TODOs, private artifacts, and unrelated PS2 notes.

### Retail content pipeline

- Added read-only NoNpDRM ZIP inspection without extraction.
- Added external Vita3K install/dump orchestration with no key handling.
- Added ELF32/ARM segment, overlap, hash, and deterministic manifest
  validation.
- Added public configuration schema/examples and synthetic tests.
- Verified the supplied PCSA00107 archive:
  - 3,230,395,399 bytes;
  - 866 entries;
  - five packaged executable modules;
  - correctly classified as protected retail PFS/NoNpDRM.
- Completed a fresh isolated Vita3K dump:
  - three stable ELF32/ARM runtime modules;
  - deterministic manifest;
  - byte-identical repeat validation;
  - only the exact spawned Vita3K PID was stopped.

### Downstream audit and CPU selection

- Audited 29 Shiz0id commits and 94 soyjxck commits against upstream.
- Reproduced:
  - Shiz0id default tests: 4/4;
  - soyjxck default/OpenGL tests: 15/15;
  - all three public soyjxck end-to-end fixtures.
- Measured upstream, soyjxck, Shiz0id, and the prior local analyzer against the
  same private Killzone runtime image set.
- Selected upstream's generated-C/runtime ABI with coherent soyjxck CPU topics
  as the canonical production path.
- Integrated:
  - retail ELF and SCE relocation handling;
  - ARM/Thumb mode keys;
  - corrected discovery and target promotion;
  - jump tables and MOVW/MOVT pointer recovery;
  - NEON/VFP and checked/exclusive memory helpers;
  - partitioned generation;
  - strict traps and deterministic reports; and
  - prior semantic regressions.

### Renderer foundation

- Added a versioned, opaque-handle C GPU ABI and C++20 internals.
- Added strict lifecycle, resource-state, command-order, fence, resize, error,
  and shader-request tests.
- Pinned DXC `1.8.2505.32` and defined one HLSL path to DXIL and SPIR-V.
- Implemented real production DX12 and Vulkan backends.
- Combined them in one validated integration branch with explicit no-fallback
  behavior.

### Native Windows host

- Added a C++20 Windows x64 GUI-subsystem host with inherited/CLI console
  handling and non-interactive failure reporting.
- Linked only the pinned standalone runtime and renderer-neutral GPU targets;
  there is no Vita3K runtime dependency or JIT.
- Added strict CLI/config parsing for explicit content, manifest, renderer,
  adapter, validation, logging, self-test frames, and help.
- Added independent runtime-manifest/ELF/range/hash validation with path,
  symlink/reparse, traversal, protected-input, title-ID, and overlap rejection.
- Mounted validated external content as read-only `app0:` and verified both
  traversal and write denial through the framework VFS.
- Added structured redacted logging and documented actionable exit codes.
- Added explicit backend/adapter selection with no fallback, Win32
  minimize/restore/resize handling, deterministic GPU/runtime/window teardown,
  and final clear/triangle readback validation.
- Kept title execution disabled with no generated-code load and no
  success-shaped title stub.

## Validation evidence

### Framework mainline (`8bf490e`)

- MSVC with `/W4 /WX /permissive- /bigobj`.
- Canonical CPU, runtime/HLE, DX12, and Vulkan histories merged.
- Complete framework CTest: 17/17 passed at the framework checkpoint.
- Three public homebrew end-to-end fixtures passed.
- All three private runtime modules generated and compiled.
- Repeat generation: 809 files byte-identical.
- Measured byte coverage: 96.370751%.
- Measured translation yield: 99.897187%.
- Explicit traps: 3,770.
- Generated partitions: 37.

### Combined renderer branch (`b1754cd`)

- MSVC Debug build passed with warnings as errors.
- CTest: 12/12 passed.
- DX12 WARP and NVIDIA hardware conformance passed through three
  resize/startup/shutdown iterations with stable hashes.
- Vulkan validation-enabled conformance passed on an NVIDIA RTX 5070 through
  two complete resize/recreate cycles.
- Invalid Vulkan ICD returned the explicit unavailable/skip path without
  falling back to DX12.
- Mismatched DXC version was rejected.
- D3D12 Graphics Tools/debug layer was not installed; that unavailability was
  reported explicitly rather than silently ignored.

### Game repository

- CMake configure/build passed for Debug, RelWithDebInfo, and Release with
  MSVC warnings as errors.
- CTest: 12/12 passed in all three configurations.
- DX12 WARP and available hardware host self-tests passed.
- Validation-enabled Vulkan host self-test passed.
- Explicit unavailable adapter and invalid-Vulkan-ICD no-fallback tests passed.
- Synthetic manifest/content integration rejected changed hashes, traversal,
  overlapping ranges, wrong title ID, and protected/not-ready images.
- The existing private three-module manifest independently validated, mounted
  read-only, and completed the DX12 WARP host self-test without emitting a
  private path or hash.
- Win32 resize/lifecycle and three repeated WARP startup/shutdown runs passed.
- Content pipeline synthetic suite: nine cases under PowerShell 7 and Windows
  PowerShell 5.1.
- Generated-source staging regression passed.
- Private-content guard passed.
- Vita3K patches apply sequentially to their pinned base.

## Ordered next steps

### 1. Define strict title-execution readiness

1. Add a generated-source provenance manifest without tracking generated code.
2. Derive and register the complete reachable import set with unsupported
   imports returning explicit failures.
3. Define module load/relocation/TLS/entry preconditions and test each with
   synthetic public fixtures.
4. Keep the current `title_not_implemented` exit until every gate passes.

### 2. Bring up title services incrementally

1. Establish measured module loading, imports, threading, and filesystem
   behavior.
2. Capture and reproduce GXM scenes through the renderer-neutral contract.
3. Integrate GXP/USSE translation through the common pinned-DXC path.
4. Add input, audio, movies, saves, and remaining services only with explicit
   unsupported results and focused tests.

### 3. Add quality gates and keep the foundation reproducible

1. Add Windows CI for framework and game repositories.
2. Build both renderers and all generated-C/public fixtures.
3. Run formatting, static analysis, warnings-as-errors, and content guards.
4. Keep GPU-dependent tests explicit about hardware/ICD availability.
5. Complete the clean-clone acceptance matrix before beginning GXM/title
   bring-up.

## Deferred title bring-up

Gameplay progression, DX12/Vulkan title-frame parity, and user-facing title
services remain deferred. They retain the strict no-JIT/no-emulator and
source-only content boundaries described above.
