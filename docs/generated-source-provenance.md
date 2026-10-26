# Local generated-source provenance

Gate 1 uses a local, ignored provenance manifest to bind generated title
sources to the exact framework pin, raw runtime manifest, generator binary,
generation recipe, module evidence, compose result, and generated-file
inventory. The manifest does not make generated output redistributable and
must not be committed.

The public generated-module contract is ABI version 4. Module sidecars are
schema v4, module reports are schema v4, compose reports are schema v4, this
provenance manifest is schema v2, and the enforced entry policy is version 1.
Consumers reject unknown versions rather than guessing compatibility.

The public shape is
[`config/generated-source-provenance.schema.json`](../config/generated-source-provenance.schema.json).
Its paired
[`generated-source-provenance.example.json`](../config/generated-source-provenance.example.json)
contains placeholders and synthetic names only.

## Evidence consumed

`armrecomp emit --module-id ...` must have produced, for every module:

- the main C file, generated header, optional numbered C partitions, and
  generated import C files;
- the schema-v4 `.module.json` sidecar, including explicit TLS alignment;
- the schema-v4 `.report.json` and `.report.txt`; and
- PC instrumentation enabled with `VITARECOMP_EMIT_PC=1`.

`armrecomp compose` must then have produced the registry C/header pair and its
schema-v4 aggregate `.report.json` and `.report.txt`. The aggregate report
records deterministic TLS descriptor indices, order, aligned offsets, data
size, and data alignment. The compose invocation must select one explicit
entry module.

The exact command shape is:

```text
armrecomp compose --entry-module <id> --output <registry.c> \
  <module-1.module.json> <module-1.report.json> [...]
```

PowerShell callers place the arguments on separate backtick-continued lines
instead of using the illustrative backslash above. Input ordering is not
precedence: the composer validates exact sidecar/report pairing and sorts the
registry deterministically.

The creator discovers module sidecars and all generated C/header files below
one output root. Persisted paths and command path arguments are exact,
forward-slash, source-relative values. Absolute paths, traversal, duplicate
paths, case collisions, and unordered inventories are rejected.

## Command specification

The creator takes a small local command specification. Commands are token
arrays, not shell command strings, and are interpreted relative to
`SourceRoot`. Emit commands are ordered by module ID and the compose command is
last. Compose inputs are sorted by path.

```json
{
  "commands": [
    {
      "sequence": 0,
      "phase": "emit",
      "moduleId": "module_main",
      "executable": "armrecomp",
      "arguments": [
        "emit",
        "--module-id",
        "module_main",
        "inputs/module_main.elf",
        "modules/module_main.c"
      ]
    },
    {
      "sequence": 1,
      "phase": "compose",
      "moduleId": null,
      "executable": "armrecomp",
      "arguments": [
        "compose",
        "--entry-module",
        "module_main",
        "--output",
        "generated_registry.c",
        "modules/module_main.module.json",
        "modules/module_main.report.json"
      ]
    }
  ],
  "environment": [
    {
      "name": "VITARECOMP_EMIT_PC",
      "value": "1"
    },
    {
      "name": "VITARECOMP_EMIT_SPLIT",
      "value": null
    },
    {
      "name": "VITARECOMP_EMIT_SPLIT_INSNS",
      "value": null
    },
    {
      "name": "VITARECOMP_WHY",
      "value": null
    }
  ]
}
```

`null` records that a recognized knob was unset. Empty and zero
`VITARECOMP_EMIT_PC` values are not entry-eligible.

## Create and validate

All path arguments may be absolute at invocation time, but no absolute path is
persisted. `AggregateReport` and `OutputFile` are source-relative.

```powershell
pwsh -NoProfile -File tools/generated/New-GeneratedSourceProvenance.ps1 `
  -SourceRoot '<ignored-generator-output>' `
  -RuntimeManifest '<local-raw-runtime-manifest>' `
  -GeneratorExecutable '<framework-build>/armrecomp.exe' `
  -CommandSpecFile '<local-command-spec.json>' `
  -AggregateReport 'generated_registry.report.json' `
  -EntryModuleId 'module_main' `
  -OutputFile '.generated-source-provenance.json'

