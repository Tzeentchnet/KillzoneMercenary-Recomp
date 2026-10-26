# Working on this repository

Read [docs/GOAL.md](docs/GOAL.md) first. In one line:
**statically recompile *Killzone Mercenary* and run it natively on Windows
with DX12 and Vulkan at 30 fps or higher.** Every task must move a
milestone exit criterion in [docs/ROADMAP.md](docs/ROADMAP.md). The current
milestone is in [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md).

## Staying on track

Before starting, name the milestone and exit criterion the task moves. If
you cannot name one, stop and ask the owner.

On-track work:

- linking generated code, boot sequence, memory map;
- missing imports and HLE behavior the game actually calls;
- trap classes the game actually hits;
- `sceGxm`, GXP, and USSE work;
- display, audio, input, movies, and saves;
- frame-time work once a frame exists;
- small regression tests for bugs found along the way.

Off-track work. Do not do it unless the owner explicitly asks:

- Vita3K features, Vita3K bug fixes, rebasing the dump patches, or any
  Vita3K fork work. Vita3K is only an external oracle and reference
  ([GOAL.md](docs/GOAL.md#vita3ks-role-oracle-and-reference-only)).
- New or reworded verification reports, provenance manifests, migration
  tables, audit write-ups, or "checkpoint" documents.
- More CI jobs, more pinned tools, stricter redaction, or more guard rules,
  when no milestone needs them.
- Re-architecting the framework/game split, or the content tools, when no
  milestone needs it.
- Support for other titles, other OSes, or other renderers.
- Pre-closing every theoretical trap or import before running the game. Work
  run-driven instead (see the roadmap's working rules).

When a task drifts, finish the smallest useful piece, write the drift into
the [PROJECT_STATUS.md](docs/PROJECT_STATUS.md) log as a follow-up, and stop.

## Non-negotiables

- No game content in Git: dumps, ELF/SELF, PSARC, assets, generated C,
  traces, captures, shader caches, saves, keys. Keep them in ignored local
  roots ([docs/CONTENT_POLICY.md](docs/CONTENT_POLICY.md)). Before
  committing, run `tools/content/Guard-PrivateContent.ps1` when PowerShell
  is available.
- No interpreter, JIT, or emulator in the shipped process. Renderer
  selection never falls back.
- Unsupported behavior fails with a named diagnostic. A named, logged,
  inventoried stub is acceptable during bring-up. A silent success is not.

## Where code goes

- Recompiler, runtime, HLE (`sceGxm`, GXP/USSE, audio, input), and GPU
  backends go in the framework fork `third_party/vitarecomp`
  (`Tzeentchnet/vitarecomp`). Land the change there, then bump the
  submodule and `config/framework.commit` together in this repository.
- The Windows host, title boot and memory map, title hooks, settings, and
  local build orchestration go here: `src/host`, `src/game`, `tools/`.

## Building and testing

Windows (full build: host, DX12, Vulkan):

```powershell
$env:VITARECOMP_DXC_ROOT = '<dxc-package-root>'
cmake --preset windows-x64-debug
cmake --build --preset windows-x64-debug
ctest --preset windows-x64-debug
```

Linux cloud containers cannot build the Win32 host or the DX12/Vulkan
backends. They can build and test the whole framework (recompiler, runtime,
and GPU contract tests) once the pending patches in
[`patches/vitarecomp`](patches/vitarecomp/README.md) are applied. Do that in
a scratch worktree so the submodule stays at its pin:

```sh
git -C third_party/vitarecomp worktree add --detach <scratch>/fw-src HEAD
git -C <scratch>/fw-src am "$PWD"/patches/vitarecomp/*.patch
cmake -G Ninja -S <scratch>/fw-src -B <scratch>/fw -DCMAKE_BUILD_TYPE=Debug
cmake --build <scratch>/fw && ctest --test-dir <scratch>/fw    # 19/19, clang or GCC
```

Without the patches, the pinned framework fails `-Werror` on Linux. Keep
build directories outside the repository (`out/` is ignored).

Docs rules that CI enforces: relative Markdown links must resolve, there is
no trailing whitespace, and each file ends with a newline.
`MIGRATION.md` and `docs/CONTENT_POLICY.md` must stay where they are.

## Recording progress

Update the milestone checkboxes in `docs/ROADMAP.md`, and add one or two
lines to the log in `docs/PROJECT_STATUS.md`. That is the whole reporting
obligation.
