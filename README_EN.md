# Sableen

[简体中文](README.md)

Sableen plays live-action short dramas and animated dramas from Hongguo. It supports Simplified and Traditional Chinese, Material 3 Expressive controls, Dynamic Color, Monet and an AMOLED theme. Search, watch history and recommendations run on the device.

## Media availability in 1.0.1

| Official chart | Bundled results | Example |
| --- | --- | --- |
| [Live-action](https://hongguoduanju.com/rank/hot-real-drama) | 20 titles, one verified preview each | [Official page](https://hongguoduanju.com/player/7706512650816982040) · [10.08-second MP4](https://hongguoduanju.com/video/public/7706514645208534041/360p.mp4) |
| [Animated](https://hongguoduanju.com/rank/hot-comic-drama) | 20 titles, one verified preview each | [Official page](https://hongguoduanju.com/player/7708355462780947518) · [10.07-second MP4](https://hongguoduanju.com/video/public/7708355470964050969/360p.mp4) |

The refresh tool follows chart entries to individual episodes, matches the publisher’s `VideoObject.contentUrl`, then probes the video track and duration. The respective episode listings give 178 and 115 seconds. The cards show the length of the available previews. The player links to the official page, which may request a login. Anonymous full episodes have yet to be verified. The app bundles WebP posters and the catalog, then streams the selected media over HTTPS.

## Playback

On Android, a **西饭** button appears for previews and playback errors. It opens the installed Xifan app, where viewers can search by title. A cross-platform Xifan episode link has yet to be verified. Episode selection and progress remain specific to each app.

### Offline downloads

Open the download panel in a native player to save the selected episode or preview. The home screen also exposes the queue, including pause-all and resume-all controls. Reopening a saved title plays the local copy. Web playback streams online. Transfers run in the app process. After a restart, users can enqueue unfinished episodes again.

The queue uses the published MP4 URL and resolves the system proxy. It transfers at most two episodes concurrently and can split files of at least 1 MiB into two byte ranges, for up to four concurrent segments. Transient network failures receive bounded retries. Progress notifications are coalesced over 250 ms. Each transfer uses its own working directory. The app checks the byte count and SHA-256 from the bundled catalog before committing the file and marking it as saved. The 40 currently bundled videos retain their measured preview lengths offline.

Opening a title enters fullscreen. Tap the center to pause or resume. The controls hide after three seconds of playback. Tap an edge or move the pointer to bring them back. Hiding the app pauses playback. Losing focus while the window remains visible allows playback to continue. Supported Android devices and browsers with the standard Picture-in-Picture API expose a button for pop-out playback.

Each theater owns one player and releases it on exit. It requests hardware decoding. Android requests a compatible refresh rate at the current resolution when the video declares its frame rate. The OS and driver choose the actual mode. The timeline updates independently of the video surface. Theme settings offer solid, blurred, refractive and Aero-style navigation materials.

History retains up to 512 episode records keyed by Hongguo IDs. Genre recommendations use a 21-day half-life. Each episode contributes `min(watched_ms, duration_ms) / (duration_ms + 60000)` before decay. Seeking and buffering do not contribute watch time.

## Build and verify

The Flutter app version is `1.0.1+2` and the Rust crate version is `1.0.1`. CI pins Flutter 3.47.9, Rust 1.99.1 and flutter_rust_bridge 2.13.0. The core uses `nextjson` for catalog parsing, `courierust` and `recurse-x` for URL validation, `rustbinary` for history and `tzcraft` for time conversion.

```sh
flutter pub get --enforce-lockfile
dart pub get --directory rust_builder/cargokit/build_tool --enforce-lockfile
cargo test --locked --manifest-path rust/Cargo.toml
flutter analyze --no-pub
flutter test --no-pub test
flutter test integration_test/playback_test.dart -d windows
python tool/ci/check_streams.py --require-episodes
```

Refresh both catalogs with `python tool/refresh_catalogs.py`. It uses Python, curl, ffprobe and ffmpeg. The workflow includes build commands for Android, iOS, Windows, macOS, Linux and Web. For Web, build the Rust Wasm module before the Flutter bundle. Serve `.wasm` as `application/wasm` with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: credentialless`. [Workflow](.github/workflows/stable.yml)

## Releases

Stable publication requires passing platform checks and verifiable full episodes in both categories. CI publishes the Windows x64 installer, signed universal Android APK, Ubuntu 24.04 x64 DEB, Web ZIP and `SHA256SUMS`. It compares build-runner and uploaded asset digests. Use `gh attestation verify <file> --repo blueokanna/Sableen` to verify provenance. Windows Authenticode and Apple distribution signing are currently unconfigured. [Actions](https://github.com/blueokanna/Sableen/actions/workflows/stable.yml) · [Published releases](https://github.com/blueokanna/Sableen/releases)
