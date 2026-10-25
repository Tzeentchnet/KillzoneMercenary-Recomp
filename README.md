# Killzone Mercenary Recomp

An unofficial, source-only foundation for a native Windows x64 recompilation of
the PlayStation Vita release of *Killzone Mercenary* (PCSA00107).

## Current status

The repository now contains a real C++20 Windows x64 native host linked to the
standalone `vitarecomp` runtime and its production DX12/Vulkan GPU contract.
The host validates an explicit external runtime-image manifest, mounts the
validated content root as read-only `app0:`, and can run the framework
clear/triangle conformance scene through either explicitly selected backend.
It has no Vita3K runtime dependency and no JIT.

Title execution remains deliberately disabled. No translated Killzone code is
loaded or called until generated-code provenance and strict import/HLE
preconditions exist. This repository still contains no game data, generated
title code, firmware, keys, or playable build. See
[docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md) for the exact checkpoint and
validation evidence.

The reusable recompilation framework is pinned as the
`third_party/vitarecomp` Git submodule. Clone recursively, or initialize it
after cloning:

```powershell
git submodule update --init --recursive
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
provided. More details are in [docs/BUILDING.md](docs/BUILDING.md).

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
the title-execution boundary.

## Migrated engineering material

- [Research record](docs/research/README.md) — curated findings, architecture
  handoff, and asset-format facts with explicit evidence labels
- [Generated-source staging](tools/generated/Stage-GeneratedSources.ps1) —
  content-aware local staging with a
  [synthetic regression](tests/Test-StageGeneratedSources.ps1)
- [Vita3K patch series](patches/vita3k/README.md) — generic post-link ELF
  dumping against a pinned external checkout
- [Migration manifest](MIGRATION.md) — per-source provenance, disposition,
  deferred integration points, and validation evidence

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

## License and trademarks

Project-authored files are licensed under
[GPL-2.0-or-later](LICENSE). The `third_party/vitarecomp` submodule is a
separate work and retains its own license files and notices; those notices are
not replaced by this repository's license.

*Killzone*, *Killzone Mercenary*, PlayStation, and PlayStation Vita are
trademarks of their respective owners. This project is not affiliated with or
endorsed by Sony Interactive Entertainment or Guerrilla.
