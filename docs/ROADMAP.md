# Post-foundation roadmap

The verified foundation is complete. The following backlog is ordered by
dependency and closes only on measurable evidence. It contains no schedule or
time estimate. Until gate 1 closes, normal title mode must keep the explicit
exit-9 `title_not_implemented` boundary.

Every gate inherits these rules:

- private inputs, generated title code, traces, captures, and packages stay in
  ignored local roots;
- unsupported CPU, import, HLE, GPU, and service behavior fails explicitly;
- Vita3K may supply external extraction or oracle evidence but is never a
  production dependency;
- DX12 and Vulkan are selected explicitly and never fall back to each other;
  and
- public synthetic regression coverage accompanies every private measurement.

## 1. Strict title-entry execution

**Goal:** call the real translated module entry only after all preconditions
are proven.

**Closure gates:**

- define a deterministic local generated-source provenance manifest recording
  exact framework revision, input-manifest identity, generator command,
  reports, partitions, and generated-file inventory without publishing
  private paths or hashes;
- account for every generated report trap, body cut, unreported partition,
  duplicate key, and unresolved entry transfer under a documented entry policy;
- implement and test module load, relocation, TLS, stack, CPU state, export,
  import, and entry-address preconditions;
- add public malformed/synthetic tests for each rejected precondition;
- prove the host cannot call title code when any gate fails; and
- replace exit 9 only when one instrumented entry call completes or reaches a
  named strict failure with no interpreter, JIT, emulator, or success stub.

## 2. Imports, threading, and filesystem startup

**Goal:** reach a reproducible early startup checkpoint through the standalone
runtime.

**Closure gates:**

- derive the complete reachable startup import inventory and classify every
  import as implemented, documented firmware error, or explicit unsupported;
- exercise thread/TLS creation, synchronization, callbacks, teardown, and
  restart without deadlock or leaked runtime objects;
- serve `app0:` only through the read-only VFS and define separate,
  path-contained writable mounts for local save/cache behavior;
- make scheduler, clock, and filesystem observations deterministic enough for
  a repeatable startup trace; and
- reach the same named startup checkpoint on repeated clean runs with zero
  silent import success.

## 3. GXM scene capture

**Goal:** translate guest GXM calls into a renderer-neutral scene description
before implementing title shaders.

**Closure gates:**

- implement the measured guest `sceGxm` object, memory-mapping, context,
  state, scene, draw, sync, and display-queue ABI needed by the first scene;
- validate every guest structure and range before creating a host object;
- capture one deterministic, redacted scene/command inventory in an ignored
  local root;
- replay an equivalent public synthetic scene through the shared GPU contract;
  and
- reject unsupported GXM state or ordering rather than dropping it.

## 4. GXP/USSE shader integration

**Goal:** turn guest shader programs into the one canonical host shader path.

**Closure gates:**

- parse and bounds-check GXP containers plus the reflection queries used by
  the title;
- translate measured USSE instructions and resource bindings to canonical
  HLSL with an explicit unsupported census;
- compile that HLSL with pinned DXC `1.8.2505.32` to both DXIL and SPIR-V;
- add public synthetic parser/reflection/compiler tests and deterministic
  private shader-report checks; and
- render the captured scene without a prebuilt private shader cache or
  backend-specific title patch.

## 5. DX12/Vulkan title-frame parity

**Goal:** prove both production backends implement the same title-facing GPU
contract.

**Closure gates:**

- replay identical captured scene inputs through explicitly selected DX12 and
  Vulkan backends;
- compare deterministic readbacks using a documented exact or tolerance-based
  metric;
- pass resize, minimize/restore, resource lifetime, device teardown, and
  repeated startup tests on both paths;
- pass validation/debug diagnostics where the host environment exposes them;
  and
- prove unavailable backend, adapter, shader capability, and validation
  requests fail without selecting the other backend.

## 6. Audio, input, save, and movie services

**Goal:** add user-facing services as independent, measurable contracts.

**Closure gates:**

- inventory the exact title imports and data flows for audio, controller/touch,
  savedata/dialog policy, and movie/codec playback;
- implement each service behind a host-neutral boundary with synthetic tests,
  lifecycle tests, and explicit unsupported behavior;
- keep save data and caches in an explicit external user-data root;
- demonstrate deterministic input injection and audio/movie decode fixtures
  that contain no retail payload; and
- close each service independently rather than using a global “implemented”
  claim.

Networking, NP/sign-in, commerce, and other online platform behavior stay
deferred until separately scoped; no offline success stubs may impersonate
them.

## 7. Gameplay progression

**Goal:** advance through named, reproducible gameplay checkpoints.

**Closure gates:**

- define checkpoints by observable state, not elapsed time;
- record the imports, strict traps, renderer errors, and service gaps at each
  checkpoint in redacted local reports;
- reproduce each checkpoint from a documented clean state on both renderers;
- add a public synthetic regression for every framework or host defect found;
  and
- make regressions fail before promoting the next checkpoint.

This gate does not begin with or imply a claim of general bootability or
playability.

## 8. Correctness-first performance

**Goal:** optimize only measured native bottlenecks after the corresponding
behavior is correct.

**Closure gates:**

- define deterministic CPU, shader-translation, frame, memory, and startup
  benchmarks with hardware/environment metadata;
- establish baselines and regression thresholds before changing algorithms;
- preserve strict checks, deterministic generation, and backend parity under
  optimization;
- identify profile evidence for every optimization; and
- keep software/WARP correctness coverage even when hardware paths are tuned.

## 9. Local-generation packaging

**Goal:** let a user produce a native package locally from their own lawful
content without publishing derived private outputs.

**Closure gates:**

- provide one clean-clone command sequence for inspection, external
  extraction, manifest creation, static generation, staging, compile, and
  package assembly;
- make every tool and revision input explicit and provenance-recorded;
- prove two runs from identical local inputs produce identical source/package
  inventories where platform signing metadata permits;
- scan the source tree and Git index before and after packaging with the
  private-content guard and artifact-quality gates;
- ensure hosted CI and release automation never require, upload, cache, or
  attest to private/generated title payloads; and
- document that locally generated packages are not project-distributed game
  builds and remain subject to the user's content rights and applicable law.
