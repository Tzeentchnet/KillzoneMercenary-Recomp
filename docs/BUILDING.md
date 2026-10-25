# Building and verification

The public build needs no game data, Vita firmware, keys, generated title
source, Vita3K installation, or repository secrets. It builds the Windows
native host and the framework's DX12/Vulkan contract, then runs only public and
synthetic tests.

## Requirements

- Windows x64
- Git with submodule support
- CMake 3.25 or newer
- Visual Studio 2022 with the x64 C/C++ toolchain
- PowerShell 7 or Windows PowerShell 5.1
- official Microsoft DXC `1.8.2505.32`
- Vulkan SDK headers, or the pinned public headers installed by `-Bootstrap`

No content path, SDK path, adapter index, renderer, or private provenance value
is compiled into the host.

## Clean clone

Clone the game and its exact framework gitlink:

```powershell
$work = '<public-work-root>'
git clone --recurse-submodules `
  https://github.com/Tzeentchnet/KillzoneMercenary-Recomp.git `
  (Join-Path $work 'game')
Set-Location (Join-Path $work 'game')
git submodule update --init --recursive
git status --short --branch
git submodule status
```

At this checkpoint, `third_party/vitarecomp` and
`config/framework.commit` must both resolve to:

```text
f3408e1ea73b724c7ba3a644633938c220f2cc2a
```

To reproduce the independently accepted revisions rather than the moving
branch heads:

```powershell
git clone --recurse-submodules `
  https://github.com/Tzeentchnet/vitarecomp.git `
  (Join-Path $work 'framework-accepted')
git -C (Join-Path $work 'framework-accepted') checkout --detach `
  f3408e1ea73b724c7ba3a644633938c220f2cc2a

git clone --recurse-submodules `
  https://github.com/Tzeentchnet/KillzoneMercenary-Recomp.git `
  (Join-Path $work 'game-accepted')
git -C (Join-Path $work 'game-accepted') checkout --detach `
  36fef0e94ab99d1fc6e1903f02a388013eb3585d
git -C (Join-Path $work 'game-accepted') submodule update --init --recursive
```

The accepted clean-room commands and results are recorded in
[`FOUNDATION_VERIFICATION.md`](FOUNDATION_VERIFICATION.md).

## Recommended public quality and build commands

The wrappers mirror the required GitHub Actions jobs. `-Bootstrap` downloads
only pinned public tools, verifies their hashes, and installs them under
ignored `out/`:

```powershell
Set-Location '<game-checkout>'

pwsh -NoProfile -File tools/ci/Invoke-Quality.ps1 -Bootstrap
pwsh -NoProfile -File tools/ci/Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-debug -Bootstrap
pwsh -NoProfile -File tools/ci/Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-relwithdebinfo -Bootstrap
pwsh -NoProfile -File tools/ci/Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-release -Bootstrap
```

`Invoke-Quality.ps1` checks the framework pin, CMake/JSON/Markdown/license
quality, relative Markdown links, workflow syntax, PowerShell analysis,
schemas/examples, PowerShell 5.1/7 compatibility, private-content guards, and
two byte-identical artifact inventories. It also runs `git diff --check`.

Each build wrapper performs a fresh configure, requires the host and both
renderer backends plus DXIL/SPIR-V shader outputs, builds with warnings as
errors, runs CTest with no empty suite allowed, and reports the required DX12
WARP and Vulkan smoke tests.

## Manual configure, build, and CTest

When using an installed toolchain instead of `-Bootstrap`, extract the
official DXC package outside the source tree and set the environment:

```powershell
$env:VITARECOMP_DXC_ROOT = `
  '<directory-containing-build\native\bin\x64\dxc.exe>'
$env:VULKAN_SDK = '<vulkan-sdk-root>'

