# Current architecture

This document describes the accepted first-checkpoint architecture at game
revision `36fef0e94ab99d1fc6e1903f02a388013eb3585d` and framework revision
`f3408e1ea73b724c7ba3a644633938c220f2cc2a`. The framework revision is the
exact `third_party/vitarecomp` gitlink and the value in
`config/framework.commit`.

The checkpoint is a verified native foundation, not a title-boot or
playability milestone. Non-self-test title mode deliberately exits with code
9 before loading or calling generated Killzone code.

## Repository and process boundaries

| Boundary | Owns | Must not own |
|---|---|---|
| [`Tzeentchnet/vitarecomp`](https://github.com/Tzeentchnet/vitarecomp/tree/f3408e1ea73b724c7ba3a644633938c220f2cc2a) | Static ARM/Thumb analysis and generated-C emission; CPU/memory/dispatch runtime; title-neutral HLE and VFS; shared GPU C contract; DX12 and Vulkan backends; public tests | Killzone policy, private title content, generated Killzone source, or an embedded emulator |
| This game repository | PCSA00107 policy and configuration; native Windows host; strict content/manifest validation; external-content workflow; local generated-source staging; title-specific compatibility work | Retail data, keys, generated title code, Vita3K source/runtime, or a second production recompiler |
| External Vita3K checkout/process | Lawful installation/decryption, post-link runtime ELF extraction, and optional behavioral-oracle observations | Production CPU execution, native-host services, renderer fallback, or a runtime dependency |
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
policy, networking, and title-specific compatibility remain deferred even
though the underlying native renderer contract is implemented.

### Native host

The C++20 Windows x64 host owns process policy, strict CLI/config parsing,
manifest and ELF revalidation, redacted diagnostics, Win32 window lifecycle,
runtime/VFS creation, renderer selection, and deterministic teardown. A valid
external image set is mounted read-only as `app0:` only after path, range,
metadata, size, and hash checks pass.

The only successful execution mode at this checkpoint is the public
clear/triangle self-test. Valid title content without `--self-test` reaches
the explicit `title_not_implemented` boundary and exits 9.

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

## Status at the checkpoint

| Classification | Behavior |
|---|---|
| **Implemented** | Offline static CPU pipeline; standalone runtime/HLE foundation; read-only VFS; versioned GPU ABI; production DX12/Vulkan backends; Win32 host; content inspection, dump, and manifest tools; safety guards |
| **Verified** | Clean-clone quality/build matrix; 73/73 CTest executions; public homebrew E2E; deterministic private generation; three-module host validation/mount; DX12 WARP/hardware and validation-enabled Vulkan self-tests; explicit no-fallback negative paths |
| **Deferred** | Strict title entry; complete startup imports and title services; guest GXM; GXP/USSE; title-frame backend parity; audio/input/save/movie services; gameplay; performance work; local-only generated package assembly |
| **Intentionally out of scope** | PFS/key derivation or extraction; distributing private content/generated title code; embedded Vita3K or other emulator; runtime JIT/interpreter fallback; silent unsupported behavior; automatic renderer fallback |

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
- Title entry remains unreachable until every readiness gate in
  [`ROADMAP.md`](ROADMAP.md) is measured.

## Framework references

- [Pipeline architecture](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/ARCHITECTURE.md)
- [CPU baseline](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/CPU_BASELINE.md)
- [Runtime and HLE](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/HLE.md)
- [GPU contract and Vulkan](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/GPU.md)
- [Direct3D 12](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/DX12.md)
- [Provenance](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/PROVENANCE.md)
- [Framework quality gates](https://github.com/Tzeentchnet/vitarecomp/blob/f3408e1ea73b724c7ba3a644633938c220f2cc2a/docs/QUALITY_GATES.md)
