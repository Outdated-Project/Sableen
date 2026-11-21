# Sableen 短剧剧场

[English](README_EN.md)

## 稳定版下载与自动发布

从 [GitHub Releases](https://github.com/blueokanna/Sableen/releases/latest) 下载已发布的版本。Windows x64 使用 `.exe` 安装程序，Android 使用通用 `.apk`，Ubuntu 24.04 x64 使用 `.deb`。Web 压缩包供服务器部署使用。iOS 和 macOS 参加 CI 编译和播放测试，Apple 安装包需要发行证书与分发配置。Windows 安装程序目前使用 GitHub 构建证明验证来源，未配置 Authenticode 签名。

`main` 更新后，[GitHub Actions](https://github.com/blueokanna/Sableen/actions/workflows/stable.yml) 自动读取 `pubspec.yaml` 的三段版本号，并在全部必需任务成功后发布新版本。构建任务记录包的 SHA-256，发布任务复核四个产物、生成来源证明，并逐一比对 GitHub 草稿附件的摘要。已经公开的版本不会被流水线覆盖。可用 `gh attestation verify 文件名 --repo blueokanna/Sableen` 验证来源，并与同一 Release 中的 `SHA256SUMS` 比对。

首次打开即可播放红果联合出品、央视网展播的《梦笔不能停》全 12 集。公共剧场还收录广州发布方展播的微短剧和红果官网公开片段。点开剧目可播放、选集或续播。观看历史和题材偏好保存在本机，界面可切换简体中文与繁体中文。

### 可播放内容

| 来源 | 随包剧单 | 核验依据 |
| --- | --- | --- |
| [央视网《梦笔不能停》](https://v.cctv.cn/yangjuchang/mbbnt/) | 1 部、12 集正片，红果短剧联合出品 | 读取发布方分集目录及公开 HLS 播放信息，检查可播放状态、正片标记和视频轨。12 集的流时长均与目录相差不到 2 秒 |
| [红果真人剧热搜榜](https://hongguoduanju.com/rank/hot-search-real-drama) | 20 部作品，各有一条约 10 秒的公开片段 | 逐集匹配播放页的 `VideoObject.contentUrl`，读取 MP4 容器时长。剧卡与选集列表显示「片段」。仍缺覆盖红果片库的匿名正片接口 |
| [广州廉洁文化微短剧](https://www.gzjjjc.gov.cn/ljgzw/ztzl/ljwhwdj/) | 8 部作品、20 条分集视频，包括《源起》6 集 | 使用发布页播放器列出的 SD 视频。每条均通过 `ffprobe` 确认含有视频轨和有效时长 |

剧单与 WebP 封面随包提供，打开剧场时无需从发布方加载海报。影片通过 HTTPS 按需播放。应用免登录，没有广告 SDK；对剧单标注的广告区间，播放器会自动快进。发布方可以变更或下架视频，媒体服务器能看到播放请求的网络地址。

「添加片源」支持自订 HTTPS 剧单、视频直链，也可切回公共剧场。维护者可在项目根目录执行 `python tool/refresh_catalogs.py`，使用 Python 3、curl、ffprobe 和 ffmpeg 重新核验片源并生成封面，然后重建应用。广州微短剧的封面取自各剧首集画面。

## 使用与构建

开发环境使用 Flutter 3.47.9、Dart 3.13.7、Rust 2024 edition 和 `flutter_rust_bridge` 2.13.0。Apple 平台使用 macOS、Xcode 和 CocoaPods，Rust 构建阶段使用 CocoaPods 1.16.2 支持的 `always_out_of_date`。Linux 桌面需要 Flutter Linux 工具链，以及 GTK 3、libmpv 和 libepoxy 的开发包。

```sh
flutter pub get
flutter devices
flutter run -d windows
```

将 `windows` 替换为设备 ID 可在其他原生目标运行。发布构建使用 `flutter build apk --release`、`flutter build ios --release`、`flutter build windows`、`flutter build macos` 或 `flutter build linux`。可通过 `--dart-define=SABLEEN_CATALOG_URL=<HTTPS剧单地址>` 指定首次启动时加载的剧单。本地快照存在时优先恢复快照，在「添加片源」重新提交地址可更新剧单。

Android 本地构建默认使用调试密钥。发行签名可在 `android/key.properties` 中配置 `storeFile`、`storePassword`、`keyAlias` 和 `keyPassword`，相对密钥路径以 `android/` 为基准。Windows 主机上若 Kotlin 报 `different roots`，可在当前 PowerShell 会话执行 `$env:GRADLE_OPTS='-Dorg.gradle.project.kotlin.incremental=false'`，然后重新构建。

### Web

```sh
cargo install flutter_rust_bridge_codegen --version 2.13.0 --locked
cargo install wasm-pack --locked
rustup toolchain install nightly --component rust-src --target wasm32-unknown-unknown
flutter_rust_bridge_codegen build-web --release
flutter build web --release --no-web-resources-cdn
```

部署 `build/web` 的全部文件，包括 `pkg/`。通过 HTTPS 或 localhost 提供页面，将 `.wasm` 的 MIME 类型设为 `application/wasm`。Rust 工作线程使用共享内存，服务端需发送以下响应头。跨域剧单必须允许浏览器的 CORS 请求，视频和封面应允许对应的跨域加载方式。浏览器决定视频格式支持、自动播放策略和显示节奏。

```http
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

若使用 `require-corp` 替代 `credentialless`，跨域资源还需相应的 CORS 或 CORP 响应头。修改 Rust 接口后运行 `flutter_rust_bridge_codegen generate` 并重建目标。

## 剧单协议

端点应直接返回 HTTP 200 及 UTF-8 JSON。以下为有效的空剧单。

```json
{"version":1,"dramas":[]}
```

| 字段 | 约束 |
| --- | --- |
| `dramas` | 最多 1,000 部，总响应最多 1 MiB |
| 剧目 `id`、`title` | `id` 在剧单内唯一，最多 96 字节。剧名最多 384 字节 |
| `tags` | 1 至 12 个不同的题材，每项最多 72 字节 |
| `cover` | 可省略，可取 `null` 或 HTTPS 封面地址 |
| `episodes` | 1 至 600 集，按播放顺序排列 |
| 单集 `id`、`title`、`url` | 剧内唯一 ID、集名、HTTPS 媒体直链。ID 与标题限制同剧目 |
| 单集 `ad_breaks` | 可省略。最多 64 组 `{"start_ms":1000,"end_ms":2000}`，毫秒半开区间，须按起点递增，区间之间留有间隔 |

文本需要含有可见内容。地址使用 ASCII，最长 4,096 字节。剧单地址用于区分历史记录，稳定的剧目及单集 ID 用于恢复进度。直链导入归入设备上的独立剧单。历史最多保留最近 512 个剧集条目，以带 `SW01` 版本标记的二进制帧保存。

要验证自己的剧单服务器，可以先发布下面的 JSON。视频来自 Flutter 文档，应用不会预置这条记录。

```json
{
  "version": 1,
  "dramas": [{
    "id": "flutter-butterfly",
    "title": "Flutter 蝴蝶示例",
    "tags": ["自然"],
    "episodes": [{
      "id": "clip",
      "title": "蝴蝶",
      "url": "https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4"
    }]
  }]
}
```

## 推荐依据

令每条有效剧集记录 $e$ 的观看毫秒数、片长和最近更新时间分别为 $w_e,d_e,t_e$。当前时间 $t$ 与 $t_e$ 使用 Unix 秒。播放进度用于续播，偏好依据累计观看时长；重复观看计入累计值，并以片长封顶。定义半衰期 $H=21\times86400$ 秒，单集证据量为

$$a_e=\frac{\min(w_e,d_e)}{d_e+60\,000}\,2^{-\max(0,t-t_e)/H}.$$

分母中的 60,000 毫秒用于抑制短片段带来的偏差。同一天看完 10 秒片段贡献 $1/7$，看了 4 分钟正片中的 2 分钟贡献 $2/5$。拖动进度条、缓冲和后台停留均不计入观看时长。

只计入 $w_e>0,d_e>0$ 的记录。令 $T_i$ 为当前剧单中作品 $i$ 的题材集合，$A_i=\sum_{e\in i}a_e$。题材 $g$ 的权重为 $b_g=1+\sum_{i:g\in T_i}A_i/|T_i|$。按以下得分为未看作品降序排列，同分沿用剧单顺序。

$$s_j=\frac{1}{|T_j|}\sum_{g\in T_j}b_g.$$

每部作品分给所有题材的总增量为 $|T_i|A_i/|T_i|=A_i$，因此多标签不会重复计算观看证据。若从候选作品的标签中等概率抽取一个标签，其权重的期望恰为 $s_j$。对任意非负递减位置权重 $q_k$，将两个逆序得分交换，目标 $\sum_k q_k s_{j_k}$ 的增量为 $(q_k-q_l)(s_{j_l}-s_{j_k})\ge0$（$k<l$）。逐次交换可得当前排序最大化此目标。这个结论依赖标签等权及所定义的效用，真实用户满意度仍需要数据检验。冷启动时所有得分为 1。21 天半衰期是产品参数。

## 极光引擎与播放

应用层的渲染策略集中在 `lib/design.dart`。页面路由统一使用 Material 前进淡入转场，标签页进入时使用同一组动效参数。系统要求减少动态效果时，自定义切页动效时长降为零。背景滤镜裁剪在胶囊范围内，播放时间线独立更新。场景合成和 GPU 调度由 Flutter 引擎负责。

界面采用 `material_ui` 的 Material 3 组件、Expressive 形状及按钮变体。系统动态配色来自 `dynamic_color`，Monet 从种子色生成色阶，AMOLED 模式使用黑色背景。胶囊支持实色、实时高斯模糊、液态折射和 Aero 渐变玻璃。折射使用支持 `ImageFilter.shader` 的后端，其余后端使用局部背景模糊。布局依可用宽度调整剧目列数与选集面板。

播放页持有一个 `media_kit` 实例，请求硬件加速，在进入后台时暂停，在关闭页面时释放资源。Android 会根据视频元数据请求同分辨率、刷新率与帧率成整数倍的最低兼容模式，暂停、缓冲或退出时释放请求。最终模式由系统决定。其他目标由浏览器或系统合成器负责呈现。功耗、温升和掉帧率需要在具体设备上测量。

| Rust 依赖 | 实际用途 |
| --- | --- |
| `courierust` 1.1.3 / `recurse-x` 0.2.6 | HTTPS URL 解析与 DNS 名称语法校验 |
| `nextjson` 0.1.5 | 剧单反序列化 |
| `rustbinary` 0.1.10 | 观看历史的紧凑二进制编解码 |
| `tzcraft` 0.1.2 | 推荐时间衰减的时间单位换算 |

## 验证

```sh
cargo test --locked --manifest-path rust/Cargo.toml
flutter analyze
flutter test test/interface_test.dart
flutter test integration_test/playback_test.dart -d windows
```

可用 `--dart-define=TEST_MEDIA_URL=<HTTPS视频地址>` 指定可播放至少数秒的替代测试素材。

| 目标 | 本次验证结果 |
| --- | --- |
| Windows x64 | Release 构建成功。集成测试播放了红果片段、《源起》和《梦笔不能停》第 1 集，后者播放时长为 550.882 秒。另验证了选集、拖动后的观看计时、落盘恢复与续播。Flutter 测试样片报告 `d3d11va-copy` 硬解，源帧率 29.970030 fps |
| Android 17 · PLK110 | Release APK 通过签名校验，包含 arm64-v8a、armeabi-v7a、x86_64 的 Flutter、Rust 和 libmpv 库。Debug 构建在真机上播放超过 1 秒并通过历史二进制往返测试。真机随后断开，扩展的落盘与解码器检测用例未在该机复测 |
| Web · Chrome | Release 应用在浏览器默认播放策略下播放了三个来源。《梦笔不能停》第 1 集显示 550.882 秒，退出后能从 30 秒处续播；《源起》第 1 集为 486.72 秒，红果《做兄弟，在心中》片段为 10.08 秒。另验证了自订剧单、刷新后恢复历史、四种胶囊设置和繁体中文。Web 使用 Dart 编译为 JavaScript，业务逻辑运行在 Rust Wasm 中 |
| iOS arm64、macOS arm64 | 两个目标均通过 Flutter Release 模式的 Dart Kernel 编译，分别生成了含 FRB 入口的 arm64 Mach-O Rust 静态库。完整应用的 Xcode 链接、签名和设备播放仍待验证 |
| Linux x64 | 通过 Flutter Release 模式的 Dart Kernel 编译。在 QEMU 的 Linux 6.8 内核中加载了 Rust 共享库，核对了 FRB 接口哈希，并运行通过全部六项 Rust 测试。GTK 桌面应用的构建和实际播放仍待验证 |

六项 Rust 测试和 Clippy 通过，`flutter analyze` 未报告问题。Flutter 组件测试验证了 360 和 1,280 逻辑像素宽度下的繁体中文导航及材质偏好读写。屏幕实际切换到的刷新率、温升、功耗与六端视觉一致性仍待设备测量。
