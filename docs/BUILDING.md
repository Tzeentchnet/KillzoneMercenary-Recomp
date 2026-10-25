# Building the native host

## Requirements

- A Windows x64 host
- Git with submodule support
- CMake 3.25 or newer
- Visual Studio 2022 with an x64 toolchain
- PowerShell 7 or Windows PowerShell 5.1
- the official Microsoft DirectX Shader Compiler package containing
  `dxc.exe` version `1.8.2505.32`
- the Vulkan SDK when Vulkan support is required

Initialize the pinned framework after cloning:

```powershell
git submodule update --init --recursive
```

The build never downloads compiler binaries. Extract the official
`Microsoft.Direct3D.DXC` `1.8.2505.32` package (or the matching official DXC
release) outside the tracked source tree and set:

```powershell
$env:VITARECOMP_DXC_ROOT = '<directory containing build\native\bin\x64\dxc.exe>'
```

The framework rejects any other DXC version. For Vulkan, set `VULKAN_SDK` to an
installed SDK if CMake cannot discover it:

```powershell
$env:VULKAN_SDK = '<Vulkan SDK root>'
```

No content path, SDK path, adapter index, or renderer is compiled into the
host.

## Presets

Configure, build, and test one configuration:

```powershell
cmake --preset windows-x64-debug
cmake --build --preset windows-x64-debug
ctest --preset windows-x64-debug
```

The other supported preset names are:

- `windows-x64-relwithdebinfo`
- `windows-x64-release`

Build output is written below `out/build/` and is ignored. The current
presets build `kzmrecomp_host` and `kzmrecomp_host_tests`. MSVC compiles the
project and framework with warnings as errors. The host is a Windows GUI
subsystem executable that uses an inherited console or allocates one for
`--help`/`--self-test`; normal Explorer GUI launch does not create an unwanted
console.

Run a renderer-only smoke test without private content:

```powershell
out\build\windows-x64-debug\Debug\kzmrecomp_host.exe `
  --self-test --renderer=dx12 --adapter=warp --frames=4
```

Use `--renderer=vulkan --validation` to require Vulkan validation. A request
for an unavailable backend, adapter, or validation layer fails explicitly and
never falls back.

The complete CTest suite includes CLI/config/manifest/redaction unit tests,
DX12 WARP and optional hardware integration, validation-enabled Vulkan,
unavailable backend/adapter checks, synthetic invalid content, resize/lifecycle
coverage, repeated startup/shutdown, the content pipeline, generated-source
staging, and private-content guards.

## Safety check

The CTest suite runs synthetic path-policy tests and scans the current staged
Git paths. Run the staged scan directly when reviewing a change:

```powershell
pwsh -NoProfile -File tools/content/Guard-PrivateContent.ps1
```

Configure local private roots by copying
`config/private-roots.example.txt` to ignored
`config/private-roots.txt` and editing the copy. Both absolute roots and paths
relative to the repository are accepted.
