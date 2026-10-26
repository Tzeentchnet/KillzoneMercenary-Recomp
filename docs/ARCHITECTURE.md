# Current architecture

This document is rooted in the accepted first-checkpoint architecture at game
revision `36fef0e94ab99d1fc6e1903f02a388013eb3585d` and framework revision
`f3408e1ea73b724c7ba3a644633938c220f2cc2a`. The current framework revision is
`0e81bb4b275435b2396b01a88c8d767d0104cc8b`, which is the exact
`third_party/vitarecomp` gitlink and the value in `config/framework.commit`.
It also records the subsequent strict host-entry wiring.

**Gate 1 status: implemented and publicly/synthetically verified; privately
unclosed.** This remains a native foundation, not a title-boot or playability
milestone. Public builds have no generated bundle and deliberately exit 9. An
opt-in validated local bundle can enter only through the fail-closed
preparation and guest-call boundary below. No ignored local status file records
a successful private real-entry attempt.

## Repository and process boundaries

| Boundary | Owns | Must not own |
|---|---|---|
| [`Tzeentchnet/vitarecomp`](https://github.com/Tzeentchnet/vitarecomp/tree/0e81bb4b275435b2396b01a88c8d767d0104cc8b) | Static ARM/Thumb analysis and generated-C emission; CPU/memory/dispatch runtime; title-neutral HLE and VFS; shared GPU C contract; DX12 and Vulkan backends; public tests | Killzone policy, private title content, generated Killzone source, or an embedded emulator |
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
  -> armrecomp emit + compose (ignored local generated C and reports)
  -> local provenance validation and content-aware ignored staging
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

Generated-module ABI v4 starts every descriptor with `abi_version` and
`struct_size`, then carries its stable module identity, complete dispatch,
raw entry address plus normalized Thumb dispatch key, TLS, site-keyed function
imports with writable direct-call targets, import/export variables, and a
schema-v4 report summary. TLS-bearing descriptors carry explicit power-of-two
alignment.
TLS-variable import tables remain unsupported and are rejected by both
generation and host preflight. They are never silently omitted from the strict
metadata contract.
The compose command consumes exactly one sidecar/report pair per module, sorts
the set deterministically, and emits a registry plus schema-v4 aggregate
reports with TLS descriptor index/order, aligned offset, and aggregate
size/alignment:

```powershell
armrecomp compose --entry-module <id> --output <registry.c> `
  <module/report JSON>...
```

Aggregate structural readiness and entry eligibility require complete
metadata, resolved entry/TLS records, function-entry and PC instrumentation,
and no body cuts, unreported partitions, or unclassified traps. Fully
classified named traps keep production readiness false but remain eligible to
become the first strict runtime stop. The local provenance validator enforces
that policy before staging or compilation.

The accepted private three-image baseline generated 809 byte-identical files
across two runs; all 800 generated C translation units compiled with MSVC
warnings as errors. Its 3,770 explicit trapped instruction instances remain a
readiness signal. They are historical generation evidence, not private Gate 1
entry evidence. If a configured entry reaches one, the first named trap stops
the guest call and is reported as a strict failure.

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

For title preparation, validated load ranges feed an explicit bounded-window
policy in `src/game/title_config.*`. The deterministic plan places disjoint
heap, sysmem, kernel, main-stack, and TLS arenas after the load set and rejects
overlap, alignment, address-overflow, and maximum-window violations. The
framework receives the planned TLS range as a dedicated allocator arena;
main and worker TLS blocks never fall back to the kernel arena. The public
renderer self-test continues to use its fixed synthetic scaffold, so
title-derived addresses cannot change that test contract.

Validation retains every ordered module's metadata and immutable bytes from
the same locked handle used for hashing. A configured bundle must agree with
the raw-manifest identity and then pass strict in-memory module-set
preflight/load, relocation and module-table extension checks, generated
descriptor/global-dispatch agreement, complete binding, stack, TLS, and CPU
state preparation. The full order is content identity, memory layout, runtime
initialization, content mount, module preflight, transactional module load,
descriptor/dispatch agreement, complete binding, stack, TLS template
preparation, CPU state, and checked main-thread TLS materialization.
Only the resulting move-only capability can issue one `vita_guest_call`.

That boundary reports clean return as exit 0, a preparation or boundary
failure as exit 11, the first strict failure as exit 12, and an explicit guest
exit request as exit 13. No-bundle title mode still mounts read-only and exits
9. Since strict loading consumes the retained buffers and never reopens module
paths, there is no validation-to-load path race.

The relocation extension delegates to the framework's shared PT_SCE_RELA
decoder. Preflight accepts the relocation bit only after every record decodes,
every patch is supported and inside declared file bytes, and applying the
identity-load relocation would change no byte. It never repairs the retained
image. Static ET_SCE_EXEC modules need no relocation stream.

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
| **Implemented** | Offline static CPU pipeline; versioned generated-module ABI/composition and local provenance; standalone runtime/HLE foundation; read-only VFS; strict conditional title preparation/entry; versioned GPU ABI; production DX12/Vulkan backends; Win32 host; content inspection, dump, and manifest tools; safety guards |
| **Verified** | Historical clean-clone foundation matrix; public homebrew E2E; deterministic private generation; public/synthetic ABI composition, provenance, retained-content, preparation, and generated-bundle outcome tests; DX12 WARP/hardware and validation-enabled Vulkan self-tests; explicit no-fallback negative paths |
| **Deferred** | Complete startup imports and title services; guest GXM; GXP/USSE; title-frame backend parity; audio/input/save/movie services; gameplay; performance work; local-only package assembly |
| **Intentionally out of scope** | PFS/key derivation or extraction; distributing private content/generated title code; embedded Vita3K or other emulator; runtime JIT/interpreter fallback; silent unsupported behavior; automatic renderer fallback |

## Test and CI layers

1. **Framework unit/contract tests:** container, decoder, discovery, emitter,
   composition, strict loader/binder, entry state, CPU/runtime/HLE, strict
   dispatch, C GPU ABI, and backend contracts.
2. **Public end-to-end fixtures:** three reviewed homebrew modules are
   extracted, emitted twice, byte-compared, and compiled.
3. **Game synthetic tests:** CLI, manifest, redaction, content pipeline,
   generated staging/bundle provenance, retained bytes, strict title entry,
   guards, VFS, and failure paths.
4. **Renderer integration:** DX12 WARP is required; hardware DX12 and
   validation-enabled Vulkan run when available; invalid selections must fail
   without fallback.
5. **Private foundation acceptance:** only ignored local inputs/outputs were
   used and public reporting is aggregate/redacted. No private Gate 1
   real-entry acceptance is recorded.
6. **Hosted CI:** public-source-only quality plus Debug/RelWithDebInfo/Release
   game builds and Debug/Release framework builds. The generated-source cache
   path stays empty; CI receives no private bundle.

Historical accepted evidence is in
[`FOUNDATION_VERIFICATION.md`](FOUNDATION_VERIFICATION.md). Current Gate 1
public commands and results are in
[`PROJECT_STATUS.md`](PROJECT_STATUS.md#gate-1-public-synthetic-validation).
The historical public runs are framework
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
- A generated title entry remains unreachable unless every host preparation
  gate succeeds; later title/HLE/GPU gates in [`ROADMAP.md`](ROADMAP.md) do
  not gain success-shaped fallbacks.

## Framework references

- [Pipeline architecture](../third_party/vitarecomp/docs/ARCHITECTURE.md)
- [CPU baseline](../third_party/vitarecomp/docs/CPU_BASELINE.md)
- [Runtime and HLE](../third_party/vitarecomp/docs/HLE.md)
- [Entry state](../third_party/vitarecomp/docs/ENTRY_STATE.md)
- [GPU contract and Vulkan](../third_party/vitarecomp/docs/GPU.md)
- [Direct3D 12](../third_party/vitarecomp/docs/DX12.md)
- [Provenance](../third_party/vitarecomp/docs/PROVENANCE.md)
- [Framework quality gates](../third_party/vitarecomp/docs/QUALITY_GATES.md)
