# Project status and handoff

Foundation checkpoint accepted: 2026-10-25

Gate 1 status: **implemented and publicly/synthetically verified; privately
unclosed**

This remains a native foundation, not a title-boot or playability claim.
Public builds contain no generated bundle, so non-self-test title mode emits
`title_not_implemented` and exits 9. An opt-in provenance-validated local
bundle is now gated by strict retained-byte loading, binding, descriptor,
stack, TLS, and CPU preparation before exactly one guest entry call.
No ignored local status file records a successful private real-entry attempt.

## Revision record

| Component | Accepted revision | State |
|---|---|---|
| Framework `Tzeentchnet/vitarecomp` | `0e81bb4b275435b2396b01a88c8d767d0104cc8b` | Local Gate 1 commit; push and framework CI pending |
| Game verification report | `36fef0e94ab99d1fc6e1903f02a388013eb3585d` | `main`, clean, pushed, game CI green |
| Game framework gitlink | `0e81bb4b275435b2396b01a88c8d767d0104cc8b` | Matches `config/framework.commit` |
| Preserved upstream framework baseline | `6ed4a5c59045706292c8ec03dfe5207ecc4033a4` | Tagged `upstream-start-6ed4a5c5` |

The report commit follows the independently tested game target
`5b013f5967e68acfdf89573ffcaeb1a13aa76029`; it changes only
[`FOUNDATION_VERIFICATION.md`](FOUNDATION_VERIFICATION.md). Run
[40189417323](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40189417323)
then passed the complete game workflow on the report head.

The framework retains the upstream MIT license and provenance while the
modified combined work is distributed under GPL-2.0-or-later. The game
repository remains GPL-2.0-or-later. `LICENSE`, `NOTICE`, framework
`LICENSES/`, and provenance records remain authoritative.

## Meaning of status terms

- **Implemented:** production source and public contract tests exist at the
  accepted revisions.
- **Verified:** the behavior passed the clean-clone matrix or the separately
  described redacted private acceptance.
- **Deferred:** it is ordered in [`ROADMAP.md`](ROADMAP.md) but is not a
  capability claim.
- **Intentionally out of scope:** the architecture forbids it; it is not a
  future fallback plan.

## Implemented

### Strict host-entry convergence

- Generated-module ABI v4 exposes size/version-first descriptors, complete
  ARM/Thumb dispatch, raw-entry/normalized-key/TLS/import/export metadata,
  site-keyed writable function-import targets, explicit TLS alignment, and
  schema-v4 report summaries. `armrecomp compose` deterministically emits the
  registry and schema-v4 aggregate report, including checked TLS
  order/offsets, for an explicitly selected entry module.
- Entry policy v1 permits fully classified named traps only as a possible first
  strict stop. Body cuts, unreported partitions, unclassified traps, incomplete
  metadata, missing function-entry or PC instrumentation, and
  unresolved/ambiguous entry records are structural blockers rejected before
  entry.
- Every deterministic manifest module retains immutable bytes and complete
  loader metadata from its no-write/no-delete-share validation handle; the
  strict loader never reopens a module path.
- Runtime-manifest identity, layout, strict module-set load/extension checks,
  generated descriptors/dispatch, exports/imports/variables, stack, TLS
  template preparation and main-thread materialization, and CPU state all
  precede construction of a move-only prepared capability.
- Unsupported TLS-variable import tables are rejected during generation and
  independently during host preflight; they are not silently treated as
  complete metadata.
- One consumed capability performs one `vita_guest_call`. Preparation,
  strict-trap, explicit-exit, and clean-return outcomes have distinct events
  and exit codes: 11, 12, 13, and 0 respectively. The absent-bundle default
  remains exit 9.
- Public synthetic bundle tests prove zero calls at every forced preparation
  stop, one call on completion, strict-stop behavior, and deterministic
  repeated processes. This is not evidence of title boot or gameplay.

### Two-repository and provenance foundation

- The reusable framework and title-specific project are separate public
  repositories.
- The game consumes the exact framework revision through
  `third_party/vitarecomp`; a quality gate checks the gitlink against
  `config/framework.commit`.
- Historical work was curated by source path and license. The old duplicate
  C++ recompiler, complete Vita3K tree, hybrid production CPU, stale TODOs,
  private artifacts, and unrelated notes were not imported.
