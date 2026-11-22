<p align="center"><img src="assets/brand/sableen.png" alt="Sableen 图标" width="76"></p>
<h1 align="center">Sableen 红果剧场</h1>
<p align="center">在一个播放器里浏览短剧与漫剧，按分集续播，保存到设备。</p>
<p align="center"><a href="README_EN.md">English</a> · <a href="#当前片库">片库实测</a> · <a href="#构建与验证">构建与验证</a> · <a href="https://github.com/blueokanna/Sableen/actions/workflows/stable.yml">构建记录</a></p>

**1.0.1 候选版**收录 40 部作品，每部可在应用内播放、下载一条约 10 秒的首集片段。发布方列出的 8,400 集中，**0 集通过完整 1080p 验收**，稳定版仍待发布。

<p align="center"><img src="docs/theater.webp" alt="Sableen 剧场实拍，手机和宽屏都在首行并列展示短剧与漫剧" width="900"></p>

## 当前片库

2026 年 11 月 22 日，20 部短剧的详情页共列出 1,596 集，20 部漫剧共列出 6,804 集。随包剧单保存了全部 8,400 个分集 ID 及发布顺序，每部有一个可播放的首集片段。发布检查逐部核对分集 ID、集号、文件摘要、时长、分辨率和片尾解码。下表的时长来自 `ffprobe` 视频轨，片尾画面由 FFmpeg 实际解码。

| 榜单与作品 | 分集 ID | 发布页标注 | 应用可播视频轨 |
| --- | --- | ---: | --- |
| 真人剧 ·《少夫人来自东北3》 | `7706514645208534041` | 178 秒 | 10.00 秒 · 360 × 640 · 25 fps |
| 漫剧 ·《公路求生榜一说她要走到公路尽头第三季》 | `7708355470964050969` | 115 秒 | 10.00 秒 · 640 × 360 · 30 fps |

