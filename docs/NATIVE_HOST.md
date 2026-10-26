# Native Windows host

The C++20 `kzmrecomp_host` executable is a source-only Windows x64 host for the
standalone framework. It links `vitarecomp` and `vitarecomp::gpu` from the
pinned submodule. It does not link or launch Vita3K, does not contain a JIT,
and has no interpreter or emulator fallback. Public builds contain no
generated title bundle. An explicitly configured, provenance-validated local
bundle is accepted only through the strict title preparation boundary
described below.

The current framework pin is in `config/framework.commit`
(`0e81bb4b275435b2396b01a88c8d767d0104cc8b`); M0 was accepted at
`f3408e1ea73b724c7ba3a644633938c220f2cc2a`. The host self-test and content
boundary are verified. The strict title-entry path below has public synthetic
coverage but has not yet been run with a real local bundle; title boot and
playability are not claimed.

## Modes and options

The public no-bundle build provides the bounded renderer conformance test:

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
6. retains immutable bytes and loader metadata for every module in manifest
   order, so title loading never reopens a module path and has no
   validation-to-load path race;
7. rejects missing, changed, protected/not-ready images and intra-/cross-module
   load-range overlap; and
8. mounts the canonical root through the framework VFS as read-only `app0:`,
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
| 0 | Requested self-test or generated title entry completed |
| 2 | Invalid command line or option combination |
| 3 | Manifest/content validation failed |
| 4 | Selected backend or requested validation unavailable |
| 5 | Selected adapter unavailable |
| 6 | Graphics initialization failed |
| 7 | Render/conformance failed |
| 8 | Runtime/VFS initialization failed |
| 9 | Title execution intentionally not implemented |
| 10 | Win32 window/lifecycle failed |
| 11 | A strict title preparation precondition failed |
| 12 | Generated title execution stopped at its first strict failure |
| 13 | Generated title execution explicitly requested process exit |
| 70 | Unexpected internal failure |

## Title boundary

When no generated bundle is configured, valid non-self-test content is
layout-checked, mounted read-only, and still emits `title_not_implemented`
with exit 9. Public and hosted builds retain that behavior.

An opt-in local bundle must first pass the provenance and inventory checks in
[`generated-source-provenance.md`](generated-source-provenance.md). At run
time the host compares the supplied raw-manifest identity with the bundle's
expected identity without logging either value. It then completes, in order:

1. raw-manifest/bundle identity agreement;
2. deterministic title memory layout;
3. runtime initialization;
4. read-only `app0:` mounting;
5. strict in-memory module-set preflight;
6. transactional load plus module-table and relocation-extension validation;
7. generated descriptor, entry, TLS, and global-dispatch agreement;
8. complete export/function-import/variable-import binding;
9. checked main-stack preparation;
10. checked TLS-template preparation;
11. deterministic module-start CPU-state preparation; and
12. checked current/main-thread TLS materialization from the dedicated TLS
    arena.

Only then is a move-only capability constructed and consumed by one
`vita_guest_call`. A real clean return alone emits `title_entry_completed`; an
explicit exit request, the first classified named strict failure, or a boundary
error receives its own event and nonzero exit code. A preparation failure emits
`title_precondition_failed`, includes only redacted stage/status and record
indexes, and cannot invoke the entry. Loader and binding logs never contain
module paths, hashes, or the generated manifest identity.

The generated entry policy is fail-closed before this boundary. Body cuts,
unreported partitions, unclassified traps, missing function-entry or PC
instrumentation, incomplete metadata, or
unresolved/ambiguous entry records make an image set ineligible. Fully
classified named traps remain eligible only so the first one reached can
terminate the call as exit 12; they never permit continuation.

Public tests exercise absent-bundle exit 9, every preparation stop point with
an entry-call count of zero, exactly one clean synthetic call, strict-stop and
exit-request behavior, retained immutable bytes, and deterministic repeated
process runs. The exact 6/6 framework and 5/5 game/host commands and results
are recorded in
[`PROJECT_STATUS.md`](PROJECT_STATUS.md#title-entry-validation).
This boundary is not a claim that a private real entry has run, that the title
boots, or that later HLE/GXM services exist. Running it on a real local bundle
is the next M2 step in [`ROADMAP.md`](ROADMAP.md#m2--into-title-code).
