# Architecture

This document describes how the native *Killzone Mercenary* build is put
together: what exists at the framework pin
`f3408e1ea73b724c7ba3a644633938c220f2cc2a`, and where the remaining pieces
go on the way to the goal in [GOAL.md](GOAL.md). Milestone order is in
[ROADMAP.md](ROADMAP.md).

At M0, title mode deliberately exits with code 9 before calling generated
code. M2 replaces that boundary with the real boot sequence.

## Repository and process boundaries

| Boundary | Owns | Must not own |
|---|---|---|
| [`Tzeentchnet/vitarecomp`](https://github.com/Tzeentchnet/vitarecomp/tree/f3408e1ea73b724c7ba3a644633938c220f2cc2a) (fork of [`sp00nznet/vitarecomp`](https://github.com/sp00nznet/vitarecomp)) | Static ARM/Thumb analysis and generated-C emission; CPU/memory/dispatch runtime; title-neutral HLE and VFS; shared GPU C contract; DX12 and Vulkan backends; public tests | Killzone policy, private title content, generated Killzone source, or an embedded emulator |
| This game repository | PCSA00107 policy and configuration; native Windows host; strict content/manifest validation; external-content workflow; local generated-source staging; title-specific compatibility work | Retail data, keys, generated title code, Vita3K source/runtime, or a second production recompiler |
| External Vita3K checkout/process | Lawful installation/decryption, post-link runtime ELF extraction, behavioral-oracle observations (screenshots, import logs), and source reading as reference | Production CPU execution, native-host services, renderer fallback, a runtime dependency, or project feature work (no fork) |
| Ignored local private roots | User-supplied archive, portable Vita3K state, runtime images, manifests, reports, captures, and generated code | Git history, hosted CI, published source archives, or shared build artifacts |

Vita3K is therefore an extraction/oracle tool only. The native application
does not link it, launch it, or fall back to it.

## Execution pipeline

```text
lawfully obtained archive
  -> external patched Vita3K, run separately
  -> private post-link ELF32/ARM runtime images
  -> independent deterministic manifest validation
  -> armrecomp static discovery and generated C (ignored local output)
  -> native compiler and standalone vitarecomp runtime/HLE
  -> game-owned Win32 host
  -> shared GPU contract
  -> explicitly selected DX12 or Vulkan backend
```

### Static generated-C CPU

`armrecomp` is an offline tool. It discovers mode-bearing ARM/Thumb code,
applies the supported Vita relocation model, emits bounded deterministic C
partitions, and produces explicit unsupported/trap reports. The production
host has no interpreter, JIT, Dynarmic, or emulator fallback.

The accepted private three-image baseline generated 809 byte-identical files
across two runs; all 800 generated C translation units compiled with MSVC
warnings as errors. Its 3,770 explicit trapped instruction instances remain a
readiness signal. They are not permission to enter title code.

### Standalone runtime and HLE

The framework runtime owns checked guest memory, mode-aware dispatch, CPU/TLS
state, deterministic scheduling and synchronization, allocators, import
registration, libc/libm, title-neutral kernel/I/O/FIOS2/ULT subsets, and
read-only VFS/PSARC behavior. Unsupported imports return a named error or trap;
they never return success merely to continue execution.

The guest `sceGxm` bridge, GXP/USSE translation, media, input, savedata UI and
policy, and title-specific compatibility are not implemented yet (M3–M5).
Networking only needs to report "offline" correctly.

### Native host

The C++20 Windows x64 host owns process policy, strict CLI/config parsing,
manifest and ELF revalidation, redacted diagnostics, Win32 window lifecycle,
runtime/VFS creation, renderer selection, and deterministic teardown. A valid
external image set is mounted read-only as `app0:` only after path, range,
metadata, size, and hash checks pass.

At M0 the only successful execution mode is the public clear/triangle
self-test. Valid title content without `--self-test` reaches the explicit
`title_not_implemented` boundary and exits 9 until M2.

### Shared GPU contract

The framework exposes a versioned C ABI with opaque typed handles, explicit
ownership, resource states, queue transitions, command ordering, fences,
swapchain lifecycle, structured errors, and one canonical HLSL shader path.
The production implementations are Direct3D 12 and Vulkan. The requested
backend, adapter, and validation mode are policy decisions; an unavailable or
invalid request fails and never selects another backend.

DXC `1.8.2505.32` is pinned. The same source is compiled to DXIL and SPIR-V.
DX12 WARP is the required software conformance path. Vulkan requires an
available 1.3 loader/ICD and reports absence explicitly.

## Target runtime design

These are the pieces still to be built, and where each one goes.

```text
generated C (all modules, one dispatch table)
  -> vitarecomp runtime: memory, CPU state, scheduler, HLE registry
       |-- kernel / threads / sync / sysmem / io / fios2 / ult   (exists, grows run-driven)
       |-- sceGxm bridge -> scene/draw translation -> GPU contract     (M3)
       |       '-- GXP parse + reflect -> USSE -> HLSL -> DXC -> DXIL/SPIR-V
       |-- sceDisplay -> swapchain present, vblank pacing              (M3)
       |-- sceCtrl / sceTouch / sceMotion -> host input                (M4)
       |-- sceAudioOut / sceNgs / ATRAC9 -> WASAPI                     (M4)
       |-- sceAvPlayer -> Media Foundation                             (M4)
       '-- savedata / appmgr / dialogs -> user-data directory          (M4)
  -> game host: boot order, memory map, settings, title hooks
  -> DX12 or Vulkan backend (explicit, no fallback)
```

Design points that the 30 fps target depends on (M6, prepared from M2):

- **Guest memory:** move from a checked call per access to one reserved host
  region addressed as base plus guest offset, with guard pages. Checked
  accessors stay at HLE boundaries and in debug builds.
- **Dispatch:** an O(1) indirect-target lookup over the combined
  multi-module table, and direct calls for static targets.
- **Threads:** the current baton scheduler runs one guest thread at a time.
  Keep it while the frame budget allows; run guest threads on host threads
  in parallel only when measurement requires it.
- **GPU:** guest surfaces and textures live in guest memory and go through
  a cache with explicit invalidation. Shaders are translated once and kept
  in a persistent local cache, with pipeline caches on both backends.
  PVRTC is decoded or transcoded because desktop GPUs lack it.
- **Pacing:** `sceDisplay` flips map to present with vblank-equivalent
  timing, so game logic sees the cadence it expects.

## Status at the M0 checkpoint

| Classification | Behavior |
|---|---|
| **Implemented** | Offline static CPU pipeline; standalone runtime/HLE foundation; read-only VFS; versioned GPU ABI; production DX12/Vulkan backends; Win32 host; content inspection, dump, and manifest tools; safety guards |
| **Verified** | Clean-clone quality/build matrix; 73/73 CTest executions; public homebrew E2E; deterministic private generation; three-module host validation/mount; DX12 WARP/hardware and validation-enabled Vulkan self-tests; explicit no-fallback negative paths |
| **Next (M1–M7)** | Linking generated code; title entry; startup imports; guest GXM; GXP/USSE; title frames on both backends; audio/input/save/movie; gameplay; 30 fps performance; one-command local build |
| **Intentionally out of scope** | PFS/key derivation or extraction; distributing private content/generated title code; embedded Vita3K or other emulator; a Vita3K fork or Vita3K feature work; runtime JIT/interpreter fallback; silent unsupported behavior; automatic renderer fallback; online play |

## Test and CI layers

1. **Framework unit/contract tests:** container, decoder, discovery, emitter,
   CPU/runtime/HLE, strict dispatch, C GPU ABI, and backend contracts.
2. **Public end-to-end fixtures:** three reviewed homebrew modules are
   extracted, emitted twice, byte-compared, and compiled.
3. **Game synthetic tests:** CLI, manifest, redaction, content pipeline,
   generated staging, guards, VFS, title boundary, and failure paths.
4. **Renderer integration:** DX12 WARP is required; hardware DX12 and
   validation-enabled Vulkan run when available; invalid selections must fail
   without fallback.
5. **Private acceptance:** only ignored local inputs/outputs are used; public
   reporting is aggregate and redacted.
6. **Hosted CI:** public-source-only quality plus Debug/RelWithDebInfo/Release
   game builds and Debug/Release framework builds.

The accepted evidence is in
[`FOUNDATION_VERIFICATION.md`](FOUNDATION_VERIFICATION.md). The corresponding
public runs are framework
[40185631954](https://github.com/Tzeentchnet/vitarecomp/actions/runs/40185631954),
game foundation
[40186098886](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40186098886),
and game report
[40189417323](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40189417323).

## Error and fallback policy

- Invalid input, unsupported CPU/HLE behavior, missing imports, bad guest
  memory, and missing dispatch targets fail explicitly.
- Private paths and hashes are redacted, but the operation still fails with an
  actionable category and exit code.
- A requested renderer, adapter, or validation layer is never substituted.
- GPU contract operations that are not implemented return
  `VITA_GPU_ERROR_UNSUPPORTED`; they do not report success.
- During bring-up, an import may be a *named stub*: registered, logged on
  first call, and listed as `stubbed` in the import inventory. A silent
  success is never allowed. See the [roadmap working rules](ROADMAP.md#working-rules).

## Framework references

- [Pipeline architecture](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/ARCHITECTURE.md)
- [CPU baseline](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/CPU_BASELINE.md)
- [Runtime and HLE](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/HLE.md)
- [GPU contract and Vulkan](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/GPU.md)
- [Direct3D 12](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/DX12.md)
- [Provenance](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/PROVENANCE.md)
- [Framework quality gates](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/QUALITY_GATES.md)
