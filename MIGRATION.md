<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Prior AOT material migration

This manifest records the curated migration from the verified 2026-10-25
`killzone-aot` snapshot. The source branch used Vita3K commit
`ee50eb8644b4184996047f04406486281586935b` as its merge base and ended at
`c505989f8c03dcae922fe93f09b0d30dac21c230`. The snapshot contains the exact
current bytes of 45 changed public source/documentation paths, including ten
uncommitted paths.

No retail content, generated title code, title addresses, traces, private
paths, private-input hashes, build output, or Vita3K source tree was copied.
Project-authored migration files are GPL-2.0-or-later. The Vita3K patches are
GPL-2.0-or-later derivative changes and retain the recorded human authorship.

## Destination notation and dispositions

- **game:** this repository.
- **framework:** the canonical `vitarecomp` repository pinned by the game
  submodule.
- **Ported:** adapted code, documentation, test, fixture, or patch is present.
- **Reference:** only a curated fact or provenance record was retained.
- **Deferred:** a precise machine-readable vector names a future canonical
  integration point; it is not claimed as executing.
- **Rejected:** intentionally omitted from both production repositories.

## Migration outputs

Game repository:

- `docs/research/{README,FINDINGS,ARCHITECTURE-HANDOFF,ASSET-FORMATS}.md`
- `tools/generated/Stage-GeneratedSources.ps1` and its synthetic test
- `patches/vita3k/{README.md,series,0001-*.patch,0002-*.patch}`
- this manifest, repository links in `README.md`, and the patch EOL rule in
  `.gitattributes`

Framework repository:

- `docs/PRIOR_AOT_MIGRATION.md`
- `tests/fixtures/prior-aot/migration-vectors.json`
- `tests/test_prior_aot.c` and `tests/test_dispatch_diagnostic.c`
- test registration in `tests/CMakeLists.txt` and a documentation link in
  `README.md`

## Source-by-source manifest

Every path below is relative to the prior repository and names its
current-snapshot version, not merely its `HEAD` version.

