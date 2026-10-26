# External content pipeline

The repository never stores retail archives, installed title files, licenses,
keys, decrypted images, or generated code. These tools only inspect content
that the user supplies and keep every Vita3K write and ELF manifest below an
explicit private root. Use content obtained and processed lawfully.

## Checkpoint status and scope

| Classification | Content behavior |
|---|---|
| **Implemented** | Read-only ZIP inspection; isolated portable Vita3K orchestration; independent ELF/range/hash/overlap validation; deterministic private manifest generation; host-side revalidation/read-only mount; local generated-source provenance/staging; strict conditional title-entry boundary |
| **Verified** | Historical protected-archive and private manifest/mount foundation evidence; public synthetic provenance, generated-bundle, retained-byte, and strict-entry tests |
| **Privately unclosed** | No ignored local status file records a successful real generated-entry attempt |
| **Deferred** | Startup HLE/GXM behavior and local native package assembly |
| **Out of scope** | Key/PFS derivation or extraction, credential handling, publishing private/generated outputs, or using Vita3K in the native runtime |

The accepted revisions are game
`36fef0e94ab99d1fc6e1903f02a388013eb3585d` and framework/gitlink
`f3408e1ea73b724c7ba3a644633938c220f2cc2a`. Aggregate acceptance evidence is
in [`FOUNDATION_VERIFICATION.md`](FOUNDATION_VERIFICATION.md). Passing this
pipeline proves content readiness and isolation; it does not prove title boot
or playability.

## 1. Inspect an archive without extracting it

`Inspect-KillzoneDump.ps1` reads the ZIP central directory and small signature
prefixes directly from the archive. It does not extract entries. The archive
path is mandatory; no local content path is compiled into the script or tracked
configuration.

```powershell
$archive = '<absolute-path-to-lawfully-obtained-archive>'

pwsh -NoProfile -File tools/content/Inspect-KillzoneDump.ps1 `
  -ArchivePath $archive `
  -OutputFormat Text `
  -Redact
