# Foundation checkpoint verification

> **Historical record of milestone M0.** This report is kept as evidence and
> is not maintained. Current state is in
> [PROJECT_STATUS.md](PROJECT_STATUS.md), and future progress is logged
> there rather than in new verification reports.

Verification date: 2026-10-25

Accepted clean-room window: 2026-10-25T10:50:11Z onward

Result: **PASS**, with one explicit environment-dependent validation skip
documented below.

This report is intentionally redacted. It contains no private filesystem
paths, content hashes, module names, generated title source, or game bytes.
Aggregate measurements are retained because they are the accepted public CPU
baseline.

## Verified public revisions

| Component | Verified revision |
|---|---|
| Framework `Tzeentchnet/vitarecomp` | `f3408e1ea73b724c7ba3a644633938c220f2cc2a` |
| Game repository before this report-only commit | `5b013f5967e68acfdf89573ffcaeb1a13aa76029` |
| Game framework gitlink | `f3408e1ea73b724c7ba3a644633938c220f2cc2a` |
| Preserved upstream baseline | `6ed4a5c59045706292c8ec03dfe5207ecc4033a4` |
| Upstream baseline tag | `upstream-start-6ed4a5c5` |

Both repositories were cloned from their public HTTPS origins with complete
history and recursive submodules. The framework verification target had 50
reachable commits and the game target had four. The expected revisions were
the remote `main` heads and were descendants of the requested minimum
revisions.

The framework retained `LICENSE`, `NOTICE`, both MIT and
GPL-2.0-or-later license texts, and `docs/PROVENANCE.md`. The game retained
`LICENSE`, `NOTICE`, `MIGRATION.md`, `docs/CONTENT_POLICY.md`, and the exact
framework pin. The provenance tag resolves to the unchanged upstream baseline.

One provenance defect was found and fixed before acceptance: the documented
upstream baseline tag existed locally but was absent from the public framework
origin. The existing tag was published without changing either branch head.
Fresh clones made after that fix received and resolved the tag correctly.

## Clean-room protocol and commands

An initial preflight clone under a much longer session path reached the legacy
MSBuild 260-character path limit during the compiler probe. No result from that
attempt is counted. The verification directory was recreated at a bounded
short session path, both repositories were cloned again from their public
origins, and every accepted configure, build, and test below ran from those
new clones.

The public-source commands were:

```powershell
git clone --recurse-submodules `
  https://github.com/Tzeentchnet/vitarecomp.git `
  <verification-root>\framework
git clone --recurse-submodules `
  https://github.com/Tzeentchnet/KillzoneMercenary-Recomp.git `
  <verification-root>\game
git -C <verification-root>\framework submodule update --init --recursive
git -C <verification-root>\game submodule update --init --recursive

pwsh -NoProfile -File `
  <framework>\tools\ci\Invoke-Quality.ps1 -Bootstrap
pwsh -NoProfile -File `
  <framework>\tools\ci\Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-debug -Bootstrap
pwsh -NoProfile -File `
  <framework>\tools\ci\Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-release -Bootstrap

pwsh -NoProfile -File `
  <game>\tools\ci\Invoke-Quality.ps1 -Bootstrap
pwsh -NoProfile -File `
  <game>\tools\ci\Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-debug -Bootstrap
pwsh -NoProfile -File `
  <game>\tools\ci\Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-relwithdebinfo -Bootstrap
pwsh -NoProfile -File `
  <game>\tools\ci\Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-release -Bootstrap
```

The scripts configured with `--fresh`, built with MSVC x64, verified both
renderer source files and pinned shader outputs in the generated projects, and
ran CTest with `--no-tests=error`. Project policy supplied `/W4 /WX
/permissive-`; generated C additionally used `/bigobj`.

Renderer and negative-path commands included:

```powershell
vitarecomp_dx12_conformance.exe `
  --warp --hidden --iterations 3 --frames 4
