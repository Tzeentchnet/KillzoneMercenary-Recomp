# Killzone Mercenary Recomp

[![Windows quality gates](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/workflows/windows-quality.yml/badge.svg)](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/workflows/windows-quality.yml)

An unofficial project to statically recompile the PlayStation Vita release of
*Killzone Mercenary* (PCSA00107) into a native Windows x64 executable. The
executable renders through Direct3D 12 or Vulkan and targets 30 fps or
higher.

**Goal and scope:** [docs/GOAL.md](docs/GOAL.md) ·
**Milestones:** [docs/ROADMAP.md](docs/ROADMAP.md) ·
**Where we are:** [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) ·
**Contributor/agent rules:** [CLAUDE.md](CLAUDE.md)

## How it works

```text
your lawful dump
  -> external Vita3K (install/decrypt, post-link ELF dump only)
  -> validated runtime-image manifest
  -> armrecomp: ARM/Thumb -> C for every game module   ("decompile")
  -> MSVC + vitarecomp runtime/HLE + this Windows host  ("recompile")
  -> native kzmrecomp_host.exe --renderer=dx12|vulkan
```

The framework is [`Tzeentchnet/vitarecomp`](https://github.com/Tzeentchnet/vitarecomp),
a fork of [`sp00nznet/vitarecomp`](https://github.com/sp00nznet/vitarecomp).
It provides the recompiler, the runtime/HLE, and the DX12/Vulkan backends.
Vita3K is used only as an external content-preparation tool and source-code
reference. Its runtime output is not a review gate, and it is not forked,
extended, linked, or shipped.

## Current status

**M0 foundation done. M1 (lift and link) and M2 (into title code) are in
progress.** The game does not boot yet.

- All three runtime images lift to C that compiles cleanly: 96.37% of
  executable bytes covered, 99.897% of emitted instructions translated,
  3,770 explicit traps left.
- The host, the content validation, and both renderer backends work, using a
  self-test scene.
- An opt-in local generated bundle (`KZMRECOMP_GENERATED_SOURCE_DIR`) builds
  into the host, which can load, bind, and enter it through one strict
  `vita_guest_call`. Public builds have no bundle and exit 9
  (`title_not_implemented`) in title mode.
- Next: the first run on a real local bundle, then fix the first strict
  failure it reports (M2).

This repository contains no game data, generated title code, firmware, keys,
or playable build.

## Getting the source

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

## Reference material

- [Architecture](docs/ARCHITECTURE.md): process boundaries, pipeline, and
  the target runtime design
- [Native host](docs/NATIVE_HOST.md): options, exit codes, and the strict
  title-entry path
- [Generated-source provenance](docs/generated-source-provenance.md): how a
  local generated bundle is validated and staged
- [Research record](docs/research/README.md): curated CPU/loader findings
  and asset-format facts from earlier work
- [Generated-source staging](tools/generated/Stage-GeneratedSources.ps1)
  and its [synthetic regression](tests/Test-StageGeneratedSources.ps1)
- [Vita3K patch series](patches/vita3k/README.md): the frozen two-patch
  post-link ELF dump for an external checkout
- [Pending framework patches](patches/vitarecomp/README.md): fixes waiting
  to land in the framework fork
- Historical records: [migration manifest](MIGRATION.md) and
  [M0 verification](docs/FOUNDATION_VERIFICATION.md)

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

## M0 evidence

Title-entry test commands and results are in
[docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md#title-entry-validation).

The accepted M0 checkpoint used framework
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
