<p align="center"><img src="assets/brand/sableen.png" alt="Sableen icon" width="76"></p>
<h1 align="center">Sableen</h1>
<p align="center">A Chinese-language theater for Hongguo short dramas and animated series, with episode-level history and offline playback.</p>
<p align="center"><a href="README.md">简体中文</a> · <a href="#catalog">Catalog measurements</a> · <a href="#build-and-verify">Build and verify</a> · <a href="https://github.com/blueokanna/Sableen/actions/workflows/stable.yml">Builds</a></p>

**1.0.1 release candidate**　The catalog contains 40 titles. Each currently offers one playable, downloadable preview of about ten seconds. **0 of 40** files meet the full-length 1080p release requirement. Stable publication is pending.

<p align="center"><img src="docs/theater.webp" alt="The Sableen theater at phone and desktop widths, with live-action and animated titles side by side" width="900"></p>

## Catalog

On November 22, 2026, all 20 files in each chart were checked. The examples below are the first episodes of the top-ranked titles. Durations refer to the video track measured with `ffprobe`. FFmpeg also decoded a frame near the end of each file. Container durations can be slightly longer because they include audio.

| Chart and title | Episode ID | Listed duration | Video available in Sableen |
| --- | --- | ---: | --- |
| Live-action · 少夫人来自东北3 | `7706514645208534041` | 178 s | 10.00 s · 360 × 640 · 25 fps |
| Animated · 公路求生榜一说她要走到公路尽头第三季 | `7708355470964050969` | 115 s | 10.00 s · 640 × 360 · 30 fps |

In fresh desktop Chrome sessions, Hongguo’s website played these episodes continuously to 178.48 s and 115.40 s. The public media files linked in the publisher’s episode metadata both end at about ten seconds. Sableen plays the available track to its end and displays decoded dimensions. [Live-action episode](https://hongguoduanju.com/player/7706512650816982040) · [Animated episode](https://hongguoduanju.com/player/7708355462780947518)

## Watching in Sableen

| Destination | What you can do |
| --- | --- |
| **剧场 · Theater** | Browse both charts in alternating rank order, search by title or genre, or switch to recommendations and individual charts. |
| **历史纪录 · History** | Resume a series or clear local history. Sableen retains up to 512 records keyed by series and episode ID. |
| **下载 · Downloads** | Follow transfers, pause, resume or retry, and select a saved episode to play it. |
| **设置 · Settings** | Select Simplified or Traditional Chinese, one or two columns, Dynamic Color, Monet or AMOLED. Navigation materials include solid, blur, Liquid Glass and Aero Glass. |

Opening a title enters fullscreen. Tap the center to pause or continue. Tap the edge or move the pointer to reveal the controls. A rotation control switches to landscape while preserving the picture’s aspect ratio. A visible window can keep playing while unfocused. Hiding the app pauses playback. Supported Android devices and browsers offer picture-in-picture. Closing the player releases its decoder.

Recommendations use time spent watching each genre, with a 21-day half-life. Seeking and buffering add no viewing time. Search, preferences and history stay on the device. Viewing requires no Sableen account.

## Saving an episode

1. Open **离线下载** in the player and choose the current episode. Multi-episode titles also offer a batch action.
2. Use **下载** to track or pause transfers. Native downloads follow the system proxy, with up to two episodes and two ranges per episode in flight. After restarting, resume retained ranges from Downloads.
3. An episode becomes available offline after byte-count and SHA-256 verification. Reopening it prefers the saved copy. The Web app uses the browser’s Cache Storage. Clearing site data removes those copies.

Serve the complete Web distribution over HTTPS or localhost, including `media/` and `sableen-offline.js`. On the first download the browser also verifies and caches the startup files, fonts and catalogs. Once an episode shows **已保存** (saved), you can close the tab, disconnect and reopen the same address in the same browser to play it from **下载** (Downloads).

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

Refresh the publisher-linked catalog and posters with `python tool/refresh_catalogs.py`. Set `SABLEEN_FFMPEG` and `SABLEEN_FFPROBE` to ByteVC2-capable builds when preparing that codec. Rust uses `nextjson` to parse catalogs, `courierust` and `recurse-x` to validate addresses, `rustbinary` to persist history and `tzcraft` for time calculations.

For Web, build Rust Wasm first, build the Flutter distribution, then run `python tool/stage_web_media.py build/web`. Serve Wasm as `application/wasm`, with `Cross-Origin-Opener-Policy: same-origin` and `Cross-Origin-Embedder-Policy: credentialless`. [Platform build commands](.github/workflows/stable.yml)

Stable publication requires passing six platform checks and package integrity checks. Every entry must match the listed duration, decode near the end and reach at least 1920 × 1080 in landscape or 1080 × 1920 in portrait. The `source-measurements` Actions artifact contains per-episode results. Distribution targets are a signed Android APK, Windows x64 installer, Ubuntu 24.04 x64 DEB, Web ZIP and `SHA256SUMS`. CI builds and tests iOS and macOS. Apple distribution signing and Windows Authenticode remain unconfigured. [Releases](https://github.com/blueokanna/Sableen/releases)
