# Ada · Dynamic Island for Mac

[Türkçe](README.md) · [Release notes](CHANGELOG.md)

A native SwiftUI/AppKit workspace attached to the MacBook notch. Customize dashboard tiles, control Spotify and Apple Music, keep local file copies, run a focus timer, or read a teleprompter. Includes purple/pink Nebula and glass themes.

## Download

[Published GitHub releases](https://github.com/frozenruzgar/ada-dynamic-island/releases). The source version lives in `Resources/Info.plist`; a published binary may be older. Local binaries target Apple Silicon and macOS 14+. Liquid Glass requires macOS 26. Local ad-hoc builds are not notarized. See [Apple’s guide](https://support.apple.com/102445) for opening downloaded apps.

| Area | Features |
| --- | --- |
| Dashboard | Add, replace, reorder and remove tiles; one Spotify tile |
| Player | Artwork, timing, transport and seeking |
| Shelf | Independent local copies, drag out, retention options |
| Focus / teleprompter | Timers, breaks, reading that stays visible |
| Assistant / cloud | User-opened ChatGPT/Claude pages and folder shortcuts |
| System | CPU, RAM, disk, power/thermal state and keep-awake |

Hover over the notch or press Control–Option–A. While music plays, the player opens; its home button goes to the dashboard. Preferences are under Menu → Settings. The interface follows the system language: Turkish and English are available, with English as the fallback for other languages.

## Build

Requires Swift 5.9+, Python 3 and a macOS SDK. Newer toolchains enable Liquid Glass; older ones use fallback surfaces. Xcode 15/16 has not yet been tested locally.

```sh
./scripts/build.sh
./scripts/check.sh
open dist/Ada.app
```

See [verification records](docs/VERIFICATION.md) and the [Turkish usage guide](docs/USAGE.tr.md). The [demo](docs/images/demo.gif) shows the actual Ada views with sample data.

## Privacy and licensing

Notes, tasks, settings and file copies stay on your Mac. Network access is used for allowlisted Spotify artwork, user-opened pages, and the optional GitHub release check. Camera access is requested only for Mirror; Automation is used for music controls. No source-code license has been selected.

[Contributing](CONTRIBUTING.md) · [Code of conduct](CODE_OF_CONDUCT.md) · [Security reporting](SECURITY.md) · [Privacy and permissions](PRIVACY.md).

Ada is an independent project and is not affiliated with Apple, Spotify, OpenAI or Anthropic. Trademarks belong to their respective owners.
