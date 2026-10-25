# Native Windows host

The C++20 `kzmrecomp_host` executable is a source-only Windows x64 host for the
standalone framework. It links `vitarecomp` and `vitarecomp::gpu` from the
pinned submodule. It does not link or launch Vita3K, does not contain a JIT,
and does not load generated Killzone code.

The accepted gitlink is
`f3408e1ea73b724c7ba3a644633938c220f2cc2a`. The host self-test and content
boundary are verified; title boot and playability are not.

## Modes and options

The only currently successful execution mode is the bounded renderer
conformance test:

```powershell
kzmrecomp_host.exe --self-test --renderer=dx12 --adapter=warp --frames=4
kzmrecomp_host.exe --self-test --renderer=vulkan --adapter=hardware --validation
```

Options accept either `--name=value` or `--name value` where a value is
required:

| Option | Contract |
|---|---|
| `--content-root` | External root mounted as `app0:` only after validation |
| `--manifest` | Private deterministic runtime-image manifest paired with the content root |
| `--renderer` | Required `dx12` or `vulkan`; no fallback |
| `--adapter` | `hardware` (default class), `warp` for DX12, or a numeric index |
| `--validation` | Require validation; unavailable validation is an error |
| `--log-level` | `trace`, `debug`, `info`, `warning`, or `error` |
| `--self-test` | Run the framework clear/triangle scene |
| `--frames` | Self-test frame count from 1 through 10000; default 4 |
| `--help` | Print help and exit; it must be used alone |

Unknown options, positional arguments, duplicates, missing option values,
partial content/manifest pairs, Vulkan WARP, and `--frames` outside self-test
are rejected.

`--self-test` may run without private content. Supplying one of
`--content-root` or `--manifest` requires the other and runs the same strict
validation used by title mode.

## Manifest and content contract

`config/runtime-manifest.schema.json` describes the deterministic manifest
emitted by `New-KillzoneElfManifest.ps1`; the tracked example contains only
placeholders. Module paths are relative to `--content-root`. The host:

1. rejects unknown/missing schema properties and the wrong title ID;
2. accepts only ELF32, little-endian ARM runtime images produced through the
   declared post-link dump capability;
3. rejects absolute, empty, duplicate, non-deterministic, traversal, symlink,
   junction, and reparse-point module paths;
4. independently checks ELF/program-header/module-info metadata against every
   manifest record;
5. verifies file sizes and SHA-256 values while each file is held without
   write/delete sharing;
6. rejects missing, changed, protected/not-ready images and intra-/cross-module
   load-range overlap; and
7. mounts the canonical root through the framework VFS as read-only `app0:`,
   then verifies both traversal and write denial before continuing.

Normal structured logs report only module/segment counts. User paths, module
paths, and hashes are never logged. Absolute paths, 64-digit hashes, and
registered command-line path values are also redacted defensively.

## Renderer lifecycle

The host creates a real Win32 window and explicitly selects one production
backend and adapter. It reports the backend, adapter, type, capability flags,
limits, and validation state. The self-test minimizes, restores, resizes, and
recreates the swapchain, renders a deterministic clear and triangle, validates
the final readback, and destroys commands, pipelines, shaders, fences,
swapchain, device, VFS/runtime, and window resources in dependency order.

## Exit codes

| Code | Meaning |
|---:|---|
| 0 | Requested self-test completed |
| 2 | Invalid command line or option combination |
| 3 | Manifest/content validation failed |
| 4 | Selected backend or requested validation unavailable |
| 5 | Selected adapter unavailable |
| 6 | Graphics initialization failed |
| 7 | Render/conformance failed |
| 8 | Runtime/VFS initialization failed |
| 9 | Title execution intentionally not implemented |
| 10 | Win32 window/lifecycle failed |
| 70 | Unexpected internal failure |

## Title boundary

Valid content in non-self-test mode is validated and mounted, then exits with
code 9. This is intentional. Title execution cannot become ready until
generated-source provenance, complete strict import registration, and the
required title HLE/GXM preconditions are implemented and tested. There is no
success-shaped title entry point in this scaffold.

The complete production boundary is in
[`ARCHITECTURE.md`](ARCHITECTURE.md); the gates that may eventually replace
exit 9 are ordered in [`ROADMAP.md`](ROADMAP.md).
