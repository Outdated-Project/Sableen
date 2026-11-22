# Sableen 红果剧场

[English](README_EN.md)

Sableen 在同一个剧场里提供红果短剧和红果漫剧。界面支持简体、繁体、系统动态配色、Monet 与 AMOLED 黑色主题。搜索、历史和推荐都在设备上运行。

## 现在能播什么

| 红果官网榜单 | 1.0.1 随包核验结果 | 可直接核对的作品 |
| --- | --- | --- |
| [真人剧热播榜](https://hongguoduanju.com/rank/hot-real-drama) | 20 部，每部 1 条公开片段 | [《少夫人来自东北3》播放页](https://hongguoduanju.com/player/7706512650816982040) · [实测 10.08 秒 MP4](https://hongguoduanju.com/video/public/7706514645208534041/360p.mp4) |
| [漫剧热播榜](https://hongguoduanju.com/rank/hot-comic-drama) | 20 部，每部 1 条公开片段 | [《公路求生榜一说她要走到公路尽头第三季》播放页](https://hongguoduanju.com/player/7708355462780947518) · [实测 10.07 秒 MP4](https://hongguoduanju.com/video/public/7708355470964050969/360p.mp4) |

2026 年 11 月 22 日，在没有账号和既有 Cookie 的桌面 Chrome 中，关闭红果官网的登录弹窗后，上表两部作品的首集都能播放。播放器报告的集长分别为 178.97 秒和 115.87 秒。通过官网进度条跳到片尾附近后，两集画面都继续前进。Sableen 播放控件里的「红果官网观看」打开对应分集。官网内的进度由红果播放器管理。

Sableen 自带播放器和离线下载使用发布页标明的 `VideoObject.contentUrl`。刷新工具校对作品和分集 ID，用 `ffprobe` 测量公开 MP4 的实际时长。这 40 个文件均为约 10 秒的片段。榜单、封面随包提供。

## 播放和设备行为

Android 在红果仅提供片段或播放失败时显示「西饭」。点按后打开设备上已安装的西饭短剧，可在西饭内搜索剧名。西饭尚未提供可核验的跨平台分集链接，切换时不会同步集数或进度。

### 离线下载

在原生播放器中打开「离线下载」，选择标有集数和可用时长的视频。也可以在首页查看队列、暂停全部任务或继续下载。再次点开已保存的剧目时，播放器优先使用设备内的副本。Web 版在线播放。下载运行于应用进程内，退出应用后可重新添加未完成的分集。

每个任务使用发布方公开的 MP4 和系统代理设置。队列最多同时传输两集，达到 1 MiB 的视频可用两条 Range 请求，总计最多四段。下载遇到短暂网络错误会有限重试。进度按 250 毫秒合并通知。文件在独立工作目录中组装，后台校验随包剧单记录的字节数和 SHA-256，校验通过后才显示「已保存」。本次收录的 40 条视频均为片段，可用时长与在线播放一致。

点开剧卡进入全屏，轻点中央暂停或继续。播放时控件在三秒后收起，点画面边缘或移动鼠标可重新显示。隐藏应用时暂停，单纯失去窗口焦点时继续播放。支持系统画中画的 Android 设备和支持标准画中画接口的浏览器可从播放器右上角进入小窗。返回前台后由用户决定是否继续。

单个播放页持有一个解码器，关闭页面时释放。原生播放器请求硬解，Android 根据视频帧率申请同分辨率的兼容显示模式。系统和驱动决定实际解码与刷新率。时间显示独立刷新，封面以 WebP 本地加载。材质设置提供实色、实时模糊、液态折射与 Aero 玻璃。

历史按红果作品和分集 ID 索引，最多保留 512 条。推荐按题材累计有效观看时间，21 天半衰；每条记录的基础权重为 `min(观看毫秒数, 片长) / (片长 + 60000)`。拖动与缓冲时间不算观看。

## 构建和核验

Flutter 应用 `1.0.1+2`，Rust 核心 `1.0.1`。CI 固定 Flutter 3.47.9、Rust 1.99.1 与 flutter_rust_bridge 2.13.0。Rust 用 `nextjson` 读剧单，`courierust` 和 `recurse-x` 校验地址，`rustbinary` 保存历史，`tzcraft` 换算时间。

```sh
flutter pub get --enforce-lockfile
dart pub get --directory rust_builder/cargokit/build_tool --enforce-lockfile
cargo test --locked --manifest-path rust/Cargo.toml
flutter analyze --no-pub
flutter test --no-pub test
flutter test integration_test/playback_test.dart -d windows
python tool/ci/check_streams.py --require-episodes
```

更新剧单运行 `python tool/refresh_catalogs.py`，需要 Python、curl、ffprobe 和 ffmpeg。Flutter 支持 Android、iOS、Windows、macOS、Linux 与 Web 构建。Web 还需先生成 Rust Wasm，详见工作流中的 `web` 任务。服务器应提供正确的 Wasm MIME 类型，以及 `Cross-Origin-Opener-Policy: same-origin` 和 `Cross-Origin-Embedder-Policy: credentialless` 两个响应头。[完整构建命令](.github/workflows/stable.yml)

## 发行

`main` 的候选版本必须通过六端检查，并且两类内容都要有可验证的正片。通过后上传 Windows x64 安装程序、签名 Android 通用 APK、Ubuntu 24.04 x64 DEB、Web ZIP 和 `SHA256SUMS`。CI 逐个比对构建端与上传后的摘要。可用 `gh attestation verify <文件> --repo blueokanna/Sableen` 验证来源。Windows 缺少 Authenticode，Apple 安装包还需要发行签名配置。[构建记录](https://github.com/blueokanna/Sableen/actions/workflows/stable.yml) · [已发布版本](https://github.com/blueokanna/Sableen/releases)