在新的桌面 Chrome 会话中，上述两集在红果网站分别连续播放至 178.48 秒和 115.40 秒。Sableen 使用发布页公开列出的媒体文件。两个样本的公开文件都在约 10 秒处结束。应用按媒体实际时长播放并显示解码尺寸。[真人剧分集](https://hongguoduanju.com/player/7706512650816982040) · [漫剧分集](https://hongguoduanju.com/player/7708355462780947518)

## 在剧场里观看

在未登录的桌面 Chrome 中，从《全球死考：刚下刑场你让我去考试一季》的 785 集选集进入第 2 集和第 5 集，两集分别连续解码至 170.53 秒和 101.10 秒，实测尺寸均为 640 × 360。点第 6 集时，网页显示「短剧独家内容，前往App端观看全部内容」。Sableen 当前剧单只收录了这部作品的首集片段。[官方第 2 集](https://hongguoduanju.com/player/7697459724635098174/7697465811157404697)

对照过的开源播放器依赖不同的片源。ShortDrama Player 的开源后端列出完整选集，播放范围取决于官网开放的单集；HongGuoFree 的红果专区使用官方网页播放器。穿山甲的内容输出 SDK 要求应用专属配置，公开接入文档覆盖 Android 和 iOS。目前缺少可供 Sableen 六端播放和离线下载的全季 1080p 内容源。[ShortDrama Player](https://github.com/zuomeizuoyang/shortdrama-player) · [HongGuoFree](https://github.com/dudt/HongGuoFree) · [内容 SDK 接入说明](https://www.csjplatform.com/supportcenter/28549)

| 页面 | 可以做什么 |
| --- | --- |
| **剧场** | 「全部」按榜单名次交替排列短剧与漫剧。可按剧名或题材搜索，也可切换到猜你喜欢、红果短剧、红果漫剧。 |
| **历史纪录** | 从上次的位置继续观看，或清空本机历史。历史按作品和分集 ID 保存，最多 512 条。 |
| **下载** | 查看进度，暂停、继续或重试任务，点已保存的分集直接播放。 |
| **设置** | 切换简繁中文、单列或双列、动态配色、Monet 和 AMOLED。导航提供实色、模糊、液态玻璃与 Aero 玻璃。 |

剧场默认双列，标题栏可切换到单列并保存选择。Aero 是悬浮胶囊，窄屏左右各留 12 个逻辑像素，宽屏居中、最大宽度 480。Liquid 在栏内模糊当前滚动内容，保留海报色彩，并在标签背后加深材质。选中图标有独立的实色底，系统高对比度模式使用实色栏。搜索栏、剧卡、导航、选项、弹层和播放控件采用 Material 组件。`material_ui 1.11.1` 提供 Expressive 变体的 ElevatedButton 和 IconButton 已在主题中启用，滑块和进度条使用新版外观。[Apple 材质指南](https://developer.apple.com/design/human-interface-guidelines/materials) · [Apple 标签栏指南](https://developer.apple.com/design/human-interface-guidelines/tab-bars)

Windows profile 构建在 `1264 × 681` 窗口中滚动浏览 40 部作品。Aero 采集 363 帧，P95 构建和光栅化耗时为 1.98 和 3.98 ms。Liquid 采集 364 帧，对应耗时为 1.82 和 3.72 ms。两次测试的 Flutter 图片缓存峰值均为 2.26 MiB，进程工作集峰值分别为 194.6 和 201.4 MiB。

点剧卡进入全屏，轻点中央暂停或继续，点边缘唤回控件。「选集」列出发布方的全部集号，可播片段标注实际时长。「本应用尚未收录」表示当前剧单没有该集的已核验文件。点播放器的解码尺寸可查看可选分辨率。切换独立文件会保留进度和暂停状态，离线下载使用所选文件。原生端同时列出当前文件内的视频轨。手机退出播放器后恢复竖屏，平板和桌面保留窗口方向。可见小窗可继续播放，隐藏应用会暂停。Android 和支持标准画中画的浏览器可进入小窗。

推荐使用实际观看时长和题材，权重每 21 天减半。拖动和缓冲不增加观看时间。剧单、封面和历史在设备端读取，无需 Sableen 账号。

长剧选集每 15 集一组，点击集号区间即可跳至其他组。播放控制栏可在 0.5× 至 2× 之间切换六档倍速。

## 保存与续传

1. 在播放器中打开 **离线下载**，选择当前分集。多集作品还提供整部下载。
2. 在 **下载** 页查看传输与校验状态。原生端按系统代理设置传输，最多同时下载两集，每集最多两条 Range 请求。重新打开应用后，残留分段可以从下载页继续。
3. 文件通过字节数和 SHA-256 校验后显示 **已保存**。再次点开该分集时优先读取本地副本。浏览器把文件存入当前站点的 Cache Storage，清除站点数据会同时清除下载。

Web 发行包提供同源 MP4。在支持 HTTP 字节范围请求的 HTTPS 或 localhost 静态服务器部署完整发行包，保留 `media/` 和 `sableen-offline.js`，以便播放器跳转和续播。首次下载时，浏览器也会校验并缓存启动文件、字体和剧单。显示 **已保存** 后，即使关闭标签页并断网，也可以在同一浏览器重新打开原地址，从 **下载** 页播放。

## ByteVC2 转码与实测

刷新剧单时，工具从 MP4 视频轨识别 `bvc2`，并用支持该解码器的 FFmpeg 将 SDR 视频转为 H.264。已有 AAC 音轨直接复用。转换完成后核对视频帧数、尺寸、音视频轨起止时间，计算全片 SSIM 和输出 SHA-256，再登记应用使用的文件。解码与编码发生在准备剧单的机器上。[转换实现](tool/transcode_bytevc2.py) · [兼容解码器](https://github.com/wxyzh/ffmpeg-bvc2)

在 Intel Core i7-11850H 上，以 FFmpeg `8.1.3-bvc2` 对同一份公开合成样本交替运行三组 x264 编码，每次均为 CRF 18。输入为 160 × 96、2 秒、20 帧、无音轨，两种输出均完整解码出 20 帧。[固定版本测试素材](https://github.com/jo32/tvbox-silicon/blob/ff2fc2c7a3ca6fc80c39277cca7b57b3ee792252/Tests/TVCoreTests/Fixtures/remux-bvc2.mp4)

| x264 预设 | 转码中位耗时 | 输出大小 | 全片 SSIM |
| --- | ---: | ---: | ---: |
| `medium` | 93.17 ms | 9,912 B | 0.996203 |
| `veryfast` | 87.11 ms | 10,145 B | 0.995055 |

这次实测为 **1.07 倍**，含进程启动时间。另一次测试为同一视频配上两秒 AAC 测试音，转码前后解码出的 PCM 摘要相同，音视频轨起止时间偏差为 0 毫秒。红果整集的三倍提速和对白同步仍待带声正片验证。以下命令可在自己的素材上生成包含原始耗时、帧数、轨道偏差和摘要的 JSON 报告。

```sh
python tool/transcode_bytevc2.py input.mp4 output.mp4 --benchmark
```

## 构建与验证

Flutter 应用版本为 `1.0.1+2`，Rust 核心与插件为 `1.0.1`。CI 固定 Flutter `3.47.9`、Rust `1.99.1`、flutter_rust_bridge `2.13.0`。准备 Python、curl、FFmpeg 与 ffprobe 后，在仓库根目录运行以下命令。

```sh
flutter pub get --enforce-lockfile
dart pub get --directory rust_builder/cargokit/build_tool --enforce-lockfile
cargo test --locked --manifest-path rust/Cargo.toml
flutter analyze --no-pub
flutter test --no-pub test
flutter test integration_test/playback_test.dart -d windows
python tool/ci/check_streams.py --require-episodes --report source-measurements.json
```

`python tool/refresh_catalogs.py` 读取公开详情页的分集链接，并解析该集视频对象直接列出或通过 JSON-LD 引用的 MP4 编码。对于时长匹配的不同尺寸文件，工具保留各档分辨率。SDR HEVC、AV1、VP9 和 ByteVC2 编码可在构建时转换为原尺寸 AVC 供播放和下载。可设置 `SABLEEN_FFMPEG` 与 `SABLEEN_FFPROBE` 指向支持源编码的构建。Rust 通过 `nextjson` 解析剧单、`courierust` 与 `recurse-x` 校验地址、`rustbinary` 编解码历史、`tzcraft` 计算时间权重。

Web 构建先生成 Rust Wasm，再构建 Flutter 并运行 `python tool/stage_web_media.py build/web`。服务器应以 `application/wasm` 提供 Wasm，发送 `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: credentialless`。[六端构建命令](.github/workflows/stable.yml)

六端检查与包完整性检查通过后，每个收录文件还须匹配分集时长、能在片尾解码，并达到横屏 1920 × 1080 或竖屏 1080 × 1920。GitHub Actions 的 `source-measurements` 包含逐集数据。发行物为签名 Android APK、Windows x64 安装程序、Ubuntu 24.04 x64 DEB、Web ZIP 和 `SHA256SUMS`。iOS 与 macOS 在 CI 构建和测试，Apple 分发签名与 Windows Authenticode 签名待配置。[发行记录](https://github.com/blueokanna/Sableen/releases)
