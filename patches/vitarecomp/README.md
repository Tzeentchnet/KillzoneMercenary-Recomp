<!-- SPDX-License-Identifier: GPL-2.0-or-later -->

# Pending framework patches

These commits belong in the framework fork
[`Tzeentchnet/vitarecomp`](https://github.com/Tzeentchnet/vitarecomp). They
are parked here only because the session that wrote them could not push to
the fork. Once they land there, delete this directory and bump the submodule
pin and `config/framework.commit` together.

Base: `0e81bb4b275435b2396b01a88c8d767d0104cc8b` (the patch base).

| Patch | What it fixes |
|---|---|
| `0001-Build-warnings-clean-with-Linux-clang-and-GCC.patch` | Linux clang/GCC `-Werror` builds, so cloud sessions can run the CPU/runtime tests. Also fixes two real bugs: NID names over 63 bytes were truncated into HLE symbols that nothing implements (22 names in vita-headers db/360), and FIOS overlay paths could be silently truncated. Adds the `nids` regression test |
| `0002-Pass-git-clang-format-s-Python-script-not-its-.bat-w.patch` | The Windows quality gate fails on any C/C++ change because it hands LLVM's `git-clang-format.bat` to Python (fork CI run [40255206038](https://github.com/Tzeentchnet/vitarecomp/actions/runs/40255206038)) |

Verified at the base above: clang and GCC Release and Debug builds with zero
warnings, and 19/19 CTest on each.

Apply them in the fork:

```sh
git checkout -b linux-clean 0e81bb4b275435b2396b01a88c8d767d0104cc8b
git am <game-repo>/patches/vitarecomp/*.patch
```
