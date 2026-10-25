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
for complying with applicable law and license terms. Future content tools will
accept explicit external paths and will keep private reports and generated
outputs outside tracked source.

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

The guard is intentionally path-focused. It recognizes specific private and
generated layouts while allowing ordinary source names such as
`src/host/save-data.cpp`, `src/game/shader_cache.cpp`, documentation that names
the title ID, and public documentation images. Review remains mandatory.
