# Quality gates

The public Windows workflow requires no secrets or private game data.
It validates the exact framework gitlink
`0e81bb4b275435b2396b01a88c8d767d0104cc8b`.

| Job | Required coverage |
|---|---|
| Formatting, static quality, schemas, artifact safety | exact framework gitlink; pinned `actionlint`, PSScriptAnalyzer, and JSON Schema validator; CMake/JSON/Markdown/license checks; public scripts under Windows PowerShell 5.1 and PowerShell 7; complete tracked-content guard; deterministic inventory |
| MSVC Debug | host and both renderer backends with `/W4 /WX`; pinned DXC shader outputs; CTest; CLI/config/manifest, content pipeline, generated provenance/staging/bundle, strict title boundary, guard, DX12 WARP, Vulkan negative/smoke tests |
| MSVC RelWithDebInfo | the same host, backend, shader, and test coverage |
| MSVC Release | the same host, backend, shader, and test coverage |

Vulkan must compile and link. The invalid-ICD test verifies explicit failure
without backend fallback. The GPU smoke reports `SKIP` only when no usable ICD
exists. DX12 WARP is a required synthetic host self-test on the Windows runner.
`KZMRECOMP_GENERATED_SOURCE_DIR` remains empty in every hosted job. The
generated-bundle test creates only an ignored synthetic tree and removes it;
CI never receives, caches, uploads, or builds a private title bundle.

Run the exact local equivalents:

```powershell
pwsh -NoProfile -File tools/ci/Invoke-Quality.ps1 -Bootstrap
pwsh -NoProfile -File tools/ci/Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-debug -Bootstrap
pwsh -NoProfile -File tools/ci/Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-relwithdebinfo -Bootstrap
pwsh -NoProfile -File tools/ci/Invoke-WindowsBuild.ps1 `
  -Preset windows-x64-release -Bootstrap
```

Pinned public tools are hash-verified and extracted only under ignored `out/`.
The artifact gate permits no binary files in this repository; the framework's
three reviewed public homebrew fixtures remain confined to the pinned
submodule.

At the accepted checkpoint, each game configuration passed 13/13 CTests and
each framework configuration passed 17/17, for 73/73 clean-room CTest
executions across the matrix. The only environment-dependent acceptance skip
was the unavailable local D3D12 Graphics Tools/debug layer; it was reported
explicitly and did not skip WARP/hardware rendering, readback, or lifecycle
coverage.

Those counts and runs are the historical foundation matrix. The current Gate 1
public/synthetic boundary was validated separately on 2026-10-25:

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

Results were 6/6 framework tests and 5/5 game/host tests. These are local
public-fixture results, not a claim of a new hosted run or private real entry.
Gate 1 is implemented and publicly/synthetically verified but remains
privately unclosed.

Public successful runs:

- framework
  [40185631954](https://github.com/Tzeentchnet/vitarecomp/actions/runs/40185631954);
- game tested foundation
  [40186098886](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40186098886);
- game verification report
  [40189417323](https://github.com/Tzeentchnet/KillzoneMercenary-Recomp/actions/runs/40189417323).

See [`FOUNDATION_VERIFICATION.md`](FOUNDATION_VERIFICATION.md) for the exact
clean-clone commands, test inventory, renderer devices, and redacted private
acceptance.