- The framework's CPU, runtime/HLE, GPU, provenance, and quality documentation
  is linked from [`ARCHITECTURE.md`](ARCHITECTURE.md).

### Static CPU and generated-code boundary

- `armrecomp` handles the accepted ELF/SCE relocation, ARM/Thumb mode,
  discovery, target promotion, jump-table, MOVW/MOVT pointer, measured
  VFP/NEON, checked/exclusive-memory, partition, report, and strict-trap
  contracts.
- Generated title C is local, ignored, and never tracked. Content-aware staging
  preserves unchanged files, removes only stale managed files, and has a
  synthetic regression.
- Gate 1 provenance now binds per-module sidecars/reports, aggregate compose
  readiness, the generated registry, and the complete C/header inventory to
  the framework pin and raw runtime-manifest identity. Provenance-required
  staging validates that evidence before modifying its target.
- The production architecture has no JIT, interpreter, Dynarmic dependency,
  emulator runtime, or missing-target continuation fallback.

### Standalone runtime and HLE foundation

- Checked guest memory, mode-aware dispatch, raw CPU/VFP state, TLS CPU
  ownership, deterministic scheduling, threading and synchronization,
  allocators, libc/libm, import registration, title-neutral kernel/I/O/FIOS2/
  ULT subsets, VFS, PSARC, diagnostics, restart, and teardown are present.
- `app0:` is forced read-only. Guest paths reject traversal, host absolute
  paths, extra drive separators, and symlink/reparse escapes.
- Missing imports and unsupported operations return explicit failures or named
  traps rather than zero/success placeholders.

### External content workflow

- The ZIP inspector reads the central directory and bounded signatures without
  extraction and classifies protected retail NoNpDRM/PFS content honestly.
- A portable, external Vita3K build can install/decrypt authorized user content
  and dump runtime ELF images only after relocation and import/export linking.
- The manifest tool independently validates ELF32/little-endian/ARM structure,
  module metadata, ranges, overlap, ordering, sizes, and hashes.
- The wrapper confines all Vita3K state and outputs to an explicit private
  root, exposes no key/license parameters, and stops only its exact spawned
  process.
- The source tree and index are protected by path-focused staged/tracked
  guards. Review remains mandatory.

### Shared GPU and native host

- A versioned C GPU ABI defines opaque handles, ownership, resources, binding,
  command ordering, queues, transitions, timeline fences, swapchains,
  readback, structured errors, and deterministic teardown.
- Production Direct3D 12 and Vulkan implementations use one HLSL source
  compiled by pinned DXC `1.8.2505.32` to DXIL and SPIR-V.
- The C++20 Win32 x64 host links only the standalone framework runtime and GPU
  targets. It validates its CLI, configuration, content manifest, ELF metadata,
  ranges, paths, and hashes before mounting content.
- Renderer, adapter, and validation choices are explicit. An unavailable
  request fails and never selects a different backend or adapter class.
- The public host self-test exercises window creation, minimize/restore,
  resize/recreate, clear/triangle rendering, readback, and reverse-order
  shutdown.

## Verified

### Historical clean-clone foundation matrix

- Framework Debug and Release: 17/17 CTests in each configuration.
- Game Debug, RelWithDebInfo, and Release: 13/13 CTests in each configuration.
- Total clean-room matrix: 73/73 CTest executions.
- MSVC warnings were errors; generated framework C used `/bigobj`.
- DX12, Vulkan, DXIL, and SPIR-V sources/outputs were required in generated
  projects.
- Three reviewed public homebrew fixtures completed extract, emit twice,
  byte-compare, and warnings-clean generated-C compilation.
- Public PowerShell content, staging, and guard suites passed under Windows
  PowerShell 5.1 and PowerShell 7.
- JSON schemas/examples, Markdown links, CMake presets, workflow syntax,
  licenses, exact submodule pin, deterministic artifact inventory, and
  private-content guards passed.

These counts are the accepted foundation record preserved in
[`FOUNDATION_VERIFICATION.md`](FOUNDATION_VERIFICATION.md); they are not
rewritten as Gate 1 results.

### Gate 1 public synthetic validation

On 2026-10-25, the current public working tree passed:

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