```

Add `-IncludeSha256` only when a full archive hash is needed. Use
`-OutputFormat Json -OutputPath <private-report-path>` for a machine-readable
private report. `-Redact` replaces the archive path and requested hash with
placeholders, making the text suitable for sharing as validation evidence.

The inspector requires:

- `app/PCSA00107/eboot.bin`;
- `app/PCSA00107/sce_sys/param.sfo`;
- `app/PCSA00107/sce_sys/package/work.bin`;
- `app/PCSA00107/game_data/data_ngp.psarc`; and
- at least one `app/PCSA00107/sce_module/*.suprx`.

It rejects unsafe or duplicate ZIP paths. `work.bin` identifies the NoNpDRM
retail layout. If the named eboot, module, and PSARC payloads do not expose
their normal signatures, the report explicitly classifies the archive as
`retail-pfs-nonpdrm` with a `protected` PFS state. This is expected for the
source archive and is not code-ready.

## 2. Prepare an isolated Vita3K

The wrapper requires a Vita3K build whose `--help` output advertises the proven
post-link `--dump-elfs` capability. The executable must be staged below the
private root, and a `portable` directory must be next to it:

```text
<private-root>/
  vita3k/
    Vita3K.exe
    portable/
```

This requirement makes Vita3K place its Vita filesystem, configuration, logs,
caches, and `elfdumps` below the explicit private root. A Vita3K installed
elsewhere is rejected rather than allowed to write to a user-wide or repository
path. The private root must either be outside the repository or match an ignore
rule such as `/private-data/`. Do not pass keys, licenses, zRIF values, or other
credentials; the wrapper has no parameters for them.

The source revision must be the Git commit used to build that executable. Keep
the corresponding source and patch provenance separately from private content.
The required source-only patch series and pinned Vita3K base are documented in
[`../patches/vita3k/README.md`](../patches/vita3k/README.md).

## 3. Dry-run, install, and dump

First verify paths, the archive layout, portable isolation, and Vita3K
capability without installing or launching the title:

```powershell
$privateRoot = '<absolute-ignored-private-data-root>'
$vita3k = Join-Path $privateRoot 'vita3k\Vita3K.exe'
$revision = '<40-character-vita3k-git-commit>'

pwsh -NoProfile -File tools/content/Export-KillzoneRuntimeImages.ps1 `
  -ArchivePath $archive `
  -Vita3KExecutable $vita3k `
  -Vita3KSourceRevision $revision `
  -PrivateDataRoot $privateRoot `
  -Phase All `
  -DryRun `
  -Redact
```

When an operator chooses to repeat the external smoke workflow, run the phases
separately:

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

Close the Vita3K title after each phase when the selected frontend requires
interaction. This repeat is an operator smoke step, not a prerequisite for
running the source-only build or its automated contract tests. Before the dump
phase, the wrapper requires installed
`eboot.bin` to expose a SELF or ELF signature and `data_ngp.psarc` to expose
`PSAR` magic. The expected dump directory must contain no existing ELF files;
move or remove an older private dump first so stale images cannot satisfy the
post-run checks or overlap a new image set. The dump phase fails if no
post-link ELF is produced. `-Phase All` performs the same install,
verification, and dump sequence in one invocation.

## 4. Validate runtime images

After a successful dump, the wrapper calls
`New-KillzoneElfManifest.ps1`. The validator is deliberately independent of
Vita3K. For every recursively discovered `.elf`, it checks:

- ELF magic, ELF32 class, little-endian encoding, and ARM machine type;
- bounded ELF and program headers;
- bounded and aligned `PT_LOAD` file and virtual-address ranges;
- at least one executable load segment and a bounded Vita module-info record
  selected by the encoded ELF `e_entry` value;
- intra-image and cross-image virtual-range overlap; and
- deterministic relative module paths and SHA-256 hashes.

The private manifest is written to:

```text
<private-root>/manifests/PCSA00107.runtime-images.json
```

It contains no timestamp, and modules are ordered by ordinal relative path, so
identical inputs produce byte-identical manifests. The source archive path and
hash are private provenance and must not be copied into tracked configuration.

The native host consumes this same schema. Pass the validated dump root as
`--content-root` and its private manifest as `--manifest`; module paths remain
relative to that root. The host independently rechecks ELF metadata, ranges,
sizes, and hashes before mounting the root as read-only `app0:`. See
[`NATIVE_HOST.md`](NATIVE_HOST.md). The tracked
`config/runtime-manifest.example.json` contains synthetic placeholders only.

`config/content-pipeline.example.json` and its JSON schema contain placeholders
only. They document the expected parameters and archive layout; replace values
only in an ignored local copy.

## Validation levels

### Automated contract tests

`Test-ContentPipeline.ps1` creates and removes synthetic ZIP and ELF fixtures
below the ignored `private-data` root. It covers valid and invalid ZIPs,
Unicode paths, missing entries, both protection classifications, Vita3K
capability and dry-run behavior, invalid ELF input, overlapping runtime
ranges, and deterministic manifests. It launches no title and needs only
PowerShell and the .NET runtime:

```powershell
pwsh -NoProfile -File tests/Test-ContentPipeline.ps1
```

CTest runs this script as `content-pipeline-synthetic`. These tests establish
the public tool contract without requiring retail content, Vita3K, graphics,
audio, or UI access.

### Independent existing-dump validation

A previously captured private post-link image set can be checked without
launching Vita3K:

```powershell
pwsh -NoProfile -File tools/content/New-KillzoneElfManifest.ps1 `
  -PrivateDataRoot '<absolute-ignored-private-data-root>' `
  -DumpRoot '<private-post-link-elf-directory>' `
  -ManifestPath '<private-manifest-path>' `
  -SourceArchivePath '<absolute-path-to-lawfully-obtained-archive>' `
  -SourceArchiveSha256 '<64-character-sha256>' `
  -Vita3KSourceRevision '<40-character-vita3k-git-commit>'
```

This is the reproducible foundation check for real images: it independently
validates structure, module metadata, executable ranges, overlap, ordering,
and hashes. A valid real archive inspection, a successful wrapper dry-run, and
a validated existing post-link set are sufficient foundation evidence.

### Optional attended repeat

Repeating install/dump proves the external emulator integration on a particular
desktop and driver stack. It is optional once equivalent private post-link
images have passed the independent validator. Use a clean ignored portable
root, confirm `--dump-elfs` in Vita3K help, ensure the title dump directory is
empty, run the `Install` and `Dump` phases, and close Vita3K only after the
required modules have loaded. UI automation is neither required nor assumed.

## Boundary after manifest creation

The manifest and runtime images remain private inputs. Static generation then
uses `armrecomp emit --module-id <id>` for each module, followed by:

```powershell
armrecomp compose --entry-module <id> --output <registry.c> `
  <module/report JSON>...
```

The local schema-v2 provenance creator binds the exact framework revision,
generator, command token arrays, recognized environment, raw-manifest
identity, schema-v4 module sidecars/reports, schema-v4 compose report and TLS
layout, partitions, and generated-file inventory. Provenance-required staging
validates all evidence before changing the stable build input. See
[`generated-source-provenance.md`](generated-source-provenance.md).

Structural report defects are rejected before entry. Fully classified named
traps keep production readiness false but may remain entry-eligible only so the
first trap reached becomes an explicit strict stop. This policy does not turn
generated output into publishable material.

The host may validate and mount the private inputs for a renderer self-test:

```powershell
out\build\windows-x64-debug\Debug\kzmrecomp_host.exe `
  --content-root='<private-runtime-image-root>' `
  --manifest='<private-runtime-manifest>' `
  --self-test --renderer=dx12 --adapter=warp --frames=4
```

Without `--self-test`, the public absent-bundle build reaches the explicit
`title_not_implemented` event and exits 9. An opt-in provenance-validated
local bundle may instead enter the strict host preparation path documented in
[`NATIVE_HOST.md`](NATIVE_HOST.md). Generated title output remains private and
must never be committed. Public presets and hosted CI leave
`KZMRECOMP_GENERATED_SOURCE_DIR` empty and contain no private bundle.

Gate 1 is implemented and publicly/synthetically verified but remains
privately unclosed. A private clean return or repeat-identical first named
strict stop would be optional stronger acceptance evidence; neither exists in
the local status records, and neither would establish bootability or
playability.
