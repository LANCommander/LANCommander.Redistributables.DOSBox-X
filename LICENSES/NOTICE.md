# Attribution and licensing

This repository contains two separately licensed things. Keeping them distinct
matters, because only one of them is ours to license.

## What we authored

The packaging scripts, workflows, option schema, curation overlay and
documentation in this repository are copyright (c) 2026 LANCommander and are
released under the MIT License, in `LICENSE`.

## What we redistribute

The published `.LCX` package contains binaries from **DOSBox-X**, which we did not
author and do not license. Those files remain under their own terms:

| | |
|---|---|
| Project | DOSBox-X |
| Homepage | https://dosbox-x.com/ |
| Source | https://github.com/joncampbell123/dosbox-x |
| Copyright | (c) the DOSBox-X team, and the DOSBox Team for the code DOSBox-X forked |
| License | GNU General Public License, version 2 |

The full upstream license is in `UPSTREAM-LICENSE.txt` and is also packed inside
the payload archive as `COPYING.txt`, so it travels with the binaries rather than
only living here.

### Obligations we carry

The GPL is a copyleft license, so redistributing DOSBox-X binaries brings real
obligations rather than an attribution line:

- **The license text accompanies the binaries.** `COPYING.txt` is placed in the
  payload by `source.ps1`, so it lands in every client's `.dosbox` directory
  alongside `dosbox-x.exe`.
- **Corresponding source is offered for the exact build shipped.** We do not build
  DOSBox-X; we republish upstream's own official Windows x64 binary, unmodified.
  The complete corresponding source for any version this package has shipped is
  therefore upstream's own release of the same version:

      https://github.com/joncampbell123/dosbox-x/releases/tag/dosbox-x-v<version>

  where `<version>` is the version recorded on the imported redistributable, for
  example `dosbox-x-v2026.08.02`. Every release page carries the source archive for
  that tag. If you need the source for a version whose upstream release has since
  been removed, open an issue here and we will provide it.
- **No notices are altered or removed.** The binaries are byte-for-byte upstream's.

### Why this payload is distributed the way it is

The payload is bundled into the `.LCX` rather than downloaded on the client,
because the GPL permits redistribution outright provided the two obligations above
are met. Bundling is what lets a LAN party run with no internet connection at all,
which is the point of the exercise.

The archive is narrowed rather than shipped whole. `source.ps1` takes the `Release`
(SDL1) build from the official `dosbox-x-vsbuild-win64-<version>-portable.zip` and
keeps the executable together with the assets its options can reach — shaders, GLSL
shaders, language files, the default TrueType font and the PC-98 character
generator. It leaves behind upstream's documentation, the Windows Explorer shell
integration scripts, the second SDL2 build, and the CJK fonts
(`SarasaGothicFixed.ttf`, `wqy_11pt.bdf`, `wqy_12pt.bdf`), which together account
for roughly half the archive. Nothing is modified; files are either copied verbatim
or not copied at all.

---

If you are a copyright holder for DOSBox-X and would prefer this package not
redistribute your files, please open an issue and we will switch it to downloading
from you directly at install time.
