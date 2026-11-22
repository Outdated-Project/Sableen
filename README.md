<p align="center"><img src="assets/brand/sableen.png" alt="Sableen 图标" width="76"></p>
<h1 align="center">Sableen 红果剧场</h1>
<p align="center">在一个播放器里浏览短剧与漫剧，按分集续播，保存到设备。</p>
<p align="center"><a href="README_EN.md">English</a> · <a href="#当前片库">片库实测</a> · <a href="#构建与验证">构建与验证</a> · <a href="https://github.com/blueokanna/Sableen/actions/workflows/stable.yml">构建记录</a></p>

**1.0.1 候选版的内容状态**　随包剧单有 40 部作品，每部目前可在应用内播放、下载一条约 10 秒的片段。整集 1080p 验收结果为 **0/40**，稳定版仍待发布。

<p align="center"><img src="docs/theater.webp" alt="Sableen 剧场实拍，手机和宽屏都在首行并列展示短剧与漫剧" width="900"></p>

## 当前片库

2026 年 11 月 22 日核验了两个榜单各 20 个文件。下表列出各榜首集。视频轨时长来自 `ffprobe`，片尾画面由 FFmpeg 实际解码。MP4 容器还包含音轨，容器总时长可以略长于视频轨。

| 榜单与作品 | 分集 ID | 发布页标注 | 应用可播视频轨 |
| --- | --- | ---: | --- |
| 真人剧 ·《少夫人来自东北3》 | `7706514645208534041` | 178 秒 | 10.00 秒 · 360 × 640 · 25 fps |
| 漫剧 ·《公路求生榜一说她要走到公路尽头第三季》 | `7708355470964050969` | 115 秒 | 10.00 秒 · 640 × 360 · 30 fps |

在新的桌面 Chrome 会话中，上述两集在红果网站分别连续播放至 178.48 秒和 115.40 秒。Sableen 使用发布页公开列出的媒体文件。两个样本的公开文件都在约 10 秒处结束。应用按媒体实际时长播放并显示解码尺寸。[真人剧分集](https://hongguoduanju.com/player/7706512650816982040) · [漫剧分集](https://hongguoduanju.com/player/7708355462780947518)

## 在剧场里观看

| 页面 | 可以做什么 |
| --- | --- |
| **剧场** | 「全部」按榜单名次交替排列短剧与漫剧。可按剧名或题材搜索，也可切换到猜你喜欢、红果短剧、红果漫剧。 |
| **历史纪录** | 从上次的位置继续观看，或清空本机历史。历史按作品和分集 ID 保存，最多 512 条。 |
| **下载** | 查看进度，暂停、继续或重试任务，点已保存的分集直接播放。 |
| **设置** | 切换简繁中文、单列或双列、动态配色、Monet 和 AMOLED。导航提供实色、模糊、液态玻璃与 Aero 玻璃。 |

点剧卡进入全屏。轻点中央暂停或继续，点边缘或移动鼠标唤回控件。屏幕方向按钮可切换横屏，画面保持原始比例。可见窗口失去焦点时继续播放，隐藏时暂停。Android 和支持标准画中画的浏览器可进入小窗。播放器关闭后释放解码器。

推荐使用实际观看时长和题材，权重每 21 天减半。拖动和缓冲不增加观看时间。剧单、封面和历史在设备端读取，无需 Sableen 账号。

## 保存与续传

1. 在播放器中打开 **离线下载**，选择当前分集。多集作品还提供整部下载。
2. 在 **下载** 页查看传输与校验状态。原生端按系统代理设置传输，最多同时下载两集，每集最多两条 Range 请求。重新打开应用后，残留分段可以从下载页继续。
3. 文件通过字节数和 SHA-256 校验后显示 **已保存**。再次点开该分集时优先读取本地副本。浏览器把文件存入当前站点的 Cache Storage，清除站点数据会同时清除下载。

Web 发行包提供同源 MP4，浏览器可以读取并校验字节。在 HTTPS 或 localhost 部署，保留包内的 `media/` 目录。已加载的应用可在断网后打开已保存的分集。完全离线冷启动网页还取决于宿主能否加载应用文件。

## ByteVC2 转码与实测

刷新剧单时，工具从 MP4 视频轨识别 `bvc2`，并用支持该解码器的 FFmpeg 将 SDR 视频转为 H.264。已有 AAC 音轨直接复用。转换完成后核对视频帧数、尺寸、音视频轨起止时间，计算全片 SSIM 和输出 SHA-256，再登记应用使用的文件。解码与编码发生在准备剧单的机器上。[转换实现](tool/transcode_bytevc2.py) · [兼容解码器](https://github.com/wxyzh/ffmpeg-bvc2)

在 Intel Core i7-11850H 上，以 FFmpeg `8.1.3-bvc2` 对同一份公开合成样本交替运行三组 x264 编码，每次均为 CRF 18。输入为 160 × 96、2 秒、20 帧、无音轨，两种输出均完整解码出 20 帧。[固定版本测试素材](https://github.com/jo32/tvbox-silicon/blob/ff2fc2c7a3ca6fc80c39277cca7b57b3ee792252/Tests/TVCoreTests/Fixtures/remux-bvc2.mp4)

| x264 预设 | 转码中位耗时 | 输出大小 | 全片 SSIM |
| --- | ---: | ---: | ---: |
| `medium` | 93.17 ms | 9,912 B | 0.996203 |
| `veryfast` | 87.11 ms | 10,145 B | 0.995055 |

这次实测为 **1.07 倍**，含进程启动时间。红果整集的三倍提速、带声素材的音画同步仍待代表性片源验证。可用以下命令在自己的素材上生成包含原始耗时、帧数、轨道偏差和摘要的 JSON 报告。

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

`python tool/refresh_catalogs.py` 按发布方的作品、分集和视频关联更新剧单。可设置 `SABLEEN_FFMPEG` 与 `SABLEEN_FFPROBE` 指向支持 ByteVC2 的构建。Rust 通过 `nextjson` 解析剧单、`courierust` 与 `recurse-x` 校验地址、`rustbinary` 编解码历史、`tzcraft` 计算时间权重。

Web 构建先生成 Rust Wasm，再构建 Flutter 并运行 `python tool/stage_web_media.py build/web`。服务器应以 `application/wasm` 提供 Wasm，发送 `Cross-Origin-Opener-Policy: same-origin` 与 `Cross-Origin-Embedder-Policy: credentialless`。[六端构建命令](.github/workflows/stable.yml)

六端检查与包完整性检查通过后，每个收录文件还须匹配分集时长、能在片尾解码，并达到横屏 1920 × 1080 或竖屏 1080 × 1920。GitHub Actions 的 `source-measurements` 包含逐集数据。发行物为签名 Android APK、Windows x64 安装程序、Ubuntu 24.04 x64 DEB、Web ZIP 和 `SHA256SUMS`。iOS 与 macOS 在 CI 构建和测试，Apple 分发签名与 Windows Authenticode 签名待配置。[发行记录](https://github.com/blueokanna/Sableen/releases)
