# Project goal

This page is the reference for deciding what to work on. If a task does not
move the project toward the goal below, it is off-track. Do not start it
unless the project owner explicitly asks for it.

## The goal

**Run *Killzone Mercenary* (PCSA00107) natively on Windows x64, with
Direct3D 12 and Vulkan renderers, at 30 fps or higher.** The game is produced
by statically recompiling the user's own copy of the game.

The pipeline that gets there:

1. **Decompile.** Lift every runtime code module of the game (the eboot and
   its SUPRX modules) from ARM/Thumb machine code into C with `armrecomp`.
   Pair that C with a function/symbol map that is good enough to debug, hook,
   and patch the game.
2. **Recompile.** Compile that C with MSVC and link it with the `vitarecomp`
   runtime/HLE and this repository's Windows host into one native executable.
3. **Run.** Implement the firmware surface the game actually calls (kernel,
   threads, files, `sceGxm`, GXP shaders, display, audio, input, savedata,
   movies) natively, until the game boots, renders, and plays.
4. **Run fast enough.** Hold 30 fps or better in real gameplay on both
   renderers.

"Decompile" here means a complete, buildable static lift plus enough symbol
knowledge to work with it. It does not mean a hand-written, byte-matching
source decompilation.

## Definition of done

The project is done when all of these hold on a reference PC:

| # | Criterion | How it is measured |
|---|---|---|
| D1 | The game boots from a user-supplied dump to the main menu, then into and through the single-player campaign | Named checkpoints in [ROADMAP.md](ROADMAP.md), reproduced from a clean user-data directory |
| D2 | Both renderers work: `--renderer=dx12` and `--renderer=vulkan` | The same checkpoints pass on each backend, with no backend-specific title hacks |
| D3 | 30 fps or higher | p95 frame time of 33.3 ms or less, and no stall over 100 ms, across the benchmark scenes, on each backend |
| D4 | Native execution only | No interpreter, no JIT, no emulator, and no Vita3K in the shipped process |
| D5 | Reproducible locally | One documented command sequence turns a lawful dump into a runnable local build |
| D6 | Input, audio, video, saves | Controller plus keyboard/mouse, game audio, FMV playback, and saves in a user-data directory all work |

Reference PC (the minimum the 30 fps target is held to): Windows 10/11 x64,
a 4-core/8-thread CPU at 3 GHz or faster, 8 GB of RAM, and a GPU with
D3D12 feature level 12_0 and Vulkan 1.3, roughly GTX 1060 or RX 580 class.
The internal resolution is the Vita's native 960x544. Higher resolutions and
60 fps are stretch goals and never block D3.

## Non-goals

- **A Vita3K fork, or Vita3K features.** See the next section.
- Online multiplayer, PSN/NP, trophies, and commerce. The game's online
  services are gone. Their imports return the documented "not
  available/offline" firmware results so that the offline game paths run.
- Other titles, or a general-purpose Vita runtime. The framework stays
  reusable because that is cheap, but no work is done only for other games.
- Other host platforms (Linux, macOS, ARM64), or renderers other than DX12 and
  Vulkan.
- Distributing game data, keys, generated title code, or builds. See
  [CONTENT_POLICY.md](CONTENT_POLICY.md).
- Reports, audits, provenance manifests, or extra CI gates as deliverables in
  their own right. They are only worth doing when they unblock a milestone.

## Vita3K's role: extraction and code reference only

Vita3K is used in two ways and no others:

1. **Content preparation:** installing and decrypting the user's copy, and
   dumping post-link runtime ELF images. The two-patch series in
   [`patches/vita3k`](../patches/vita3k/README.md) is frozen to that purpose.
2. **Code reference:** reading its source and documentation to understand GXM,
   USSE/GXP, and firmware behavior. We then write our own implementation in
   `vitarecomp` or this repository.

Vita3K currently reaches only the game menu and is not a useful visual or
behavioral oracle. Its screenshots, import traces, return values, and guest
state are therefore not review evidence or milestone acceptance gates.

We do **not** maintain a Vita3K fork, add Vita3K features, fix Vita3K bugs as
project work, upstream changes to Vita3K, or link, vendor, or launch Vita3K
from the native host. Any new Vita3K patch beyond the existing dump series
is out of scope unless the frozen extraction workflow itself breaks and the
owner explicitly approves the repair.

Both Vita3K and this project are GPL-2.0-or-later, so porting a small,
self-contained piece with attribution is legally possible. The current
policy is still "write our own". Any port is an explicit owner decision,
made case by case.

## Where work lives

| Work | Repository |
|---|---|
| Recompiler, runtime, title-neutral HLE (including the `sceGxm` bridge and GXP/USSE translator), shared GPU contract, DX12/Vulkan backends | Framework fork [`Tzeentchnet/vitarecomp`](https://github.com/Tzeentchnet/vitarecomp), pinned here as `third_party/vitarecomp` |
| Windows host, title boot sequence, title memory map, Killzone-specific hooks and patches, input mapping, settings, local build orchestration | This repository |
| Extraction and source reading | External Vita3K checkout, never in either repository |

The framework fork is based on
[`sp00nznet/vitarecomp`](https://github.com/sp00nznet/vitarecomp). It
branched at `6ed4a5c` (tag `upstream-start-6ed4a5c5`). Upstream has no newer
commits, so the fork is the canonical framework. Framework changes land there
first, then this repository bumps the submodule pin and
`config/framework.commit` together.

## How to choose the next task

1. Find the lowest open milestone in [ROADMAP.md](ROADMAP.md).
2. Pick work that moves one of its exit criteria. Prefer whatever unblocks the
   next real run of the game.
3. Be run-driven: execute the game, take the first failure (trap, missing
   import, bad draw), fix that one thing, and run again. Do not try to
   pre-close every possible failure before running.
4. Record what changed in [PROJECT_STATUS.md](PROJECT_STATUS.md) in a few
   lines. Do not write a separate verification report.
