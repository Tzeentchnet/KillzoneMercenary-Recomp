<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Research record

These documents curate reusable engineering evidence from the verified
`killzone-aot` snapshot captured on 2026-10-25. They contain no retail bytes,
generated title code, traces, private paths, or private-input hashes.

Source provenance:

- Vita3K base: `ee50eb8644b4184996047f04406486281586935b`
- prior branch HEAD: `c505989f8c03dcae922fe93f09b0d30dac21c230`
- accepted framework integration:
  `f3408e1ea73b724c7ba3a644633938c220f2cc2a`
- accepted game verification report:
  `36fef0e94ab99d1fc6e1903f02a388013eb3585d`
- snapshot validation: exact current bytes for all 45 changed public
  source/documentation paths, including ten uncommitted paths
- migration disposition and validation: [`../../MIGRATION.md`](../../MIGRATION.md)

## Evidence legend

| Label | Meaning |
|---|---|
| **Verified** | Reproduced by a parser, build, focused synthetic test, or direct oracle comparison in the prior snapshot. |
| **Derived** | Follows from verified observations, but has not been exercised end to end in the standalone architecture. |
| **Hypothesis** | A plausible direction that still requires a named experiment. |

Labels describe the evidence in the prior snapshot. They do not imply that the
same behavior is already integrated into the new framework. Integration status
is stated separately in each document and was reconciled after the accepted
foundation verification. See the production
[`architecture`](../ARCHITECTURE.md) for the current boundary.

## Documents

- [`FINDINGS.md`](FINDINGS.md) — executable-input, translation, runtime, and
  correctness findings.
- [`ARCHITECTURE-HANDOFF.md`](ARCHITECTURE-HANDOFF.md) — how the evidence maps
  from the historical Vita3K hybrid into the standalone framework/game split.
- [`ASSET-FORMATS.md`](ASSET-FORMATS.md) — measured container and asset-format
  facts, with unknowns kept explicit.

The historical live TODO and unrelated PS2Recomp note were intentionally not
copied. They describe a superseded implementation and are not project trackers
for this repository.
