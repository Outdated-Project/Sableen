# Sableen

[简体中文](README.md)

Open the theater to watch all twelve episodes of 《梦笔不能停》, a Hongguo co-production streamed by CCTV. The bundled catalog also includes Guangzhou short dramas and public clips from Hongguo. Select a title to play, choose an episode or resume watching. Watch history and genre preferences stay on the device. The interface supports Simplified and Traditional Chinese.

### Available media

| Publisher | Bundled catalog | Verification |
| --- | --- | --- |
| [CCTV, 《梦笔不能停》](https://v.cctv.cn/yangjuchang/mbbnt/) | One Hongguo co-production, 12 full episodes | The refresh tool reads CCTV’s episode directory, checks the public playback and preview flags and probes the HLS video track. All twelve stream durations matched the listed lengths within two seconds |
| [Hongguo live-action ranking](https://hongguoduanju.com/rank/hot-search-real-drama) | 20 titles with one public clip of about 10 seconds each | The refresh tool matches each episode to its player page and `VideoObject.contentUrl`, then measures the MP4 duration. Cards and the episode selector identify the clips. An anonymous full-episode feed covering the wider Hongguo library remains open |
| [Guangzhou short-drama showcase](https://www.gzjjjc.gov.cn/ljgzw/ztzl/ljwhwdj/) | 8 titles and 20 episode videos, including all six listed episodes of 《源起》 | Each SD stream comes from the publisher’s embedded player. `ffprobe` confirmed a video track and positive duration for every entry |

Catalog metadata and WebP posters ship with the app. Browsing the bundled catalog makes no poster requests to publishers. Videos stream over HTTPS on demand. Playback requires no account. The app contains no advertising SDK and skips ad intervals identified in a catalog. Publishers can change or withdraw media. Media servers receive playback requests including the viewer’s network address.

Open **添加片源 / 新增片源** to subscribe to an HTTPS feed, import a direct video URL or return to the bundled catalog. Maintainers can run `python tool/refresh_catalogs.py` from the project root with Python 3, curl, ffprobe and ffmpeg installed to refresh the catalogs and posters before rebuilding. Guangzhou posters use a frame from each title’s first episode.

## Build and run

Development uses Flutter 3.47.9, Dart 3.13.7, Rust edition 2024 and `flutter_rust_bridge` 2.13.0. Apple builds use macOS, Xcode and CocoaPods. The Rust build phase uses the `always_out_of_date` option supported by CocoaPods 1.16.2. Linux desktop requires the Flutter Linux toolchain and development packages for GTK 3, libmpv and libepoxy.

```sh
flutter pub get
flutter devices
flutter run -d windows
```

Use the relevant device ID for other native targets. Build with `flutter build apk --release`, `flutter build ios --release`, `flutter build windows`, `flutter build macos` or `flutter build linux`. Pass `--dart-define=SABLEEN_CATALOG_URL=<HTTPS-feed-URL>` to load a feed on first launch. Subsequent launches restore the local snapshot. Submit the URL again to refresh it.

Android uses a debug signing key for local validation. For distribution, set `storeFile`, `storePassword`, `keyAlias` and `keyPassword` in `android/key.properties`. Relative keystore paths resolve from `android/`. On Windows, if Kotlin reports `different roots` for a Pub cache and a project on different drives, set `$env:GRADLE_OPTS='-Dorg.gradle.project.kotlin.incremental=false'` in the current PowerShell session and rebuild.

### Web

```sh
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
cargo install wasm-pack --locked
rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown
flutter_rust_bridge_codegen build-web --release
flutter build web --release --no-web-resources-cdn
```

Serve all of `build/web`, including `pkg/`, over HTTPS or localhost. Set the Wasm MIME type to `application/wasm`. Rust worker threads use shared memory. Configure the following response headers. Cross-origin catalog servers must allow CORS. Media and cover servers must permit the browser’s resource request mode. The browser determines codec support, autoplay and presentation cadence.

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

Using `require-corp` in place of `credentialless` requires matching CORP or CORS headers on cross-origin resources. After changing the Rust API, run `flutter_rust_bridge_codegen generate` and rebuild the target.

## Catalog contract

Serve UTF-8 JSON directly with HTTP 200. An empty catalog is valid.

```json
{"version":1,"dramas":[]}
```

| Field | Contract |
| --- | --- |
| `dramas` | Up to 1,000 titles. The response is limited to 1 MiB |
| Drama `id`, `title` | Unique catalog ID up to 96 bytes. Title up to 384 bytes |
| `tags` | 1–12 distinct genres, up to 72 bytes each |
| `cover` | Optional HTTPS image URL or `null` |
| `episodes` | 1–600 entries in playback order |
| Episode `id`, `title`, `url` | ID unique within its drama, display title and HTTPS media URL. The drama ID and title length limits also apply here |
| Episode `ad_breaks` | Optional array of up to 64 half-open millisecond ranges such as `{"start_ms":1000,"end_ms":2000}`. Sort by start time and leave a gap between consecutive ranges |

Text fields require visible content. URLs use ASCII and are limited to 4,096 bytes. History is scoped to each feed URL and keyed by stable drama and episode IDs. Direct imports have their own local catalog. The app retains the latest 512 distinct episode entries and stores them in a binary frame beginning with `SW01`.

To test a catalog server, serve the following feed with the public Flutter documentation clip.

```json
{
  "version": 1,
  "dramas": [{
    "id": "flutter-butterfly",
    "title": "Flutter butterfly sample",
    "tags": ["Nature"],
    "episodes": [{
      "id": "clip",
      "title": "Butterfly",
      "url": "https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4"
    }]
  }]
}
```

## Recommendation model

For an episode record $e$, let $w_e$ denote watched milliseconds, $d_e$ duration and $t_e$ the most recent update in Unix seconds. The playhead is stored separately for resuming. Repeat viewing contributes to watched time up to the duration. With current time $t$ and half-life $H=21\times86400$ seconds, define

$$a_e=\frac{\min(w_e,d_e)}{d_e+60\,000}\,2^{-\max(0,t-t_e)/H}.$$

The 60,000 ms term discounts very short clips. At age zero, finishing a ten-second clip contributes $1/7$, while watching two minutes of a four-minute episode contributes $2/5$. Seeking, buffering and time spent in the background do not add watch evidence.

Only records with positive watched time and duration contribute. Write $T_i$ for the genre set of title $i$ in the current catalog and $A_i=\sum_{e\in i}a_e$. Genre weight is $b_g=1+\sum_{i:g\in T_i}A_i/|T_i|$. Sort unseen titles by decreasing mean genre weight, breaking ties by catalog order.

$$s_j=\frac{1}{|T_j|}\sum_{g\in T_j}b_g.$$

Each title distributes exactly $|T_i|A_i/|T_i|=A_i$ total evidence across its genres. Under a uniform draw from a candidate’s genres the expected weight equals $s_j$. For any nonnegative decreasing position weights $q_k$, swapping an inverted pair at $k<l$ increases the objective $\sum_k q_k s_{j_k}$ by $(q_k-q_l)(s_{j_l}-s_{j_k})\ge0$. Repeating the exchange establishes optimality for this objective. The result assumes uniform genre attribution and the stated utility. Predicting viewer satisfaction requires empirical evaluation. At cold start every score equals one. The 21-day half-life is a design parameter.

## Aurora rendering and playback

`lib/design.dart` centralizes application-level rendering policy. Page routes share the Material fade-forwards transition, and tab entry uses shared motion parameters. A system request for reduced motion sets the custom tab animation duration to zero. Backdrop filters are clipped to the capsule and the playback timeline updates independently. Flutter handles scene composition and GPU scheduling.

The interface uses Material 3 components, Expressive shapes and button variants from `material_ui`. `dynamic_color` supplies available system palettes. Monet derives a palette from a seed and AMOLED mode uses a black background. The navigation capsule offers a solid fill, live Gaussian blur, liquid refraction and an Aero glass gradient. Backends supporting `ImageFilter.shader` run the refraction shader. Other backends use clipped backdrop blur. Catalog columns and the episode selector adapt to the available width.

Each player page owns one `media_kit` instance, requests hardware acceleration, pauses in the background and releases the player on exit. Android requests the lowest compatible same-resolution display mode at an integer multiple of the reported source frame rate. Pausing, buffering and leaving the page release the request. The display system determines the effective mode. Other targets use system or browser presentation timing. Device measurements are required for thermal, energy and dropped-frame claims.

| Rust dependency | Role |
| --- | --- |
| `courierust` 1.1.3 / `recurse-x` 0.2.6 | Parse HTTPS URLs and validate DNS name syntax |
| `nextjson` 0.1.5 | Deserialize catalog JSON |
| `rustbinary` 0.1.10 | Encode and decode compact history frames |
| `tzcraft` 0.1.2 | Convert the recommendation half-life to seconds |

## Verification

```sh
cargo test --locked --manifest-path rust/Cargo.toml
flutter analyze
flutter test test/interface_test.dart
flutter test integration_test/playback_test.dart -d windows
```

Pass `--dart-define=TEST_MEDIA_URL=<HTTPS-video-URL>` to test another clip lasting at least several seconds.

| Target | Verification result |
| --- | --- |
| Windows x64 | Release build succeeded. The integration test played a Hongguo clip, 《源起》 and the 550.882-second first episode of 《梦笔不能停》. It also verified episode switching, watch accounting after a seek, disk persistence and resume. The Flutter test clip reported `d3d11va-copy` hardware decoding and a source frame rate of 29.970030 fps |
| Android 17 · PLK110 | The release APK passed signature verification and contains Flutter, Rust and libmpv libraries for arm64-v8a, armeabi-v7a and x86_64. A debug build played the remote clip on the device, advanced past one second and passed the binary history round trip. The phone disconnected before the extended disk persistence and decoder checks could run |
| Web · Chrome | The release app played all three sources under Chrome’s default playback policy. The 550.882-second first episode of 《梦笔不能停》 resumed from 30 seconds after reopening. Chrome reported 486.72 seconds for the first episode of 《源起》 and 10.08 seconds for the Hongguo clip 《做兄弟，在心中》. The checks also covered custom feeds, history after page reload, all four capsule settings and Traditional Chinese. This build combines Dart compiled to JavaScript with Rust compiled to Wasm |
| iOS arm64 and macOS arm64 | Release-mode Dart kernel compilation succeeded for both Flutter targets. Separate Rust archives contain arm64 Mach-O objects and the FRB entry point. Xcode application linking, signing and device playback still require verification |
| Linux x64 | Release-mode Dart kernel compilation succeeded. On a Linux 6.8 kernel in QEMU, the Rust shared library loaded, its FRB interface hash matched the Dart bindings and all six Rust tests passed. The GTK desktop app build and video playback still require verification |

All six Rust tests and Clippy passed. `flutter analyze` reported no issues. The Flutter widget test verified Traditional Chinese navigation and glass preferences at widths of 360 and 1,280 logical pixels. Effective display modes, thermals, energy use and visual parity across all six targets still require device measurements.