| # | Source path | Destination | Disposition | Evidence |
|---:|---|---|---|---|
| 1 | `CMakeLists.txt` | `framework:tests/CMakeLists.txt`; this manifest | Reference / rejected old build wiring | S, F, M |
| 2 | `README.md` | `game:docs/research/README.md`; `game:docs/research/ARCHITECTURE-HANDOFF.md` | Ported and curated | S, Q, M |
| 3 | `docs/ASSET_FORMATS.md` | `game:docs/research/ASSET-FORMATS.md` | Ported and curated | S, Q, M |
| 4 | `docs/FINDINGS.md` | `game:docs/research/FINDINGS.md`; `framework:docs/PRIOR_AOT_MIGRATION.md` | Ported and curated | S, J, Q, M |
| 5 | `docs/TODO.md` | `game:docs/research/ARCHITECTURE-HANDOFF.md`; `framework:tests/fixtures/prior-aot/migration-vectors.json` | Ported verified cases; rejected as a live tracker | S, J, Q, M |
| 6 | `docs/UPSTREAM.md` | `game:docs/research/README.md`; `game:patches/vita3k/README.md` | Ported provenance; rejected stale workflow | S, P, Q, M |
| 7 | `docs/killzone-aot.md` | `game:docs/research/ARCHITECTURE-HANDOFF.md`; `framework:docs/PRIOR_AOT_MIGRATION.md` | Ported architecture facts; rejected hybrid production design | S, Q, M |
| 8 | `tools/stage-aot-sources.ps1` | `game:tools/generated/Stage-GeneratedSources.ps1`; `game:tests/Test-StageGeneratedSources.ps1` | Ported and generalized | S, T, G, M |
| 9 | `tools/vita-recomp/CMakeLists.txt` | `framework:tests/CMakeLists.txt` | Reference for adapted tests; rejected duplicate tool build | S, F, M |
| 10 | `tools/vita-recomp/README.md` | `game:docs/research/ARCHITECTURE-HANDOFF.md`; `framework:docs/PRIOR_AOT_MIGRATION.md` | Ported contracts; rejected old operator workflow | S, Q, M |
| 11 | `tools/vita-recomp/include/vita_recomp/analysis.h` | `framework:tests/fixtures/prior-aot/migration-vectors.json`; `framework:docs/PRIOR_AOT_MIGRATION.md` | Deferred mode/image-set contracts; rejected duplicate API | S, J, M |
| 12 | `tools/vita-recomp/include/vita_recomp/aot.h` | `framework:tests/test_prior_aot.c`; `framework:tests/test_dispatch_diagnostic.c`; fixture above | Ported represented state/diagnostics; deferred full ABI; rejected runtime | S, F, J, M |
| 13 | `tools/vita-recomp/include/vita_recomp/codegen.h` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Deferred emitter contracts; rejected duplicate API | S, J, M |
| 14 | `tools/vita-recomp/include/vita_recomp/image.h` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Deferred image-set contracts; rejected duplicate API | S, J, M |
| 15 | `tools/vita-recomp/src/analysis.cpp` | `framework:tests/fixtures/prior-aot/migration-vectors.json`; `framework:docs/PRIOR_AOT_MIGRATION.md` | Deferred deterministic image/mode/table-branch cases; rejected implementation | S, J, M |
| 16 | `tools/vita-recomp/src/aot.cpp` | `framework:tests/test_prior_aot.c`; `framework:tests/test_dispatch_diagnostic.c`; fixture above | Ported canonical state/memory/strict-miss tests; deferred monitor/full state; rejected runtime | S, F, J, M |
| 17 | `tools/vita-recomp/src/codegen.cpp` | `framework:tests/fixtures/prior-aot/migration-vectors.json`; `framework:docs/PRIOR_AOT_MIGRATION.md` | Deferred control-flow/VFP/NEON semantics; rejected emitter | S, J, M |
| 18 | `tools/vita-recomp/src/decoder.h` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Deferred precise instruction-shape cases; rejected decoder | S, J, M |
| 19 | `tools/vita-recomp/src/image.cpp` | `framework:tests/test_prior_aot.c`; `framework:tests/fixtures/prior-aot/migration-vectors.json` | Ported checked-access vectors; deferred image composition; rejected loader | S, F, J, M |
| 20 | `tools/vita-recomp/src/main.cpp` | `framework:tests/fixtures/prior-aot/migration-vectors.json`; `framework:docs/PRIOR_AOT_MIGRATION.md` | Deferred deterministic report/orchestration behavior; rejected CLI | S, J, M |
| 21 | `tools/vita-recomp/tests/dynarmic_tests.cpp` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Ported vectors as deferred oracle cases; rejected Dynarmic dependency | S, J, M |
| 22 | `tools/vita-recomp/tests/recomp_tests.cpp` | `framework:tests/test_prior_aot.c`; `framework:tests/test_dispatch_diagnostic.c`; fixture above | Ported independent canonical tests and exact deferred vectors | S, F, J, M |
| 23 | `vita3k/android/jni/native_config.cpp` | None | Rejected Android configuration coupling | S, P, M |
| 24 | `vita3k/app/src/app_init.cpp` | None | Rejected application/GUI dump toggle wiring | S, P, M |
| 25 | `vita3k/config/include/config/config.h` | `game:patches/vita3k/0002-add-headless-dump-elfs-switch.patch` | Ported generic dump flag; rejected AOT options | S, P, M |
| 26 | `vita3k/config/include/config/settings.h` | None | Rejected persistent GUI setting | S, P, M |
| 27 | `vita3k/config/include/config/state.h` | None | Rejected GUI state coupling | S, P, M |
| 28 | `vita3k/config/src/config.cpp` | `game:patches/vita3k/0002-add-headless-dump-elfs-switch.patch` | Ported explicit headless switch; rejected AOT CLI | S, P, M |
| 29 | `vita3k/config/src/settings.cpp` | None | Rejected persistent GUI setting | S, P, M |
| 30 | `vita3k/cpu/CMakeLists.txt` | `framework:docs/PRIOR_AOT_MIGRATION.md` | Reference; rejected bridge build integration | S, F, M |
| 31 | `vita3k/cpu/include/cpu/aot.h` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Deferred optional oracle contract; rejected bridge header | S, J, M |
| 32 | `vita3k/cpu/include/cpu/common.h` | `framework:tests/test_prior_aot.c`; fixture above | Ported represented-state knowledge; deferred complete state | S, F, J, M |
| 33 | `vita3k/cpu/include/cpu/functions.h` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Reference/deferred CPU selection seam; rejected bridge declarations | S, J, M |
| 34 | `vita3k/cpu/include/cpu/impl/dynarmic_cpu.h` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Deferred oracle state knowledge; rejected production dependency | S, J, M |
| 35 | `vita3k/cpu/include/cpu/impl/interface.h` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Deferred canonical CPU-selection seam; rejected interface changes | S, J, M |
| 36 | `vita3k/cpu/src/aot.cpp` | `framework:tests/test_prior_aot.c`; `framework:tests/test_dispatch_diagnostic.c`; fixture above | Ported independent semantics; deferred monitor/oracle; rejected bridge | S, F, J, M |
| 37 | `vita3k/cpu/src/cpu.cpp` | `framework:docs/PRIOR_AOT_MIGRATION.md` | Reference/deferred CPU-selection decision; rejected backend switch | S, M |
| 38 | `vita3k/cpu/src/dynarmic_cpu.cpp` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Deferred state/oracle cases; rejected Dynarmic modifications | S, J, M |
| 39 | `vita3k/cpu/tests/aot_tests.cpp` | `framework:tests/test_prior_aot.c`; `framework:tests/fixtures/prior-aot/migration-vectors.json` | Ported canonical synthetic cases; deferred bridge-only cases | S, F, J, M |
| 40 | `vita3k/gui-qt/src/settings_dialog.cpp` | None | Rejected GUI coupling | S, P, M |
| 41 | `vita3k/gui-qt/src/settings_dialog_tooltips.cpp` | None | Rejected GUI coupling | S, P, M |
| 42 | `vita3k/interface.cpp` | `game:patches/vita3k/0002-add-headless-dump-elfs-switch.patch` | Ported early generic dump-flag wiring; rejected AOT backend wiring | S, P, M |
| 43 | `vita3k/kernel/include/kernel/state.h` | `framework:tests/fixtures/prior-aot/migration-vectors.json`; `framework:docs/PRIOR_AOT_MIGRATION.md` | Deferred shared-monitor ownership; rejected emulator state changes | S, J, M |
| 44 | `vita3k/kernel/src/kernel.cpp` | `framework:tests/fixtures/prior-aot/migration-vectors.json` | Deferred monitor initialization/ownership; rejected emulator changes | S, J, M |
| 45 | `vita3k/kernel/src/load_self.cpp` | `game:patches/vita3k/0001-dump-modules-after-linking.patch` | Ported generic post-link dump ordering | S, P, M |

