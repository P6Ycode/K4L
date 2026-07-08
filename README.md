<div align="center">

<img src="resources/screenshots/sparkle.png" width=128 height=128> 

# Sparkle for Instagram

*Bring the spark back to Instagram*

`v1.0.0` · Tested on versions **437.1.0** and **410.1.0**

[📣 Telegram Channel](https://t.me/sparkle_ig) · [💬 Chat & Support](https://example.com) · [📥 Releases](https://github.com/efibalogh/sparkle-ig/releases/latest) · [🐛 Issues](https://github.com/efibalogh/sparkle-ig/issues/new/choose) · [☕ Donate](https://ko-fi.com/sparkle_ig)

</div>

---

> [!NOTE]
> - To open Sparkle's settings, see [Opening Sparkle Settings](#opening-sparkle-settings).
> - Releases and announcements go out on the [Telegram channel](https://t.me/sparkle_ig); questions and help happen in the [chat group](https://example.com).
> - Feature request or bug report? [Open an issue](https://github.com/efibalogh/sparkle-ig/issues/new/choose).

## What is Sparkle?

Sparkle is a [Theos](https://theos.dev) tweak that reshapes the iOS Instagram app around you. Download any media, keep a private on-device gallery, recover deleted messages, run each account with its own settings, analyze your followers, and strip out the ads, AI, and annoyances.

It started as a fork of [SoCuul's SCInsta](https://github.com/SoCuul/SCInsta), but has since been rewritten and extended far beyond it.

- Targets **iOS 15.0+**, built with the iOS 16.2 SDK.
- Works **jailbroken** (tested via Dopamine on iOS 16.7.16) and **sideloaded** (Feather, SideStore, LiveContainer etc.).
- Written in Objective-C / Objective-C++ / Logos.

## Highlights

For the full list of features, check out [`FEATURES.md`](FEATURES.md).

- **Media downloads**:
  - Save feed posts, reels, stories, DMs, Instants, and comments.
  - An action-based download manager with a queue, retries, duplicate detection, and configurable concurrency.
  - High-quality DASH video+audio merging via FFmpegKit.
- **Private Gallery**:
  - An on-device media library with folders, search, metadata, source overlays, and an optional passcode / Face ID / Touch ID lock. Nothing ever leaves your device.
- **Built-in editors**:
  - Trim any video down to a clip, a single still frame, or audio-only.
  - A photo editor with crop / pan-zoom / rotate / flip.
  - Reachable from the gallery, media preview, or an opt-in action button.
- **Action buttons everywhere**:
  - Fully customizable action-button menus on feed, reels, stories, DMs, Instants, and profiles.
  - Reorder, rename, re-icon, and set per-surface default tap actions.
- **Keep deleted messages**:
  - Preserve unsent DMs, log removed reactions, and recover view-once media, with a browsable log.
- **Profile Analyzer**:
  - Fetches your followers/following and surfaces mutuals, non-followbacks, and a durable change log (new/lost followers, profile updates) across scans.
- **Per-account settings**:
  - Each logged-in account keeps its own preferences, gallery scope, and download history.
- **Privacy & focus**:
  - Hide ads, Meta AI, and suggested content.
  - Disable seen receipts, typing status, screenshot detection, and view-once limits.
  - Block doom-scrolling.
  - Hide tabs and UI clutter.
- **Confirmations**:
  - Optional "are you sure?" guards for accidental likes, follows, reposts, calls, comments, and more.
- **Liquid Glass (iOS 26+)**:
  - Native Liquid Glass integration across Sparkle's own UI, plus an option to force-enable Instagram's.

## Installation

> [!IMPORTANT]
> Sparkle does **not** ship Instagram itself. Pre-injected IPAs are distributed on the [Telegram channel](https://t.me/sparkle_ig), and the jailbroken `.deb` is on [Releases](https://github.com/efibalogh/sparkle-ig/releases/latest).

### Sideloaded

1. Grab the latest **pre-injected IPA** from the [Telegram channel](https://t.me/sparkle_ig).
2. Install the IPA with your sideloading tool of choice.
   - Use the **`_sidestore`** build for **AltStore / SideStore / LiveContainer** (or if you don't want to have app extensions).

> [!NOTE]
> Sparkle uses Instagram's bundled image assets everywhere. The distributed IPA is a full (un-thinned) build (it contains icons for all screen sizes), so the higher-quality in-app icons render crisply on every device. If you build your own from an IPA that was already thinned to a smaller device, some icon scales may be missing. See [Building from source](#building-from-source).

### Jailbroken

1. Download the rootless or rootful `.deb` from [Releases](https://github.com/efibalogh/sparkle-ig/releases/latest).
2. Install it in Sileo/Zebra (or `Depiction`-add via a package manager), then respring.

### Build it yourself

You can build from source locally, or fork the repo and run the **Build and Package Sparkle** GitHub Action with your own decrypted IPA URL. The injected IPA lands as a draft release in *your* fork. See [Building from source](#building-from-source).

## Opening Sparkle Settings

By default, **long-press the Home tab** or the **Profile settings button** to open Sparkle Settings. You can also enable *Show Settings on App Launch*. If you hide the Home tab, the long-press automatically moves to another visible tab so Settings is always reachable.

## Screenshots

| Settings | How to Access |
|:-------------:|:------------:|
| <img src="resources/screenshots/sparkle_settings.jpg" width="300"> | <img src="resources/screenshots/sparkle_settings_open.jpg" width="300"> |

## Building from source

### Prerequisites

- **Xcode** + Command-Line Developer Tools
- [Homebrew](https://brew.sh)
- [Theos](https://theos.dev/docs/installation) with the **iPhoneOS16.2.sdk** in `~/theos/sdks`
- `brew install ldid dpkg make cmake` (plus the FFmpeg build deps: `autoconf automake libtool meson nasm ninja pkgconf wget yasm`)
- **For sideloading only:** [cyan](https://github.com/asdfzxcvbn/pyzule-rw#install-instructions) and [ipapatch](https://github.com/asdfzxcvbn/ipapatch/releases/latest)

### Setup

1. **Install the iOS 16.2 SDK** for Theos — download from [xybp888/iOS-SDKs](https://github.com/xybp888/iOS-SDKs) and copy `iPhoneOS16.2.sdk` into `~/theos/sdks`.
2. **Clone with submodules:**
   ```sh
   git clone --recurse-submodules https://github.com/efibalogh/sparkle-ig
   cd sparkle-ig
   ```
3. **Fetch the FFmpegKit frameworks** (used for video/audio merging & trimming):
   ```sh
   ./fetch-ffmpegkit.sh
   ```
4. **For sideloading:** obtain a **decrypted, un-thinned** Instagram IPA from a trusted source, rename it to `com.burbn.instagram.ipa`, and place it in a `packages/` folder at the repo root.

> [!IMPORTANT]
> Use a *universal* decrypted IPA. An IPA that was already thinned to a specific device (e.g. dumped on an older iPhone) might be missing higher-scale icons/image assets, which makes icons and image assets blurry on newer devices.
>
> Alternatively, if you own a jailbroken device, I recommend using [ipadecrypt](https://github.com/londek/ipadecrypt), which provides an un-thinned IPA regardless of your device's screen size.

### Build

```sh
./build.sh rootless          # rootless .deb (jailbroken)
./build.sh rootful           # rootful .deb (jailbroken)
./build.sh ipa --release     # sideload IPA (= --inject --ffmpeg --patch)
```

The `ipa` command takes composable flags:

| Flag | Effect |
|------|--------|
| `--release` | Shorthand for `--inject --ffmpeg --patch` |
| `--inject` | Inject `Sparkle.dylib` |
| `--ffmpeg` | Bundle the FFmpegKit frameworks |
| `--flex` | Bundle `libFLEX.dylib` (in-app debugging) |
| `--patch` | Run `ipapatch` |
| `--no-ext` | Strip all `.appex` bundles before injection |
| `--sidestore` | Shorthand for `--release --no-ext` (for SideStore) |
| `--dev` | `DEV=1` build |
| `--buildonly` | Build dylibs only, skip IPA packaging |
| `--bundle-id <id>` | Override the bundle ID |

Outputs are named with the Sparkle version (and, for IPAs, the bundled Instagram version) so builds are easy to tell apart:

- **IPA**: `Sparkle[_<flags>]_v<version>_IG_v<ig version>.ipa` (e.g. `Sparkle_v1.0.0_IG_v437.2.0.ipa`, or `Sparkle_no-flex_v1.0.0_IG_v437.2.0.ipa`)
- **deb**: `Sparkle_v<version>_<rootless|rootful>.deb`

Run `./build.sh` with no arguments for the full usage reference.

### Recompiling the Liquid Glass app icons

The app icons are pre-compiled into `resources/sparkle_icons/` to keep IPA packaging fast. If you change the source `.icon` bundles in `resources/`, recompile them with `actool` before building:

```zsh
mkdir -p resources/compiled_sparkle resources/compiled_sparkle_dark resources/compiled_sparkle_neutral

xcrun actool resources/sparkle.icon         --compile resources/compiled_sparkle         --platform iphoneos --minimum-deployment-target 15.0 --app-icon sparkle         --output-partial-info-plist resources/sparkle_partial.plist         --target-device iphone --target-device ipad
xcrun actool resources/sparkle-dark.icon    --compile resources/compiled_sparkle_dark    --platform iphoneos --minimum-deployment-target 15.0 --app-icon sparkle-dark    --output-partial-info-plist resources/sparkle_dark_partial.plist    --target-device iphone --target-device ipad
xcrun actool resources/sparkle-neutral.icon --compile resources/compiled_sparkle_neutral --platform iphoneos --minimum-deployment-target 15.0 --app-icon sparkle-neutral --output-partial-info-plist resources/sparkle_neutral_partial.plist --target-device iphone --target-device ipad

mkdir -p resources/sparkle_icons
cp resources/compiled_sparkle/*.png resources/compiled_sparkle_dark/*.png resources/compiled_sparkle_neutral/*.png resources/sparkle_icons/
rm -rf resources/compiled_sparkle resources/compiled_sparkle_dark resources/compiled_sparkle_neutral resources/*_partial.plist
```

## Contributing

Contributions are greatly appreciated! Feel free to open a pull request.

- New hooked IG classes/methods go in `src/InstagramHeaders.h`
- Prefix all custom symbols with `spk_` / `SPK`.
- Break new features into `src/Features/<Surface>/` rather than bloating `Tweak.x`.

Not a coder? Documentation improvements are always appreciated too.

## Support the project

Sparkle takes a lot of time to develop and maintain as Instagram changes constantly, and I can only work on it in my limited amount of free time. If you'd like to support the work:

- ☕ Donate on [Ko-fi](https://ko-fi.com/sparkle_ig).
- 📣 Join and share the [Telegram channel](https://t.me/sparkle_ig).
- ⭐ Star the repo and tell people who'd like it.

## Credits

- [**SoCuul** • SCInsta](https://github.com/SoCuul/SCInsta): the base project Sparkle is built on.
- [**BandarHL** • BHInstagram](https://github.com/BandarHL/BHInstagram): the original tweak SCInsta forked from.
- [**Ryuk** • RyukGram](https://github.com/faroukbmiled): code, inspiration, and help.
- [**@n3d1117** • InstaSane](https://github.com/n3d1117/InstaSane): the Following-feed mode.
- [**@asdfzxcvbn** • zxPluginsInject / ipapatch / cyan](https://github.com/asdfzxcvbn): tooling and fixes for sideloaded installs.

## License

Sparkle is licensed under the [GNU General Public License v3.0](LICENSE).
</content>
</invoke>
