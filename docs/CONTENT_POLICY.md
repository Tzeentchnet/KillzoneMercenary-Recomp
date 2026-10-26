# External content policy

## Source-only repository

This repository contains project source, public documentation, build metadata,
and synthetic tests only. It must not contain:

- retail game archives, installed application trees, updates, or DLC;
- PlayStation Vita firmware or Vita3K user-data directories;
- SELF, ELF, SUPRX, PSARC, or extracted game assets;
- cryptographic keys, NoNpDRM work files, or retail licenses;
- locally generated title code or translated modules;
- saves, execution traces, graphics captures, or shader/pipeline caches; or
- build products and machine-local configuration.

Users are responsible for supplying their own lawfully obtained content and
for complying with applicable law and license terms. The implemented content
tools accept explicit external paths, confine Vita3K state and output to a
declared private root, and keep private reports and generated outputs outside
tracked source. They do not accept keys, licenses, zRIF values, or other
credentials.

## Architecture boundary

Vita3K is an external installation/decryption and post-link extraction process,
plus a source-code reference. Its runtime output is not review evidence. It is
not vendored, linked, launched by the native host, or used as a CPU/renderer
fallback. The native host
independently validates the resulting ELF manifest before mounting its root
read-only as `app0:`.

`armrecomp` output is also private local material for this title. Generated C,
reports, object files, locally assembled native packages, and provenance
manifests must stay in ignored output roots. The staging tool may synchronize
such output between two explicit ignored local directories, but it does not
make the files distributable or safe to commit:

```powershell
pwsh -NoProfile -File tools/generated/Stage-GeneratedSources.ps1 `
  -SourceDir '<ignored-generator-output>' `
  -TargetDir '<ignored-stable-build-input>' `
  -RequiredFile '<required-generated-file>'
```

Gate 1 additionally requires the ignored local provenance described in
[`generated-source-provenance.md`](generated-source-provenance.md). Its
opt-in staging mode validates the raw-manifest identity, framework revision,
module sidecars/reports, compose report, registry, and generated inventory
before modifying the target. Console and error output contain neither private
paths nor content hashes.

Only the generic schema, placeholder example, and provenance/staging tools are
public. A real provenance manifest, command specification, module/report pair,
compose output, staged source inventory, runtime manifest, and any resulting
binary remain private local material.

The CMake opt-in consumes only that explicit validated staging directory. It
does not search the checkout or generator output, and it never installs or
copies generated C, reports, provenance, or staging metadata into public
artifact paths. Hosted builds leave the cache opt-in unset; their bundle test
generates only a tiny synthetic staging tree below ignored `out/tests/` and
removes it after verification.

`KZMRECOMP_GENERATED_SOURCE_DIR` is empty by default in every public preset and
hosted job. Hosted CI stays source-only and must not receive, discover, cache,
upload, or attest to a private title bundle.

Automated public tests use synthetic fixtures only. The accepted private
validation is reported solely through redacted aggregate measurements in
[`FOUNDATION_VERIFICATION.md`](FOUNDATION_VERIFICATION.md).
That file is a historical foundation report, not successful private Gate 1
real-entry evidence. Gate 1 remains privately unclosed.

## Local private roots

Copy `config/private-roots.example.txt` to
`config/private-roots.txt`. The destination is ignored. Add one absolute path
or repository-relative path per line. The staged-content guard rejects any
candidate path located at or below a configured root.

Private roots may also be supplied through `KZM_RECOMP_PRIVATE_ROOTS`, separated
by the platform path separator (`;` on Windows). Environment and file entries
are combined.

## Before every commit

1. Review `git status --short`.
2. Stage only intended source and public synthetic fixtures.
3. Run `tools/content/Guard-PrivateContent.ps1`.
4. Inspect `git diff --cached --stat` and `git diff --cached`.

Run both complete scans when preparing a checkpoint:

```powershell
pwsh -NoProfile -File tools/content/Guard-PrivateContent.ps1
pwsh -NoProfile -File tools/content/Guard-PrivateContent.ps1 -Tracked
```

The guard is intentionally path-focused. It recognizes specific private and
generated layouts while allowing ordinary source names such as
`src/host/save-data.cpp`, `src/game/shader_cache.cpp`, documentation that names
the title ID, and public documentation images. Review remains mandatory.

See [`content-pipeline.md`](content-pipeline.md) for exact inspection and
external dump commands, [`ARCHITECTURE.md`](ARCHITECTURE.md) for the
two-repository/process boundary, and [`ROADMAP.md`](ROADMAP.md) for the
one-command local build milestone (M7).