The framework selection passed 6/6 and the game/host selection passed 5/5.
Coverage includes ABI/report composition, structural blockers, classified
strict stops, provenance and staging failures, generated-bundle configure and
build rejection, retained bytes, no-TOCTOU loading, all eleven preparation
stages, one-use entry, clean return, explicit exit, and first strict failure.
All inputs were public or synthetic.

### Renderer and host acceptance

- Framework DX12 WARP and hardware paths passed three complete
  startup/resize/shutdown iterations with stable readback.
- Validation-enabled Vulkan passed two resize/recreate cycles on available
  hardware.
- Host DX12 WARP, DX12 hardware, and validation-enabled Vulkan self-tests
  passed.
- Invalid Vulkan ICD and unavailable adapter tests returned explicit errors and
  did not fall back.
- The wrong DXC version was rejected during configure.
- The local D3D12 Graphics Tools/debug layer was unavailable and reported as
  the single environment-dependent skip. Rendering, readback, lifecycle, and
  hardware/WARP coverage still passed.

### Redacted private acceptance

The following is historical foundation evidence, not Gate 1 real-entry
closure:

- A supplied PCSA00107 archive was inspected read-only: 866 central-directory
  entries, five packaged executable modules, expected NoNpDRM record, and
  protected outer PFS classification.
- Three post-link ELF32/ARM runtime images produced byte-identical manifests
  across repeat validation.
- Two static-generation runs each produced 809 files and 356,792,679 bytes;
  every file and report was byte-identical.
- All 800 generated C translation units across three modules compiled with
  MSVC `/W4 /WX /permissive- /bigobj` and no diagnostics.
- Measured CPU coverage was 10,898,202 of 11,308,620 executable bytes
  (96.370751%); 3,663,088 of 3,666,858 emitted instruction instances
  translated (99.897187%).
- The remaining 3,770 explicit traps are visible readiness failures, not
  hidden continuation behavior.
- The host independently validated and mounted the real manifest read-only,
  ran both renderer self-tests, redacted all paths/hashes, and preserved exit 9
  for title mode.
- Host dependencies and generated link inputs contained no Vita3K, Dynarmic,
  LLVM/JIT, or emulator runtime.

Complete commands, devices, metrics, redaction rules, and history scans are in
[`FOUNDATION_VERIFICATION.md`](FOUNDATION_VERIFICATION.md).

No successful private real-entry result is recorded. Gate 1 therefore remains
privately unclosed despite its implemented and publicly verified boundary.

## Public CI evidence

- Framework accepted head:
  [Windows quality gates 40185631954](https://github.com/Tzeentchnet/vitarecomp/actions/runs/40185631954)
- Game tested foundation:
  [Windows quality gates 40186098886](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40186098886)
- Game verification-report head:
  [Windows quality gates 40189417323](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40189417323)

All three completed successfully for the historical foundation. Hosted CI is
and remains source-only: it leaves `KZMRECOMP_GENERATED_SOURCE_DIR` empty and
has no private bundle, manifest, report, or generated title source. The local
public Gate 1 results above do not claim a new hosted run.

## Deferred

The ordered measurable backlog is maintained in
[`ROADMAP.md`](ROADMAP.md):

1. startup imports, threading, TLS, and filesystem behavior;
2. guest GXM scene capture through the shared GPU contract;
3. GXP reflection and USSE-to-HLSL shader integration;
4. DX12/Vulkan parity for title frames;
5. audio, input, save, and movie services;
6. named gameplay-progression checkpoints;
7. correctness-preserving performance work; and
8. local-only generation/build/package workflow.

None is implemented merely because its lower-level framework dependency
exists. Strict host entry makes later failures observable; it does not imply
that the remaining title services are implemented.

## Intentionally out of scope

- PFS/key derivation, key extraction, credential handling, or distributing
  decrypted/retail content.
- Tracking or publishing generated Killzone code, private manifests, traces,
  captures, shader caches, saves, or locally generated packages.
- Vendoring or linking Vita3K, using an emulator as the native runtime, or
  restoring the historical hybrid AOT CPU.
- Runtime JIT/interpreter fallback, renderer fallback, silent import success,
  unchecked guest access, or success-shaped unsupported GPU/HLE behavior.
- A claim that the title boots, reaches gameplay, or is playable at this
  checkpoint.
