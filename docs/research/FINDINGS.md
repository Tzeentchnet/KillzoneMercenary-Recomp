<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Curated recompilation findings

This is a source-only handoff of reusable evidence from the verified prior AOT
snapshot. Exact title addresses, private hashes, generated code, and traces are
omitted. Evidence labels are defined in [`README.md`](README.md).

## Architecture status

- **Verified:** A standalone parser/recompiler can inspect normalized Vita
  ELF32 images, retain ARM/Thumb mode, discover reachable control flow, and
  emit bounded generated-source partitions without running Vita3K.
- **Verified:** The historical branch executed generated blocks inside an
  opt-in Vita3K AOT-first CPU and used Dynarmic as a one-step differential
  oracle.
- **Derived:** The reusable semantics and vectors remain valid when adapted to
  the canonical `vitarecomp` C runtime/emitter.
- **Verified integration decision:** The new production architecture is not
  the historical Vita3K hybrid. The pinned `third_party/vitarecomp` submodule
  is the production framework; Vita3K is an external content-preparation and
  optional oracle tool. No second production recompiler is migrated.

## Executable input contract

### Input layers

- **Verified:** The original retail application tree retains an outer PFS
  layer. Apparent PNG, MP4, PSARC, SELF, and SUPRX filenames are not evidence
  that their bytes are directly parseable.
- **Verified:** An authorized Vita3K installation removes outer PFS, but the
  installed executable SELF can still contain protected/compressed segments.
  Its metadata is inspectable while its code is not yet a static-analysis
  input.
- **Verified:** A runtime-addressed ELF reconstructed from loaded segments is
  analyzable.
- **Verified:** Runtime ELF capture must happen after relocations and both
  export and import linking. A pre-link capture retained a weak-import body
  that the loader later replaced; translating the stale body caused a
  reproducible divergence.
- **Derived:** Every local input manifest should record loader stage and
  runtime address ranges, and reject a mixture of pre-link and post-link
  images.

### Image composition

- **Verified:** Non-overlapping runtime images can be composed into one
  deterministic report and registry.
- **Verified:** Input/report order must not affect output ordering.
- **Verified:** Overlapping executable ranges and duplicate block keys must
  fail explicitly rather than letting the last input win.
- **Derived:** Explicit seeds should be routed to exactly one containing
  executable image; a seed outside all images or inside more than one image is
  an input error.

The generic cases are preserved as framework fixtures. Multi-image command-line
integration is deferred to the framework's future image-set orchestration; see
the framework migration record.

## ARM/Thumb and control flow

- **Verified:** Instruction-set mode is part of a code key. The same aligned
  address in ARM and Thumb modes must not alias.
- **Verified:** A function pointer's low bit carries Thumb state. Clear it only
  for byte addressing; retain the mode when creating discovery and dispatch
  keys.
- **Verified:** Capstone exposes some ARM immediates through a signed field.
  Address reconstruction must preserve the underlying 32-bit bit pattern.
- **Verified:** Reachable instructions must be collected before final basic
  blocks are formed, because a later-discovered target can split an earlier
  range.
- **Verified:** Table-branch recovery is safe only when table bounds are proven.
  Runtime-indexed tables require checked guest-memory reads.
- **Verified:** Thumb PC-relative table calculations use the architectural,
  word-aligned PC base, including when the instruction itself is only
  halfword-aligned.
- **Verified:** Indirect `BLX` must capture its source before updating LR;
  `BLX LR` otherwise dispatches to the newly written return address.
- **Verified:** Conditional A32 calls, branches, returns, and SVC exits must
  preserve predicate-false fallthrough. A failed predicate must not write LR,
  change PC, or raise an exception.

The canonical framework does not yet have one mode-aware key type across
discovery, symbols, and dispatch. The same-address/mixed-mode collision vector
is therefore recorded as deferred rather than claimed as executable coverage.

## Architectural state and memory

- **Verified:** Differential comparison must include every represented core
  register, raw extended-register word, CPSR/NZCV state, FPSCR state, and every
  initial or written guest-memory byte. Comparing only return registers is not
  sufficient.
- **Verified:** VFP/NEON registers must retain raw bits. Host `float` storage
  alone loses distinctions such as NaN payloads.
- **Verified:** Guest reads and writes need explicit bounds checks, checked
  address arithmetic, little-endian behavior, and defined unaligned access.
  A failed read must remain visible; silently returning zero creates
  success-shaped corruption.
- **Verified:** Addressing-mode ordering matters. Post-index stores write
  before base update; pre-index loads complete the checked read before
  committing destination and writeback; multi-register transfers capture
  aliased inputs before commits.
- **Verified:** Scalar comparisons must account for FPSCR flush-to-zero mode
  before deriving comparison flags.
- **Verified:** A vector lane store is not a whole-register store. If the
  emitter cannot distinguish the lane form, it must reject it.

The framework directly executes checked-memory, raw-state, flag, and NaN
vectors. FPSCR mode behavior and unsupported vector forms remain fixtures for
their named emitter/runtime integration points.

## Exclusive monitor

- **Verified:** `LDREX` establishes a core-local reservation associated with a
  shared monitor. A matching `STREX` succeeds once; an absent or invalidated
  reservation fails without writing.
- **Verified:** An ordinary guest write that overlaps a reservation must
  invalidate other cores' reservations.
- **Verified:** Invalidation and the ordinary write must be serialized under
  the same monitor synchronization as `LDREX`/`STREX`. Invalidating before
  taking the write lock allows a new reservation to appear between
  invalidation and the write.
- **Derived:** The standalone runtime should expose these semantics only when
  its canonical thread/CPU selection and shared-memory ownership are defined.

Exclusive-monitor vectors are intentionally deferred: the current framework
has no canonical per-thread CPU object or exclusive-monitor API.

## Strict diagnostics and reproducibility

- **Verified:** Missing translated targets are correctness failures. Diagnostics
  must include both the source transfer and destination key; silently returning
  is invalid.
- **Verified:** Dispatch registries must be sorted deterministically and reject
  duplicate keys. Searching an unsorted table can look exactly like missing
  translation coverage.
- **Verified:** Generated-source staging by content preserves unchanged mtimes,
  updates changed files, removes only previously managed stale files, and is
  idempotent.
- **Derived:** Stable source identities are necessary but not sufficient for
  very large outputs; address-bucket partitioning avoids shifting every later
  chunk when one block is inserted.

The adapted staging tool and synthetic tests live under `tools/generated` and
`tests`. Framework trace-mode tests verify exact missing-target diagnostics.

## Evidence limits

- **Verified:** The prior branch demonstrated early translated execution and
  differential agreement; it did not reach a no-JIT build or playable state.
- **Hypothesis:** Conservative function-entry scanning can make many runtime
  indirect targets resident without resolving each call statically. It still
  needs false-positive controls and synthetic malformed-input tests.
- **Hypothesis:** Broader VFP/NEON support should be added in measured families
  behind exact operand-shape gates, not generalized from one observed form.