cmake --preset windows-x64-debug --fresh
cmake --build --preset windows-x64-debug --parallel
ctest --preset windows-x64-debug --no-tests=error
```

The framework rejects any DXC version other than `1.8.2505.32`. The supported
presets are:

- `windows-x64-debug`
- `windows-x64-relwithdebinfo`
- `windows-x64-release`

Build products stay under ignored `out/build/`. The host is a Windows GUI
subsystem executable that inherits a console or allocates one for
`--help`/`--self-test`; ordinary Explorer launch does not create an unwanted
console.

## Host DX12 and Vulkan self-tests

The bounded self-tests need no private content:

```powershell
$host = 'out\build\windows-x64-debug\Debug\kzmrecomp_host.exe'

& $host `
  --self-test --renderer=dx12 --adapter=warp `
  --frames=4 --log-level=debug

& $host `
  --self-test --renderer=vulkan --adapter=hardware `
  --validation --frames=4 --log-level=debug
```

DX12 WARP is the required software path. Vulkan requires a usable Vulkan 1.3
loader/ICD and the requested validation layer. An unavailable backend,
adapter, or validation capability is an explicit failure; the host does not
switch renderer or adapter class.

An optional self-test can validate and mount a user's external image set
without entering title code:

```powershell
& $host `
  --content-root='<private-runtime-image-root>' `
  --manifest='<private-runtime-manifest>' `
  --self-test --renderer=dx12 --adapter=warp --frames=4
```

Omitting `--self-test` after supplying valid content intentionally exits 9.
It does not prove or attempt title boot.

## Content inspection and external Vita3K dump

All placeholders below must point outside tracked source or below an ignored
private root. Use only content you are authorized to process.

Inspect an archive without extraction:

```powershell
$archive = '<absolute-path-to-lawfully-obtained-archive>'
pwsh -NoProfile -File tools/content/Inspect-KillzoneDump.ps1 `
  -ArchivePath $archive -OutputFormat Text -Redact
```

Check an isolated external Vita3K workflow without launching the title:

```powershell
$privateRoot = '<absolute-ignored-private-data-root>'
$vita3k = Join-Path $privateRoot 'vita3k\Vita3K.exe'
$revision = '<40-character-vita3k-source-revision>'

pwsh -NoProfile -File tools/content/Export-KillzoneRuntimeImages.ps1 `
  -ArchivePath $archive `
  -Vita3KExecutable $vita3k `
  -Vita3KSourceRevision $revision `
  -PrivateDataRoot $privateRoot `
  -Phase All -DryRun -Redact
```

Run the attended external install and dump only after the dry run succeeds:

```powershell
pwsh -NoProfile -File tools/content/Export-KillzoneRuntimeImages.ps1 `
  -ArchivePath $archive `
  -Vita3KExecutable $vita3k `
  -Vita3KSourceRevision $revision `
  -PrivateDataRoot $privateRoot `
  -Phase Install

pwsh -NoProfile -File tools/content/Export-KillzoneRuntimeImages.ps1 `
  -ArchivePath $archive `
  -Vita3KExecutable $vita3k `
  -Vita3KSourceRevision $revision `
  -PrivateDataRoot $privateRoot `
  -Phase Dump
```

Vita3K remains a separate extraction/oracle process. These commands do not
make it a host dependency. The full isolation, empty-dump-root, patch, and
manifest rules are in [`content-pipeline.md`](content-pipeline.md) and
[`../patches/vita3k/README.md`](../patches/vita3k/README.md).

## Direct safety checks

Before every commit:

```powershell
git status --short
pwsh -NoProfile -File tools/content/Guard-PrivateContent.ps1
pwsh -NoProfile -File tools/content/Guard-PrivateContent.ps1 -Tracked
git diff --check
git diff --cached --check
```

Optional private roots can be listed in ignored
`config/private-roots.txt` or `KZM_RECOMP_PRIVATE_ROOTS`. The guard is
path-focused and complements manual diff review; it is not a legal-content or
secret detector.

## Public verification evidence

The exact accepted matrix completed 73/73 CTest executions. Public hosted
evidence:

- framework
  [run 40185631954](https://github.com/Tzeentchnet/vitarecomp/actions/runs/40185631954);
- game tested foundation
  [run 40186098886](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40186098886);
- game verification-report head
  [run 40189417323](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40189417323).

See [`QUALITY_GATES.md`](QUALITY_GATES.md) for required coverage and
environment-dependent skip policy.
