<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Curated asset-format findings

This document preserves format facts measured in the prior research without
including payload bytes, private manifests, logical asset names, or private
hashes. Evidence labels are defined in [`README.md`](README.md).

## Source-layer warning

- **Verified:** The original extracted application remains PFS protected.
  Named extensions in that layer do not carry valid format signatures and must
  not be used for format inference.
- **Verified:** After authorized installation removes outer PFS, the main
  archive begins with `PSAR`, ATRAC9 files are RIFF/WAVE containers, and PNG,
  MP4, MIDI, SELF, and SUPRX signatures are recognizable.
- **Derived:** Format probes should reject protected inputs explicitly and
  operate read-only by default.

## PSARC

- **Verified:** The title's main resource archive uses PSARC version
  `0x00010004`, a `zlib` compression tag, 30-byte TOC entries, and a 65,536-byte
  block size.
- **Verified:** Header, TOC, and block-length integers are big-endian.
- **Verified:** A TOC entry contains a 16-byte path digest, a 32-bit first-block
  index, a 40-bit uncompressed size, and a 40-bit data offset.
- **Verified:** For this archive, block lengths are 16-bit big-endian. Zero
  denotes a full-size block; a stored block shorter than the expected output is
  zlib-compressed.
- **Verified:** The first entry has an all-zero digest and expands to the UTF-8
  path manifest. Manifest names correspond one-for-one with remaining entries.
- **Verified:** Different logical names can share one payload location.

Parser requirements derived from those observations:

- use checked 64-bit arithmetic for 40-bit fields;
- bounds-check headers, TOC, block table, and compressed/stored ranges;
- retain path case and preserve duplicate payload references;
- fail if manifest and TOC counts disagree; and
- inventory without extraction unless a requested file is needed.

## Loose standard formats

- **Verified:** ATRAC9 assets are RIFF/WAVE with
  `WAVE_FORMAT_EXTENSIBLE` and the ATRAC9 subtype GUID
  `47e142d2-36ba-4d8d-88fc-61654f8c836c`.
- **Verified:** Sample MP4 files use `mp42` branding, PNG uses the standard
  signature, and MIDI begins with `MThd`.
- **Verified:** Companion CSV files are UTF-8 with BOM and quoted columns.
- **Verified:** `.sub` is a custom little-endian binary with count/offset data
  and UTF-16LE text.
- **Hypothesis:** The `.sub` records associate localized identifiers with
  timing metadata. The exact record layout remains unknown.

## Archive-internal families

### `.core`

- **Verified:** Sampled files begin with the exact 16-byte
  `RTTIBin<2.07>  \0` signature.
- **Verified:** Numeric values after the signature appear little-endian.
- **Verified:** The format contains a runtime type dictionary and serialized
  object graph. Observed vocabulary names mesh, skinning, material, shader, and
  texture resource types.
- **Verified:** A minimal 47-byte file is a valid empty/minimal container.
- **Unknown:** Header field meanings, object identity, reference encoding, and
  section boundaries.

Unknown words must remain numbered raw fields until a controlled mutation,
loader trace, or cross-file invariant proves their meaning.

### `.CoreStream`

- **Verified:** Every observed stream has an exact-stem `.core` partner; not
  every `.core` has a stream.
- **Verified:** Streams contain mostly high-entropy aligned binary data and no
  universal RTTIBin or standard texture-container signature.
- **Verified:** Texture-resource samples did not contain an embedded GXT, DDS,
  PNG, or KTX wrapper.
- **Derived:** `.core` contains object/descriptor metadata while `.CoreStream`
  carries bulk vertex, index, texture, animation, or related data.
- **Unknown:** Descriptor layout, per-resource alignment, vertex/index
  declarations, texture swizzles, compression, and skeleton/animation layout.

Pairing should use the complete normalized archive path without the final
suffix while preserving original case for display and provenance.

### `.gum`

- **Verified:** GUM files are plain-text XML UI definitions. They are not a
  mesh-import prerequisite.

## Validation and content policy

- Keep offset/size arithmetic checked and reject unknown variants explicitly.
- Never substitute empty geometry or zero-filled textures for a parse failure.
- Use only synthetic malformed and minimal-format fixtures in public tests.
- Keep PSARC, extracted entries, full filename manifests, decoded assets,
  captures, and private probe output outside Git.
- Compare against authorized private captures only in local workflows and
  publish aggregate conclusions rather than payload-derived evidence.
