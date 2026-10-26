# Roadmap

Every milestone moves the project toward the goal in [GOAL.md](GOAL.md): a
statically recompiled *Killzone Mercenary* running natively on Windows with
DX12 and Vulkan at 30 fps or higher. Milestones close on observable
behavior of the real game, not on reports.

| Milestone | Outcome | State |
|---|---|---|
| [M0](#m0--foundation) | Build, host, renderers, content pipeline | ✅ Done |
| [M1](#m1--lift-and-link-decompile) | All game code lifted to C and linked into the host | ▶ **Current**: build path done, trap ranking and symbol map open |
| [M2](#m2--into-title-code) | The recompiled game boots and reaches its frame loop | ▶ **Current**: ordered module startup reaches GXP vertex-program creation |
| [M3](#m3--first-frame) | First game-rendered frame on DX12 and Vulkan | |
| [M4](#m4--main-menu) | Main menu with input, audio, FMV, and saves | |
| [M5](#m5--first-mission) | Mission 1 playable start to finish | |
| [M6](#m6--30-fps) | 30 fps or higher, p95, on both backends | |
| [M7](#m7--full-campaign) | Full campaign plus a one-command local build | |

Earlier documents call the strict title-entry work "Gate 1". In this
roadmap, that work is the M1 build path plus the first M2 tasks.

M6 is listed after M5 because optimization needs correct behavior to
measure. Performance is still designed in from M2: see
[Performance guardrails](#performance-guardrails).

## Working rules

These replace the old "close every gate before running" ordering.

- **Run-driven bring-up.** Run the game, fix the first failure, and run
  again. Title code may be entered before every trap is closed. A trap that
  is actually hit is the next task; one that is never hit can wait.
- **Fail loudly, never silently.** Unimplemented imports and untranslated
  instructions stop execution with a named diagnostic by default.
  `VITARECOMP_TRACE=1` (log and continue) is a bring-up aid only.
- **Named stubs are allowed.** An import may return a fixed plausible result
  while bring-up continues, if it:
  - is registered in a title stub table;
  - logs its name the first time it is called; and
  - appears as `stubbed` in the import inventory.

  Replacing stubs with real implementations is tracked work. What stays
  forbidden is a silent success path.
- **Extraction/reference, not a gate.** Vita3K is used only as described in
  [GOAL.md](GOAL.md#vita3ks-role-extraction-and-code-reference-only). Its
  runtime output is not review evidence or an acceptance criterion.
- **Content stays private.** Dumps, generated C, traces, captures, and
  shader caches stay in ignored local roots
  ([CONTENT_POLICY.md](CONTENT_POLICY.md)). Public CI stays source-only.
- **Tests follow fixes.** A framework or host bug found in the game gets a
  small synthetic regression test. New CI jobs, verification reports, and
  provenance documents are not milestone work.

## M0 — Foundation

✅ Done (2026-10-25). See [PROJECT_STATUS.md](PROJECT_STATUS.md) and the
historical [FOUNDATION_VERIFICATION.md](FOUNDATION_VERIFICATION.md).

- Framework fork with static ARM/Thumb → C recompiler, runtime/HLE
  foundation, shared GPU contract, and production DX12 and Vulkan backends.
- Windows host with explicit renderer selection and a clear/triangle
  self-test.
- Content pipeline: archive inspection, external Vita3K dump of three
  post-link runtime images, and a validated manifest with a read-only `app0:`
  mount.
- The lift of all three images compiles: 96.37% of executable bytes covered,
  99.897% of emitted instructions translated, 3,770 explicit traps remaining.

## M1 — Lift and link (decompile)

**Outcome:** one local build produces `kzmrecomp_host.exe` with all
generated game code linked in, plus a symbol map for working with it.

Exit criteria:

1. A single local command takes a validated manifest to a host build that
   links the generated C for all three runtime images. Public CI keeps
   building the no-content host.
2. Generated functions from all images share one deterministic dispatch
   table. Duplicate or overlapping keys fail the build.
3. The 3,770 traps are ranked by class and by distance from the boot path,
   and the top classes are fixed in the framework.
4. A local, ignored symbol map names functions from exports, the import NID
   database, and recovered strings/RTTI. Trap and crash diagnostics print
   those names.

Tasks:

- [x] **Framework:** compose multi-image output into one dispatch registry
      and generation report (`armrecomp compose`, generated-module ABI,
      framework `0e81bb4`, now pinned).
- [x] **Game:** the `KZMRECOMP_GENERATED_SOURCE_DIR` CMake option builds a
      provenance-validated generated bundle (generated C plus the composed
      registry) into the host. It is empty by default, and CI never sets
      it. See [generated-source-provenance.md](generated-source-provenance.md).
- [ ] **Game:** one local command that chains the existing steps: manifest
      validation, `armrecomp emit` per image, `armrecomp compose`,
      `New-GeneratedSourceProvenance.ps1`, provenance-required staging,
      configure, and build.
- [ ] **Framework:** rank the trap census by reachability from the module
      entries (compose already classifies traps by kind), then fix the
      largest NEON/VFP, branch-target, and transfer-shape classes on the
      boot path.
- [ ] **Framework/Game:** a symbol map format consumed by trap and dispatch
      diagnostics.
- [ ] **Framework:** build warnings-clean with Linux clang and GCC so that
      cloud sessions can test CPU/HLE changes. The fix is done and verified
      (zero warnings, 19/19 CTest on both compilers), but it is not pushed:
      this session has no push access to the fork. It also fixes two real
      bugs: NID names over 63 bytes were truncated into wrong HLE symbols,
      and FIOS overlay paths could be silently truncated. See
      [PROJECT_STATUS.md](PROJECT_STATUS.md#log).
- [ ] **Framework:** fix the Windows quality gate, which fails on any C/C++
      change because it hands LLVM's `git-clang-format.bat` to Python (fork
      CI run 40255206038). The fix is done, not pushed (same reason).

## M2 — Into title code

**Outcome:** the recompiled game starts, runs its static initialization and
module start-up, creates its threads, and repeatedly reaches its per-frame
display/GXM calls.

Exit criteria:

1. With a local generated bundle, title mode runs the real boot sequence.
   Exit 9 (`title_not_implemented`) remains only for public builds, which
   have no bundle.
2. Three consecutive clean runs reach the frame loop. That means at least 60
   iterations of the game's display flip or `sceGxmBeginScene` calls, with
   no trap.
3. An import inventory is written on every run. It lists each import as
   implemented, stubbed, or missing, with call counts, and nothing is
   missing on the boot path.
4. The ordered import sequence up to the first frame is identical across the
   three clean native runs. Any native-run deviation is a failure.

Tasks:

- [x] **Game:** derive the title memory plan from the validated load
      ranges, with disjoint heap, sysmem, kernel, main-stack, and TLS arenas
      (`src/game/title_config.*`).
- [x] **Game:** add dedicated GPU-mapped CDRAM and physically contiguous
      arenas. The measured plan is 96 MiB main, 128 MiB CDRAM, 16 MiB
      physically contiguous, and a 384 MiB maximum guest window.
- [x] **Framework:** strict module-set preflight/load, export/import
      binding by NID, checked main-stack/TLS/CPU entry preparation, and the
      `vita_guest_call` boundary that reports completion, an exit request,
      or the first strict failure (framework `0e81bb4`; see its
      `docs/ENTRY_STATE.md`).
- [x] **Game:** wire the host to those APIs. The title session loads the
      composed module set from retained bytes, binds imports, prepares
      stack/TLS/CPU, and calls the entry module's `module_start` once
      through `vita_guest_call`. Exit codes: 0 clean return, 11
      preparation failure, 12 first strict failure, 13 exit request
      ([NATIVE_HOST.md](NATIVE_HOST.md)).
- [x] **Run it:** the first real-bundle DX12 attempt validated and mounted
      all three modules, then exited 11 during module preflight with zero
      entry calls. The aggregate outcome is in
      [PROJECT_STATUS.md](PROJECT_STATUS.md#log).
- [x] **Content pipeline:** normalize identity relocation records before
      manifest generation while preserving 1,516 validated post-link variable
      records. The real set now reports zero changed, unsupported, or
      out-of-file records.
- [x] **Run it:** the preserved three-module bundle bound, prepared the main
      stack, called translated title entry once, and exited 12 at the named
      strict import `nid_BE43BB07::nid_BFE02B3A` from `0x818C37A8`.
- [x] **Run it:** regenerate the preserved bundle with the pinned public
      VitaSDK 3.60 NID database. The import resolved to the existing
      `SceLibc::__cxa_set_dso_handle_main` HLE, and three consecutive DX12 WARP
      runs called the selected entry module and returned cleanly with exit 0.
      Supporting modules are not started yet, so no frame loop is claimed.
- [x] **Game:** run `module_start` for the support modules in the retained
      dependency order before the entry module, preserving threads created by
      earlier starts within one strict guest boundary.
- [x] **Run it:** the ordered three-module DX12 WARP run now passes measured
      process/TLS/libc/AppUtil startup, partitioned Sysmem, GXM initialization,
      mappings, context and shader-patcher registration, and GXP reflection.
      It stops explicitly at
      `SceGxm::sceGxmShaderPatcherCreateVertexProgram`; no frame loop or shader
      translation is claimed.
- [ ] **Game:** print the first strict failure with its symbol name once
      the M1 symbol map exists.
- [ ] **Framework:** grow kernel, thread, synchronization, sysmem, I/O,
      FIOS2, ULT, and libc coverage as the run asks for it. That includes
      the ULT fiber scheduler and real asynchronous FIOS2 if the game
      depends on them.
- [ ] **Game:** writable, path-contained `ux0:`-style mounts for saves and
      cache under a user-data directory.
- [ ] **Framework:** return the documented offline results for the
      net/NP/trophy imports.

## M3 — First frame

**Outcome:** the first frame the game itself renders, such as a logo or
splash screen, is presented through DX12 and then Vulkan.

Exit criteria:

1. Both backends produce a valid, nonblank first frame and their captures are
   visually equivalent to each other, with the metric chosen when the frame
   exists.
2. Every `sceGxm` call on the path to that frame is implemented; none are
   stubbed.
3. GXP programs on that path are translated by our USSE → HLSL translator
   and compiled with DXC to DXIL and SPIR-V. There is no prebuilt or
   hand-written per-title shader.

Tasks:

- [ ] **Framework:** guest `sceGxm` ABI. Start with the 85-odd shallow state
      setters and accessors, then memory mapping, contexts, render targets,
      color/depth surfaces, sync objects, and the display queue.
- [ ] **Framework:** `sceDisplay` flips into the host swapchain present,
      with vblank timing.
- [ ] **Framework:** GXP container parsing and the reflection queries the
      game uses.
- [ ] **Framework:** USSE decoder and translator to HLSL. Grow it one
      instruction class at a time from the shaders the game actually
      registers. Unsupported instructions fail with a census.
- [ ] **Framework:** scene, draw, and mid-scene-flush semantics mapped onto
      DX12/Vulkan render passes. Guest surfaces go through a surface/texture
      cache with explicit invalidation on CPU writes.
- [ ] **Framework:** texture formats. Swizzled and tiled layouts, and PVRTC
      (no desktop GPU support, so decode or transcode it), plus the UBC/BC
      formats.
- [ ] **Game/Framework:** runtime shader translation with a persistent local
      cache keyed by GXP hash, and a DX12/Vulkan pipeline cache.

## M4 — Main menu

**Outcome:** boot to the main menu with sound and FMV, navigate it with a
controller or keyboard/mouse, and change settings that persist, on both
backends.

Tasks:

- [ ] **Input:** `sceCtrl` from XInput/GameInput and keyboard/mouse.
      `sceTouch` front and rear panels mapped to buttons, mouse, or
      gestures. `sceMotion` stubbed or mapped.
- [ ] **Audio:** `sceAudioOut` through WASAPI. `sceNgs` voices and mixing.
      ATRAC9 decode, using an independent decoder with a compatible license.
- [ ] **Movies:** `sceAvPlayer`, decoding H.264/AAC through Media
      Foundation, with frames delivered as guest textures.
- [ ] **Saves/dialogs:** `sceAppUtil`/savedata into the user-data
      directory. Common dialogs and IME get native minimal implementations.
- [ ] **Game:** a settings file for renderer, adapter, resolution scale,
      bindings, and audio device.

## M5 — First mission

**Outcome:** mission 1 can be played from start to finish, saved, and
reloaded on both backends, without crashes and with correct world, HUD,
lighting, and post-processing.

Tasks:

- [ ] Translate the remaining GXP/USSE instructions as gameplay shaders
      reach them.
- [ ] Render-target feedback, readbacks, and CPU access to GPU memory that
      the engine uses, done without whole-frame stalls.
- [ ] Touch-driven gameplay actions, such as melee and hacking, mapped to
      controller and mouse.
- [ ] Named checkpoints (for example *mission 1 loaded*, *first combat*,
      *mission complete*), each reproducible from a clean user-data
      directory on both backends.

## M6 — 30 fps

**Outcome:** the definition of done's performance criterion D3 holds: p95
frame time of 33.3 ms or less, and no stall over 100 ms, on the reference PC,
on both backends.

Tasks:

- [ ] **Benchmark harness:** fixed scenes from M5 checkpoints, a frame-time
      capture, a CPU/GPU split, and a JSON result written locally.
- [ ] **Guest memory fast path:** one reserved host region (base + offset)
      with guard pages instead of a bounds-checked call per access. Checked
      accessors stay for debug builds and HLE boundaries.
- [ ] **Dispatch:** O(1) indirect-call lookup instead of binary search, and
      direct calls wherever the target is static.
- [ ] **Threads:** measure whether the one-guest-thread-at-a-time baton
      scheduler fits the frame budget. If it does not, run guest threads on
      host threads in parallel, keeping exclusive-monitor correctness.
- [ ] **GPU:** batch submissions, keep CPU/GPU sync minimal, precompile
      pipelines from the shader cache, and avoid per-frame texture
      re-uploads.
- [ ] **Frame pacing:** present timing that matches the game's vblank
      expectations. Optional uncapped or 60 fps mode where game logic
      allows (stretch).

## M7 — Full campaign

**Outcome:** the whole single-player campaign is playable on both backends,
and a user can produce a build from their own dump with one documented
command sequence (D5).

Tasks:

- [ ] Every campaign mission reaches *mission complete* on both backends.
- [ ] One-command local pipeline: inspect → external extraction → manifest
      → lift → build → run. It records the tool revisions and never
      uploads private output.
- [ ] Stretch goals: higher internal resolution, a 60 fps mode, and
      widescreen UI fixes, through title hooks in `src/game`.

## Performance guardrails

These apply from M2 so that M6 does not mean re-architecting:

- Track how long the generated CPU code takes per game frame once the frame
  loop runs (M2). Track GPU frame time from the first frame (M3).
- Bring-up uses RelWithDebInfo. Debug-only checks must not become the only
  supported configuration.
- New runtime paths avoid per-call allocation, global locks on hot paths,
  and synchronous GPU readback.

## Open decisions for the owner

- **Title hooks and addresses.** Hooks and patches (frame pacing,
  resolution, bug fixes) need to name game functions. Recommendation: allow
  function addresses and names in tracked hook configuration. Those are
  functional facts. The content ban still covers code bytes, data, and
  generated C.
- **Porting from Vita3K.** The default is "reference only, write our own".
  Decide case by case whether a small, attributed GPL port is acceptable,
  for example USSE decode tables.