## Current uncommitted fixes included

The snapshot's ten dirty paths were `docs/FINDINGS.md`, `docs/TODO.md`,
`tools/vita-recomp/README.md`, `tools/vita-recomp/include/vita_recomp/analysis.h`,
`tools/vita-recomp/src/analysis.cpp`, `tools/vita-recomp/src/codegen.cpp`,
`tools/vita-recomp/src/decoder.h`, `tools/vita-recomp/src/main.cpp`,
`tools/vita-recomp/tests/dynarmic_tests.cpp`, and
`tools/vita-recomp/tests/recomp_tests.cpp`.

Their current (not `HEAD`) behavior is represented by the curated documents
and fixture IDs for conditional A32 exit fallthrough, `BLX LR`
capture-before-link, aligned-PC `TBB`, single-lane `VST1` rejection, IT
immediate move, wide non-writeback `LDM`, FPSCR flush-to-zero, deterministic
multi-image behavior, ARM/Thumb keys, and ordinary-write exclusive-reservation
invalidation. Cases blocked on canonical CPU selection remain explicitly
`deferred-pending-canonical-cpu-selection`; they are not reported as executing.

## Rejected material

- The complete C++ recompiler/runtime and its production build wiring.
- The complete Vita3K tree, GUI/Android settings, and hybrid AOT CPU backend.
- The historical live TODO as a project tracker.
- The unrelated PS2Recomp note embedded in that TODO.
- Private inputs, generated title source, traces, title-specific bytes or
  addresses, hashes tied to private paths, and build artifacts.

## Validation evidence

| Code | Evidence |
|---|---|
| S | Snapshot `validation/report.json` reports success, exact branch/index/worktree capture, 45 copied changed paths, ten dirty paths, and no private/build payload. |
| M | The manifest audit compares `payload/source-paths.txt` with this table and requires exactly one row for each of all 45 paths. |
| T | `tests/Test-StageGeneratedSources.ps1` passes invalid-source safety, initial/no-op/delta sync, add/remove, unmanaged-file preservation, deterministic manifest, and overlap rejection. |
| F | The framework Debug build includes both migrated test targets; targeted and full `ctest` runs pass. |
| J | `migration-vectors.json` parses as JSON and all vectors carry an explicit executed/deferred status plus future integration point where required. |
| P | Both patches apply in order with plain `git apply` to the four relevant files from pinned Vita3K base; the patched loader matches the verified snapshot's post-link implementation. |
| G | The game repository's synthetic guard regression and explicit guard scan of all migrated paths pass. |
| Q | Hygiene scans find no prohibited payload, machine-private path, generated title code, trace, private hash, or address literal in migrated material. |

The optional AOT CPU bridge is deliberately outside
[`patches/vita3k/series`](patches/vita3k/series). Its future oracle adapter is
blocked only where the canonical CPU/mode-selection seam is required; all
independent migration work is complete.
