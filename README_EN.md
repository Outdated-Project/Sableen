<p align="center"><img src="assets/brand/sableen.png" alt="Sableen icon" width="76"></p>
<h1 align="center">Sableen</h1>
<p align="center">A Chinese-language theater for Hongguo short dramas and animated series, with episode-level history and offline playback.</p>
<p align="center"><a href="README.md">简体中文</a> · <a href="#catalog">Catalog measurements</a> · <a href="#build-and-verify">Build and verify</a> · <a href="https://github.com/blueokanna/Sableen/actions/workflows/stable.yml">Builds</a></p>

The **1.0.1 release candidate** includes 40 titles, each with a playable, downloadable first-episode preview of about ten seconds. Of the publisher’s 8,400 listed episodes, **0 have passed full-length 1080p verification**. The stable release is pending.

<p align="center"><img src="docs/theater.webp" alt="The Sableen theater at phone and desktop widths, with live-action and animated titles side by side" width="900"></p>

## Catalog

On November 22, 2026, the publisher listed 1,596 episodes across 20 live-action titles and 6,804 across 20 animated titles. The bundled catalogs retain all 8,400 episode IDs in published order. Each title has one playable first-episode preview. The release check compares episode IDs and order against the publisher and verifies each available file’s digest, duration, resolution and near-end frame. The table shows the video track duration from `ffprobe`. FFmpeg decoded a frame near the end of each file.

| Chart and title | Episode ID | Listed duration | Video available in Sableen |
| --- | --- | ---: | --- |
| Live-action · 少夫人来自东北3 | `7706514645208534041` | 178 s | 10.00 s · 360 × 640 · 25 fps |
| Animated · 公路求生榜一说她要走到公路尽头第三季 | `7708355470964050969` | 115 s | 10.00 s · 640 × 360 · 30 fps |

