# LANCommander.Redistributables.DOSBox-X

Automatically built LANCommander redistributable import package (`.LCX`) for
[DOSBox-X](https://dosbox-x.com/).

DOSBox-X emulates a PC from the IBM XT through to the late 1990s, and runs an
MS-DOS game inside it. Unlike most redistributables this is not a compatibility
improvement — a 16-bit DOS executable will not start at all on 64-bit Windows, so
without an emulator a DOS-era title in your library is simply unlaunchable.

It also matters for LAN play specifically. Doom, Doom II, Descent, Duke Nukem 3D,
Heretic, Hexen, Warcraft II and most of their contemporaries only ever spoke IPX,
a protocol no current operating system carries. DOSBox-X tunnels IPX over UDP, so
those games find each other on an ordinary modern network. Enable IPX in the
options below, then use `IPXNET` inside DOSBox-X to point every client at one host.

Attach it to any game whose primary action runs a DOS program.

## Install it

Download the `.lcx` asset from the [latest release][latest] and import it
through your LANCommander server's **Redistributables** page, or from the CLI:

```
LANCommander.Launcher.CLI Import --Path LANCommander.Redistributables.DOSBox-X-v<version>.lcx --Type Redistributable
```

Then assign it to the games that need it, either from the game's
**Redistributables** field or from this redistributable's **Games** field.

Re-importing a newer release **updates** the existing entry rather than creating a
second one, because the identifiers in `redistributable.yml` are stable across
releases.

Alternatively, import once and let it update itself: the package ships a
`Package` script, which a LANCommander server runs on a schedule to pull new
versions straight from this repository's releases.

[latest]: https://github.com/LANCommander/LANCommander.Redistributables.DOSBox-X/releases/latest

## What is in the package

| Path | |
|---|---|
| `Manifest.yml` | Redistributable metadata, including the embedded option schema |
| `Archives/{guid}` | A ZIP of the payload, extracted into the game's `.lancommander` metadata directory |
| `Scripts/{guid}` | One entry per PowerShell script |

The payload is the official Windows x64 portable build (`Release`, the SDL1
variant), narrowed to about 25 MB: the executable plus the shaders, GLSL shaders,
language files, default TrueType font and PC-98 character generator that its
options can reach. Upstream's documentation, the Explorer shell integration
scripts, the duplicate SDL2 build and the CJK fonts are not packaged. If you need
CJK text under `output=ttf`, point `[ttf] font` at a font on the host.

## How it runs a game

Nothing about the launch is a `CommandTemplate`. `Scripts/RunWrapper.ps1` takes
over the launch entirely and, on every start:

1. Resolves this game's option values.
2. Rewrites `dosbox-x.reference.conf` into `<game>/.dosbox/dosbox-x.conf` with
   those values, preserving upstream's comments and layout so the generated file
   still reads like the documented one.
3. Appends an `[autoexec]` block that mounts the action's working directory as
   `C:`, changes into the executable's directory, runs it with the action's
   arguments and exits. A `.BAT` or `.CMD` action is invoked through `CALL`,
   because DOS batch semantics otherwise transfer control away and never return,
   leaving the emulator at a DOS prompt.
4. Runs `dosbox-x.exe -fastlaunch -exit -conf …` and waits for it to close.

Two consequences are worth knowing about:

- **Attaching this to a game that is not a DOS program will break that game.** The
  wrapper applies to any game it is assigned to, and there is no platform check
  that could tell a DOS executable from a Windows one.
- Everything lands in the game's own `<game>/.dosbox` directory. Nothing is
  installed system-wide, no PATH is changed, no elevation is requested, and
  uninstalling the game removes the emulator with it. The cost is one copy of
  DOSBox-X per DOS game rather than one per machine.

## Options

Every option upstream documents in `dosbox-x.reference.conf` is exposed — **378 of
them**, with upstream's own descriptions and valid-value lists harvested from the
file rather than retyped, so an option added upstream appears here automatically.

That is a lot of surface. The defaults are upstream's own and run most games as-is;
the settings that actually decide whether a given game works are `[dosbox] machine`,
`[cpu] cycles`, the `[sblaster]` addressing, and `[ipx] ipx` for LAN play.
Sections like `[ttf]`, `[pc98]`, `[dosv]` and `[log]` are there for completeness and
will not improve an ordinary DOS game.

| Section | Shown as | Options |
|---|---|---|
| `[sdl]` | Display and Window | 30 |
| `[log]` | Logging | 2 |
| `[dosbox]` | Machine and Emulation | 32 |
| `[render]` | Rendering and Scaling | 11 |
| `[pc98]` | NEC PC-98 | 11 |
| `[dosv]` | DOS/V | 17 |
| `[video]` | Video Memory and VESA | 8 |
| `[vsync]` | Vertical Sync | 2 |
| `[cpu]` | CPU | 13 |
| `[keyboard]` | Keyboard Hardware | 4 |
| `[ttf]` | TrueType Output | 23 |
| `[voodoo]` | 3dfx Voodoo | 5 |
| `[mixer]` | Audio Mixer | 7 |
| `[midi]` | MIDI | 10 |
| `[sblaster]` | Sound Blaster | 19 |
| `[sblaster2]` | Sound Blaster (Second Card) | 19 |
| `[gus]` | Gravis Ultrasound | 10 |
| `[innova]` | Innovation SSI-2001 | 4 |
| `[speaker]` | PC Speaker and Tandy Audio | 7 |
| `[joystick]` | Joystick | 5 |
| `[mapper]` | Joystick Deadzones | 16 |
| `[serial]` | Serial Ports | 10 |
| `[parallel]` | Parallel Ports | 10 |
| `[printer]` | Printer Emulation | 14 |
| `[dos]` | DOS Environment | 40 |
| `[ipx]` | IPX Networking | 1 |
| `[ne2000]` | NE2000 Ethernet | 5 |
| `[ethernet, pcap]` | Ethernet (pcap backend) | 2 |
| `[ethernet, slirp]` | Ethernet (slirp backend) | 5 |
| `[ide, primary]` … `[ide, octernary]` | IDE Channels 1–8 | 2 each |
| `[fdc, primary]` | Floppy Controller | 3 |
| `[4dos]` | 4DOS Shell | 1 |
| `[config]` | CONFIG.SYS | 16 |

The full list, with every description, default and choice list, is
[`OptionSchema.yml`](OptionSchema.yml). Upstream's own reference for the same
options is [`dosbox-x.reference.conf`][refconf] and the
[DOSBox-X wiki][wiki].

[refconf]: https://github.com/joncampbell123/dosbox-x/blob/master/dosbox-x.reference.conf
[wiki]: https://dosbox-x.com/wiki/

Administrators can override any of these per game from the game's
**Redistributables** page. Values resolve as schema default, then per-game value,
then per-action override.

Two quirks in the generated names are deliberate. Option keys are sanitised to
letters, digits and underscores, so `[mapper]`'s `joy1deadzone0-` and
`joy1deadzone0+` collapse to one `Joy1deadzone0_` that sets both directions of the
axis, and section names containing a comma become `Ethernet_pcap` or
`Ide_secondary`. The friendly headings come from `Schema.Overlay.yml`; the
underlying keys are what per-game values are stored against and must not be
renamed.

## How this repository works

| File | Purpose |
|---|---|
| `redistributable.yml` | Identity, payload source, config paths, stable script GUIDs |
| `source.ps1` | Resolves and downloads the upstream release, narrowing the payload |
| `Parse-Config.ps1` | Reads `dosbox-x.reference.conf`, whose layout the shared INI parser cannot follow |
| `Schema.Overlay.yml` | Hand-written curation: section headings, and the one option upstream mis-documents |
| `OptionSchema.yml` | Generated from the upstream config, then curated. Do not edit by hand |
| `Scripts/*.ps1` | Client-side and server-side scripts |
| `LICENSES/` | Upstream attribution and license text |

`OptionSchema.yml` is generated, and the build fails if the committed copy does
not match what the upstream config produces. To regenerate it locally:

```powershell
Import-Module <path-to>/LANCommander.Redistributables/module/LANCommander.Redistributables
Invoke-RedistributableBuild -RepositoryPath . -UpdateSchema
```

Edit `Schema.Overlay.yml` to change how an option is presented; never edit
`OptionSchema.yml`, since the next rebuild overwrites it.

### Staying current

A scheduled workflow checks DOSBox-X for new versions. Upstream releases on roughly
the first of each month. When one appears the workflow re-parses the config,
regenerates the option schema through the overlay, and opens a pull request listing
exactly which options were added, removed or had their defaults change. Merging that
pull request publishes the release.

Options that upstream adds are picked up automatically and ship uncurated; the
pull request calls them out so a description can be written for them.

## Licensing

The scripts and workflows here are MIT licensed. DOSBox-X itself is GPL v2 and is
redistributed unmodified — see [`LICENSES/NOTICE.md`](LICENSES/NOTICE.md) for
attribution, the obligations that carries, and where to get the corresponding
source for any version this package has shipped.