pwsh -NoProfile -File tools/generated/Test-GeneratedSourceProvenance.ps1 `
  -ProvenanceFile '<ignored-generator-output>/.generated-source-provenance.json' `
  -SourceRoot '<ignored-generator-output>' `
  -RuntimeManifest '<local-raw-runtime-manifest>' `
  -GeneratorExecutable '<framework-build>/armrecomp.exe'
```

Repeated creation with unchanged evidence produces identical bytes and leaves
the existing provenance timestamp untouched. Normal output and failures never
print local paths or hashes.

## Entry policy v1

Composition records two separate answers. `productionReady` requires zero
translation gaps. `structuralReady` and aggregate `entryEligible` require
complete, internally consistent metadata suitable for a controlled entry
attempt.

Provenance validation rejects the image set before staging or entry when any
module or aggregate evidence has:

- a body cut or unreported partition;
- an unclassified or unnamed trap;
- missing function-entry or PC instrumentation;
- incomplete structural metadata;
- missing, non-power-of-two, or mismatched TLS alignment/layout metadata;
- an unresolved, duplicated, or mismatched entry;
- sidecar/report/aggregate disagreement; or
- a missing, added, changed, misclassified, or unordered generated file.

Fully classified named traps are retained as explicit strict runtime traps.
They keep `productionReady` false but do not by themselves make an otherwise
complete image set ineligible for an instrumented entry attempt. They are
allowed only as the first named stop: `vita_guest_call` terminates at the first
one and never continues past it.

## Provenance-required staging

Legacy staging remains available by omitting the two provenance parameters.
Gate 1 staging opts in explicitly:

```powershell
pwsh -NoProfile -File tools/generated/Stage-GeneratedSources.ps1 `
  -SourceDir '<ignored-generator-output>' `
  -TargetDir '<ignored-stable-build-input>' `
  -RequiredProvenance '.generated-source-provenance.json' `
  -RuntimeManifest '<local-raw-runtime-manifest>'
```

The complete provenance check runs before the target is modified. Provenance
is then managed like every other staged file: unchanged bytes preserve
timestamps, a later legacy source removes stale managed provenance, and
unmanaged target files remain untouched.

## Opt-in CMake consumption

The public build leaves `KZMRECOMP_GENERATED_SOURCE_DIR` empty and compiles the
absent-bundle adapter. A local bundle build points that cache PATH at the
stable staging directory and supplies the same raw runtime manifest used for
provenance:

```powershell
cmake --preset windows-x64-debug --fresh `
  -DKZMRECOMP_GENERATED_SOURCE_DIR:PATH='<ignored-stable-build-input>' `
  -DKZMRECOMP_RUNTIME_MANIFEST:FILEPATH='<local-raw-runtime-manifest>'
```

Both paths must be absolute and either outside the checkout or below a known
ignored local root. Configure requires the staging manifest and provenance,
runs this validator without echoing local paths or hashes, and creates targets
only from the validated `generatedFiles` inventory. Every dependent build
revalidates the evidence and rejects changed provenance, changed staging
metadata, missing files, extra generated files, and digest drift.

The source-owned adapter exposes bundle presence and the expected raw-manifest
identity to title code without logging either private value. The host compares
that identity with the supplied raw manifest, consumes retained module bytes
through the strict framework loader/binder, and calls the generated entry at
most once only after every preparation gate succeeds. Builds with the
absent-bundle adapter continue to emit `title_not_implemented` and exit 9.

Hosted CI never sets either private cache path. Its generated-bundle coverage
constructs only synthetic evidence below ignored output, exercises successful
and rejected configure/build cases, and removes the evidence afterward.

Gate 1 is implemented and publicly/synthetically verified but remains
privately unclosed. No ignored local status file records a successful private
real-entry attempt. A clean return or a repeat-identical first named strict
stop is optional stronger evidence, not a hosted-CI requirement and not a
bootability claim.