In fresh desktop Chrome sessions, Hongguo’s website played these episodes continuously to 178.48 s and 115.40 s. The public media files linked in the publisher’s episode metadata both end at about ten seconds. Sableen plays the available track to its end and displays decoded dimensions. [Live-action episode](https://hongguoduanju.com/player/7706512650816982040) · [Animated episode](https://hongguoduanju.com/player/7708355462780947518)

## Watching in Sableen

The open-source backend in ShortDrama Player lists whole seasons and plays episodes available on the publisher’s website. HongGuoFree uses the publisher’s web player for Hongguo titles. The Pangle content SDK requires application-specific configuration and documents Android and iOS integration. Sableen still needs a source for full-season 1080p playback and downloads on all six platforms. [ShortDrama Player](https://github.com/zuomeizuoyang/shortdrama-player) · [HongGuoFree](https://github.com/dudt/HongGuoFree) · [Content SDK documentation](https://www.csjplatform.com/supportcenter/28549)

| Destination | What you can do |
| --- | --- |
| **剧场 · Theater** | Browse both charts in alternating rank order, search by title or genre, or switch to recommendations and individual charts. |
| **历史纪录 · History** | Resume a series or clear local history. Sableen retains up to 512 records keyed by series and episode ID. |
| **下载 · Downloads** | Follow transfers, pause, resume or retry, and select a saved episode to play it. |
| **设置 · Settings** | Select Simplified or Traditional Chinese, one or two columns, Dynamic Color, Monet or AMOLED. Navigation materials include solid, blur, Liquid Glass and Aero Glass. |

The theater opens in two columns and remembers the layout selected beside the title. Aero floats in a capsule with 12 logical pixels of clearance on each side on narrow screens and a centered maximum width of 480 on wider screens. Liquid blurs the scrolling posters beneath the bar, preserves their color and increases opacity behind the labels. The selected icon has its own solid indicator. High contrast uses an opaque bar. Search, cards, navigation, selection controls, sheets and playback controls use Material components. The theme enables the Expressive variants supplied by `material_ui 1.11.1` for elevated and icon buttons and the updated appearances for sliders and progress indicators. [Apple materials](https://developer.apple.com/design/human-interface-guidelines/materials) · [Apple tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)

A Windows profile build scrolled through 40 titles at `1264 × 681`. Aero recorded 363 frames with P95 build and raster times of 1.98 ms and 3.98 ms. Liquid recorded 364 frames at 1.82 ms and 3.72 ms respectively. The Flutter image cache peaked at 2.26 MiB in both runs. Peak process working sets were 194.6 MiB and 201.4 MiB respectively.

Opening a title enters fullscreen. Tap the center to pause or continue, or tap the edge to reveal the controls. The episode picker lists every published episode number and the duration of available previews. “本应用尚未收录” means the app’s current catalog has no verified file for that episode. Tap the decoded dimensions to see the available resolutions. Switching between files preserves the playback position and play or pause state. Downloads use the selected file. Native players also list video tracks within the current file alongside separate files. Phones return to portrait after playback. Tablets and desktop windows retain their orientation. Visible windows can keep playing while unfocused. Hiding the app pauses playback. Supported Android devices and browsers offer picture-in-picture.

For long series, tap the episode range to jump between groups of 15. The player offers six playback speeds from 0.5× to 2×.

In fresh desktop Chrome sessions, the official 785-episode picker for 《全球死考：刚下刑场你让我去考试一季》 played episodes 2 and 5 without signing in. Continuous frame measurements reached 170.53 and 101.10 seconds respectively, both at 640 × 360. Selecting episode 6 showed a prompt to continue in the official app. The Sableen catalog currently includes the first episode’s preview for this series. [Official episode 2](https://hongguoduanju.com/player/7697459724635098174/7697465811157404697)

Recommendations use time spent watching each genre, with a 21-day half-life. Seeking and buffering add no viewing time. Search, preferences and history stay on the device. Viewing requires no Sableen account.

## Saving an episode

1. Open **离线下载** in the player and choose the current episode. Multi-episode titles also offer a batch action.
2. Use **下载** to track or pause transfers. Native downloads follow the system proxy, with up to two episodes and two ranges per episode in flight. After restarting, resume retained ranges from Downloads.
3. An episode becomes available offline after byte-count and SHA-256 verification. Reopening it prefers the saved copy. The Web app uses the browser’s Cache Storage. Clearing site data removes those copies.

Serve the complete Web distribution over HTTPS or localhost, including `media/` and `sableen-offline.js`. Serve MP4 files with HTTP byte-range support for seeking and resuming. On the first download the browser also verifies and caches the startup files, fonts and catalogs. Once an episode shows **已保存** (saved), you can close the tab, disconnect and reopen the same address in the same browser to play it from **下载** (Downloads).

## ByteVC2 conversion and measurement

Catalog preparation identifies the MP4 video sample entry, decodes SDR `bvc2` using a compatible FFmpeg build and encodes H.264. AAC audio can be copied directly. Preparation checks decoded frame count, dimensions and track boundaries, compares the entire picture sequence with SSIM, and records the output digest. Prepared files are bundled for the player and downloader. [Converter](tool/transcode_bytevc2.py) · [Compatible decoder](https://github.com/wxyzh/ffmpeg-bvc2)

On an Intel Core i7-11850H, FFmpeg `8.1.3-bvc2` encoded the same public synthetic fixture at x264 CRF 18 over three alternating pairs. The input contained 20 frames at 160 × 96 over two seconds, with no audio track. Both outputs decoded to 20 frames. [Pinned test input](https://github.com/jo32/tvbox-silicon/blob/ff2fc2c7a3ca6fc80c39277cca7b57b3ee792252/Tests/TVCoreTests/Fixtures/remux-bvc2.mp4)

| x264 preset | Median conversion time | Output size | Full-sequence SSIM |
| --- | ---: | ---: | ---: |
| `medium` | 93.17 ms | 9,912 B | 0.996203 |
| `veryfast` | 87.11 ms | 10,145 B | 0.995055 |

The measured ratio was **1.07×**, including process startup. A separate conversion added a two-second AAC tone to the fixture. The decoded PCM hashes matched and the track boundaries differed by 0 ms. A threefold speedup and dialogue synchronization still require testing on a representative Hongguo episode with audio. Run the comparison on another input to obtain the individual timings, frame counts, track-boundary differences and hashes as JSON.

```sh
python tool/transcode_bytevc2.py input.mp4 output.mp4 --benchmark
```

## Build and verify

The Flutter app is `1.0.1+2`. The Rust core and plugin are `1.0.1`. CI pins Flutter `3.47.9`, Rust `1.99.1` and flutter_rust_bridge `2.13.0`. With Python, curl, FFmpeg and ffprobe installed, run the following from the project root.

```sh
flutter pub get --enforce-lockfile
dart pub get --directory rust_builder/cargokit/build_tool --enforce-lockfile
cargo test --locked --manifest-path rust/Cargo.toml
flutter analyze --no-pub
flutter test --no-pub test
flutter test integration_test/playback_test.dart -d windows
python tool/ci/check_streams.py --require-episodes --report source-measurements.json
```

`python tool/refresh_catalogs.py` follows episode links on public series pages and reads the MP4 encodings listed or referenced by each episode’s JSON-LD video object. It keeps distinct resolutions with matching durations. SDR HEVC, AV1, VP9 and ByteVC2 encodings can be prepared as AVC playback and download files at their original dimensions. Set `SABLEEN_FFMPEG` and `SABLEEN_FFPROBE` to builds that decode the source codec. Rust uses `nextjson` to parse catalogs, `courierust` and `recurse-x` to validate addresses, `rustbinary` to persist history and `tzcraft` for time calculations.

For Web, build Rust Wasm first, build the Flutter distribution, then run `python tool/stage_web_media.py build/web`. Serve Wasm as `application/wasm`, with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: credentialless`. [Platform build commands](.github/workflows/stable.yml)

Stable publication requires passing six platform checks and package integrity checks. Every entry must match the listed duration, decode near the end and reach at least 1920 × 1080 in landscape or 1080 × 1920 in portrait. The `source-measurements` Actions artifact contains per-episode results. Distribution targets are a signed Android APK, Windows x64 installer, Ubuntu 24.04 x64 DEB, Web ZIP and `SHA256SUMS`. CI builds and tests iOS and macOS. Apple distribution signing and Windows Authenticode remain unconfigured. [Releases](https://github.com/blueokanna/Sableen/releases)