vitarecomp_dx12_conformance.exe `
  --hidden --iterations 3 --frames 4

kzmrecomp_host.exe `
  --self-test --renderer=dx12 --adapter=warp --frames=4 --log-level=debug
kzmrecomp_host.exe `
  --self-test --renderer=dx12 --adapter=hardware --frames=4 --log-level=debug
kzmrecomp_host.exe `
  --self-test --renderer=vulkan --adapter=hardware `
  --validation --frames=4 --log-level=debug
```

The invalid-ICD test set both Vulkan ICD override variables to a nonexistent
manifest and required explicit Vulkan unavailability with no DX12 selection.
A separate fresh configure pointed `VITARECOMP_DXC_ROOT` at an executable that
did not report the pinned version and required configure failure naming
`1.8.2505.32`.

Private commands used the same public tools with redacted arguments:

```powershell
pwsh -NoProfile -File Inspect-KillzoneDump.ps1 `
  -ArchivePath <supplied-archive> -OutputFormat Json `
  -IncludeSha256 -Redact
pwsh -NoProfile -File New-KillzoneElfManifest.ps1 `
  -PrivateDataRoot <ignored-private-root> `
  -DumpRoot <private-runtime-images> `
  -ManifestPath <ignored-private-manifest> `
  -SourceArchivePath <supplied-archive> `
  -SourceArchiveSha256 <private-hash> `
  -Vita3KSourceRevision <private-provenance-revision>

armrecomp.exe discover <private-image>
armrecomp.exe emit <private-image> <ignored-private-output>\module.c

kzmrecomp_host.exe `
  --content-root=<private-content-root> `
  --manifest=<private-manifest> `
  --self-test --renderer=dx12 --adapter=warp --frames=4
kzmrecomp_host.exe `
  --content-root=<private-content-root> `
  --manifest=<private-manifest> `
  --self-test --renderer=vulkan --adapter=hardware `
  --validation --frames=4
kzmrecomp_host.exe `
  --content-root=<private-content-root> `
  --manifest=<private-manifest> `
  --renderer=dx12 --adapter=warp
```

Private inputs were copied only into ignored verification output. No private
output was staged or committed.

## Build and test results

| Matrix entry | Build coverage | CTest |
|---|---|---:|
| Framework Debug | MSVC `/WX`, DX12, Vulkan, DXIL and SPIR-V | 17/17 passed |
| Framework Release | MSVC `/WX`, DX12, Vulkan, DXIL and SPIR-V | 17/17 passed |
| Game Debug | Host, DX12, Vulkan, DXIL and SPIR-V | 13/13 passed |
| Game RelWithDebInfo | Host, DX12, Vulkan, DXIL and SPIR-V | 13/13 passed |
| Game Release | Host, DX12, Vulkan, DXIL and SPIR-V | 13/13 passed |

The full configuration matrix therefore completed 73/73 CTest executions.
Coverage included:

- container, inflation, decoder, relocation, discovery, emitter, runtime,
  runtime-foundation/HLE, prior semantic vectors, dispatch diagnostics, GPU
  contract, and C ABI tests;
- all three public homebrew fixtures through extract, emit twice, byte
  comparison, and warnings-clean C compilation;
- DX12 WARP buffer and presentation conformance;
- Vulkan invalid-ICD/no-fallback and validation-enabled conformance;
- host CLI, configuration, manifest, redaction, read-only VFS, and title
  boundary tests;
- synthetic content, generated-source staging, staged/tracked guards,
  unavailable backend/adapter handling, and resize/lifecycle repetition.

The game quality gate also ran its public PowerShell suites under Windows
PowerShell 5.1 and PowerShell 7:

- private-content guard: 10 allowed and 17 rejected synthetic cases per host;
- content pipeline: nine synthetic cases per host;
- generated staging: initial copy, unchanged repeat, and stale-file removal
  per host;
- tracked guard: 73 paths;
- JSON schema/example validation: two schema pairs and five JSON files.

## Renderer acceptance

