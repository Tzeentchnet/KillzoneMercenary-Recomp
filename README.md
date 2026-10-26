# Killzone Mercenary Recomp

[![Windows quality gates](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/workflows/windows-quality.yml/badge.svg)](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/workflows/windows-quality.yml)

An unofficial, source-only foundation for a native Windows x64 recompilation of
the PlayStation Vita release of *Killzone Mercenary* (PCSA00107).

## Current status

**Gate 1 status: implemented and publicly/synthetically verified; privately
unclosed.**

The first foundation checkpoint remains complete and independently verified.
This repository is pinned to
[`vitarecomp@0e81bb4`](https://github.com/Tzeentchnet/vitarecomp/tree/0e81bb4b275435b2396b01a88c8d767d0104cc8b),
which provides the static generated-C CPU pipeline, standalone runtime/HLE,
shared GPU contract, and production DX12/Vulkan backends. The game repository
provides a C++20 Windows x64 host, strict external-content validation,
read-only `app0:` mounting, explicit renderer selection, and a bounded
clear/triangle conformance scene.

Generated-module ABI v1 and `armrecomp compose` provide deterministic
multi-module descriptors, a registry, and aggregate readiness reports.
Structural report defects are pre-entry blockers; fully classified named
traps are allowed only as the first explicit strict stop. Local provenance
schema-v1 tools bind that evidence to the framework, raw manifest, commands,
environment, and staged inventory.

`KZMRECOMP_GENERATED_SOURCE_DIR` is empty by default. Public and hosted builds
therefore contain no generated title bundle, and normal title mode retains
`title_not_implemented` exit 9. An opt-in provenance-validated local bundle
uses retained immutable module bytes without reopening paths, then passes the
strict loader, binding, descriptor, stack, TLS, CPU, and one-use
`vita_guest_call` boundary. Preparation failure, first strict failure, explicit
exit, and clean return are distinct outcomes.

No ignored local status record supplies successful private real-entry
evidence. Gate 1 is not privately closed, and this status does not claim that
the title boots or is playable. Startup HLE/GXM work remains deferred. The
repository contains no game data, generated title code, firmware, keys, or
playable build. See the
[current architecture](docs/ARCHITECTURE.md),
[project status](docs/PROJECT_STATUS.md), [verification
report](docs/FOUNDATION_VERIFICATION.md) for the historical foundation, and
the measurable
[post-foundation roadmap](docs/ROADMAP.md).

The reusable recompilation framework is pinned as the
`third_party/vitarecomp` Git submodule. Clone recursively, or initialize it
after cloning:

```powershell
git clone --recurse-submodules `
  https://github.com/Tzeentchnet/KillzoneMercenary-Recomp.git `
  KillzoneMercenary-Recomp
Set-Location KillzoneMercenary-Recomp
git submodule update --init --recursive
git submodule status
```

## Content boundary

This project does not distribute Sony Interactive Entertainment or Guerrilla
Cambridge content. Users must provide their own lawfully obtained copy of the
game and use authorized external tooling to prepare any required local data.
Retail archives, installed Vita data, decrypted modules, generated title code,
keys, licenses, saves, traces, captures, and shader caches must remain outside
Git. See [docs/CONTENT_POLICY.md](docs/CONTENT_POLICY.md).

## Configure, build, and test

Prerequisites:

- Windows x64
- CMake 3.25 or newer
- Visual Studio 2022
- PowerShell 7 or Windows PowerShell 5.1
- official Microsoft DXC `1.8.2505.32`
- Vulkan SDK headers when building the Vulkan backend

Point `VITARECOMP_DXC_ROOT` at the extracted official compiler package. Set
`VULKAN_SDK` when the Vulkan SDK is not already discoverable:

```powershell
$env:VITARECOMP_DXC_ROOT = '<dxc-package-root>'
$env:VULKAN_SDK = '<vulkan-sdk-root>'
cmake --preset windows-x64-debug
cmake --build --preset windows-x64-debug
ctest --preset windows-x64-debug
```

Equivalent `windows-x64-relwithdebinfo` and `windows-x64-release` presets are
provided. More details are in [docs/BUILDING.md](docs/BUILDING.md), including
the exact clean-clone verification commands and public-only
[quality gates](docs/QUALITY_GATES.md).

The generated-bundle opt-in is intentionally absent from every preset. Local
users must provide both an explicit validated staging directory and its bound
raw runtime manifest; hosted CI never supplies, uploads, caches, or builds a
private bundle.

## Native host

The bounded renderer smoke path needs no private content:

```powershell
out\build\windows-x64-debug\Debug\kzmrecomp_host.exe `
  --self-test --renderer=dx12 --adapter=warp --frames=4
```

Supported options are `--content-root`, `--manifest`,
`--renderer=dx12|vulkan`, `--adapter`, `--validation`, `--log-level`,
`--self-test`, `--frames`, and `--help`. Renderer selection never falls back.
Paths and content hashes are redacted from structured logs. See
[docs/NATIVE_HOST.md](docs/NATIVE_HOST.md) for manifest rules, exit codes, and
the strict conditional title-execution boundary.

Vulkan can be selected just as explicitly:

```powershell
out\build\windows-x64-debug\Debug\kzmrecomp_host.exe `
  --self-test --renderer=vulkan --adapter=hardware `
  --validation --frames=4
```

An unavailable backend, adapter, or requested validation layer is an error.
The host never falls back from Vulkan to DX12, from hardware to WARP, or to an
emulator/JIT.

## Migrated engineering material

- [Research record](docs/research/README.md) — curated findings, architecture
  handoff, and asset-format facts with explicit evidence labels
- [Current architecture](docs/ARCHITECTURE.md) — production boundaries,
  private-data rules, test layers, and strict error/no-fallback policy
- [Generated-source staging](tools/generated/Stage-GeneratedSources.ps1) —
  content-aware local staging with a
  [synthetic regression](tests/Test-StageGeneratedSources.ps1)
- [Generated-source provenance](docs/generated-source-provenance.md) —
  strict local sidecar/report/registry evidence and provenance-required
  staging with public synthetic coverage
- [Vita3K patch series](patches/vita3k/README.md) — generic post-link ELF
  dumping against a pinned external checkout
- [Migration manifest](MIGRATION.md) — per-source provenance, disposition,
  deferred integration points, and validation evidence
- [Post-foundation roadmap](docs/ROADMAP.md) — ordered, measurable gates from
  strict title entry through local-only package generation

## Repository layout

- `cmake/` — project CMake modules
- `config/` — tracked configuration templates
- `docs/` — public architecture, build, and content-boundary documentation
- `patches/vita3k/` — minimal source patches for an external Vita3K workflow
- `src/game/` — title-specific bindings and compatibility code
- `src/host/` — native Windows host code
- `tests/` — public and synthetic tests only
- `tools/content/` — local content inspection and safety tools
- `tools/generated/` — generic generated-source staging tools
- `third_party/vitarecomp/` — pinned framework submodule

## Private-content guard

Before committing, stage the intended files and run:

```powershell
pwsh -NoProfile -File tools/content/Guard-PrivateContent.ps1
```

The guard rejects known private/generated path classes. Optional private roots
can be listed in ignored `config/private-roots.txt` or in the
`KZM_RECOMP_PRIVATE_ROOTS` environment variable (semicolon-separated on
Windows). The guard complements review; it is not a legal-content detector.

## Gate 1 public validation

On 2026-10-25, the public synthetic Gate 1 surface passed these exact commands:

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

The framework selection passed 6/6 tests and the game/host selection passed
5/5 tests. All fixtures were public or synthetic. These local public results
do not substitute for the still-missing private real-entry closure evidence.

## Historical foundation evidence

The accepted checkpoint used framework
`f3408e1ea73b724c7ba3a644633938c220f2cc2a` and game report revision
`36fef0e94ab99d1fc6e1903f02a388013eb3585d`. The complete matrix and redacted
private acceptance are recorded in
[docs/FOUNDATION_VERIFICATION.md](docs/FOUNDATION_VERIFICATION.md).

Public hosted runs:

- framework [Windows quality gates
  40185631954](https://github.com/Tzeentchnet/vitarecomp/actions/runs/40185631954);
- game foundation [Windows quality gates
  40186098886](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40186098886);
- game verification report [Windows quality gates
  40189417323](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40189417323).

## License and trademarks

Project-authored files are licensed under
[GPL-2.0-or-later](LICENSE). The `third_party/vitarecomp` submodule is a
separate work and retains its own license files and notices; those notices are
not replaced by this repository's license.

*Killzone*, *Killzone Mercenary*, PlayStation, and PlayStation Vita are
trademarks of their respective owners. This project is not affiliated with or
endorsed by Sony Interactive Entertainment or Guerrilla.