| Path | Device | Result |
|---|---|---|
| Framework DX12 WARP | Microsoft Basic Render Driver, adapter 2 | PASS, three startup/resize/shutdown iterations with stable readback |
| Framework DX12 hardware | NVIDIA GeForce RTX 5070, adapter 0 | PASS, three startup/resize/shutdown iterations with stable readback |
| Framework Vulkan | NVIDIA GeForce RTX 5070, adapter 0 | PASS, validation enabled and two full resize/recreate cycles |
| Framework Vulkan enumeration | AMD Radeon Graphics, adapter 1 | Detected; discrete adapter 0 was selected |
| Host DX12 WARP | Microsoft Basic Render Driver, adapter 2 | PASS |
| Host DX12 hardware | NVIDIA GeForce RTX 5070, adapter 0 | PASS |
| Host Vulkan | NVIDIA GeForce RTX 5070, adapter 0 | PASS, validation required and enabled |

The framework invalid-ICD test passed. The host invalid-ICD run exited 4,
reported Vulkan unavailable, never selected DX12, and never emitted a
self-test success event. Wrong-DXC configure exited 1 with the pinned version
in the diagnostic. The host repeated WARP initialization, resize, rendering,
and deterministic shutdown three times.

No Vulkan validation error, VUID, high-severity graphics message, or host
error-level event appeared in successful runs. **SKIP:** the Windows D3D12
Graphics Tools/debug layer was not installed, so DX12 info-queue
high-severity capture was unavailable. The conformance tools reported that
limitation explicitly; it was not silently treated as enabled. WARP and
hardware rendering, readback, resize, and repeated shutdown still passed.

## Supplied content and private manifest

The supplied archive was opened read-only and inspected through its ZIP central
directory without extraction:

- title ID: `PCSA00107`;
- 866 central-directory entries: 765 files and 101 directories;
- 865 entries below the title root;
- all four required layout classes present and nonempty;
- five packaged executable-module entries;
- NoNpDRM work/license record present;
- classification: retail NoNpDRM layout with the outer PFS layer still
  protected.

The independently supplied post-link set contained three ELF32,
little-endian ARM runtime modules. A fresh manifest was generated twice from
hash-checked copies. The two manifests were byte-identical, all three records
matched the accepted manifest, segment/range validation passed, and no private
path or hash was printed.

## Private CPU repeat acceptance

Both complete generation runs used the clean framework clone. Each run then
compiled every generated C translation unit for all three modules with MSVC
`/W4 /WX /permissive- /bigobj`.

| Metric | Accepted result |
|---|---:|
| Runtime images | 3/3 hash-checked |
| Generation runs | 2 |
| Files per run | 809 |
| Generated bytes per run | 356,792,679 |
| C translation units per run | 800 |
| Compiled modules | 3/3 in each run |
| Compile warning/error diagnostics | 0 |
| Discovered functions | 105,873 |
| Instructions reached | 4,050,600 |
| Executable bytes covered | 10,898,202 / 11,308,620 |
| Executable-byte coverage | 96.370751% |
| Jump tables | 631 |
| MOVW/MOVT pointers | 18,121 |
| Indirect sites | 44,591 |
| Emitted functions | 48,706 |
| Emitted instruction instances | 3,666,858 |
| Translated instruction instances | 3,663,088 |
| Explicit trapped instances | 3,770 |
| Translation yield | 99.897187% |
| Body cuts / unreported partitions | 0 / 0 |
| Function partitions | 37 |

Relative file inventories, every generated-file digest, and all six report
files were identical between runs. These values exactly reproduce the
accepted CPU baseline. The 3,770 explicit traps remain a readiness signal, not
permission to execute title code.

## Host content boundary

Synthetic self-tests passed with DX12 WARP, DX12 hardware, and
validation-enabled Vulkan. The fresh real three-module manifest and copied
content were then validated, mounted as read-only `app0:`, exercised with both
DX12 and Vulkan self-tests, and shut down cleanly. Structured output exposed
only aggregate module/segment counts; scans found no registered private path,
module path, absolute path, or 64-digit content hash.

Non-self-test title mode validated and mounted the same content, emitted the
explicit `title_not_implemented` event, and exited 9. No generated title
source was loaded and no title entry point was called.

`dumpbin /dependents` inspected Debug, RelWithDebInfo, and Release hosts.
Dependencies were limited to Windows graphics, shell, cryptography, and MSVC
runtime DLLs. Generated project link inputs and the host source boundary had
no Vita3K, Dynarmic, LLVM, or JIT runtime link.

## Artifact and operational safety

Public quality inventories were deterministic:

- framework: 137 tracked entries, including exactly three reviewed public
  homebrew fixtures;
- game before this report: 73 tracked entries and no binary fixture.

A separate all-history scan checked reachable paths, blobs, commit messages,
binary signatures, file sizes, high-confidence secret formats, credential
paths, private absolute paths, generated/private path classes, and required
license/provenance inputs:

| Repository target | History scanned | Unique blobs | Result |
|---|---:|---:|---|
| Framework | 50 commits, 632 reachable objects | 371 | PASS, zero violations; three reviewed fixture blobs |
| Game | 4 commits, 117 reachable objects | 82 | PASS, zero violations; no binary blobs |

No proprietary/generated/private artifact, secret, machine-private absolute
path, unexpected binary, file over the one-megabyte policy limit, LFS pointer,
or license/provenance gap was found.

Windows Application-log checks from the verification-window start found zero
Application Error, Application Hang, .NET Runtime crash, or Windows Error
Reporting events, including zero related to any verification executable.
There were no remaining host, recompiler, conformance, test, CMake, MSBuild,
compiler, WER, debugger, Vita3K, or dialog processes.

## Hosted CI

The verified target heads were green before this report-only commit:

- framework:
  [Windows quality gates run 40185631954](https://github.com/Tzeentchnet/vitarecomp/actions/runs/40185631954);
- game:
  [Windows quality gates run 40186098886](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40186098886).

The framework run covered formatting/static/artifact safety plus Debug and
Release DX12/Vulkan jobs. The game run covered formatting/static/schema/
PowerShell/artifact safety plus Debug, RelWithDebInfo, and Release host jobs.
The report-only follow-up head subsequently completed the same hosted workflow:
[game run 40189417323](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40189417323)
passed on report commit
`36fef0e94ab99d1fc6e1903f02a388013eb3585d`. The hosted-CI handoff gate is
therefore complete.

## Original workspaces and preserved handoff

Before adding this report, both original `main` workspaces were clean and
equal to `origin/main`. The framework remained at
`f3408e1ea73b724c7ba3a644633938c220f2cc2a`; the game remained at
`5b013f5967e68acfdf89573ffcaeb1a13aa76029`. The pinned submodule was clean at
the framework revision, with detached HEAD only in the normal gitlink sense.

The preserved session worktrees were unchanged:

- `feature/dx12-foundation` at
  `a19d340e5adbf48d2b1b366fc4ffeea7b8c58032`;
- `integration/renderers` at
  `b1754cd5464604c70f39253d63b8c6163da20012`;
- `feature/runtime-foundation` at
  `91c91ea1c6d291ba3fcd53dca3ba9c843be36d10`;
- `feature/vulkan-foundation` at
  `d2e0c8bc5044333cc41354572a6002614423570b`.

The private-free prior-work snapshot and branch handoff were not modified.

## Deferred scope

This checkpoint does not implement or authorize title execution. Generated
source provenance, complete strict import registration, module/TLS/entry
preconditions, title HLE, GXM/GXP/USSE, input, audio, movies, saves, networking,
gameplay, and renderer parity for title frames remain deferred. The explicit
exit-9 boundary must remain until those gates are implemented and measured.

The unavailable local DX12 debug layer is the only acceptance skip. It is an
environment capability, not a source defect, and does not change the deferred
title scope.
