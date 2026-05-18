# Social Media Downloader

一个本地命令行视频下载工具。核心入口只有一个：

```bash
./download-video.sh "视频链接"
```

## 使用

下载视频到默认目录 `downloads/`：

```bash
./download-video.sh "完整视频分享链接"
```

小红书这类平台建议直接粘贴完整分享 URL，保留 `xsec_token` 等参数。

指定输出目录：

```bash
./download-video.sh -o ./my-downloads "视频链接"
```

只查看视频信息，不下载：

```bash
./download-video.sh --info "视频链接"
```

如果页面需要登录态，可以读取浏览器 cookies：

```bash
./download-video.sh --cookies-from-browser chrome "视频链接"
```

只下载音频：

```bash
./download-video.sh --audio-only "视频链接"
```

## 批量下载

先复制模板：

```bash
cp urls.example.txt urls.txt
```

然后编辑 `urls.txt`，一行放一个完整视频链接。批量下载：

```bash
while IFS= read -r url; do
  [[ -z "$url" || "$url" =~ ^# ]] && continue
  ./download-video.sh "$url"
done < urls.txt
```

## 说明

- 第一次运行会自动创建项目本地 `.venv/`，并安装 `yt-dlp`。
- 默认下载最佳可用视频；如果系统没有 `ffmpeg`，会优先选择单文件 MP4，避免合并失败。
- 下载文件默认保存到 `downloads/<平台>/`。
- 支持平台取决于 `yt-dlp`，例如小红书、YouTube、TikTok、Bilibili 等。

## 更新下载器

```bash
./download-video.sh --update "视频链接"
```

## Qwen3-ASR Submodule

本项目已把 Qwen3-ASR 作为 submodule 放在：

```text
third_party/Qwen3-ASR
```

新环境拉取代码后初始化：

```bash
git submodule update --init --recursive repo/social-media-downloader/third_party/Qwen3-ASR
```

如果当前目录就是本项目目录，也可以运行：

```bash
git -C /home/qitong submodule update --init --recursive repo/social-media-downloader/third_party/Qwen3-ASR
```

## ASR Model Weights

默认转写模型使用：

```text
Qwen/Qwen3-ASR-1.7B
```

权重已下载到本地：

```text
models/Qwen3-ASR-1.7B
```

本地权重目录大小约 `4.4G`，主要文件是：

```text
model-00001-of-00002.safetensors
model-00002-of-00002.safetensors
```

模型目录已加入 `.gitignore`，不会提交到仓库。

如果需要重新下载：

```bash
.venv/bin/hf download Qwen/Qwen3-ASR-1.7B --local-dir models/Qwen3-ASR-1.7B
```

## 视频转文字计划

1. 准备独立 ASR 环境
   - Qwen3-ASR 官方建议 Python 3.12。
   - 新建单独环境，例如 `.venv-asr/`，避免和当前下载脚本的 `.venv/` 混在一起。
   - 安装 `third_party/Qwen3-ASR` 或官方 `qwen-asr` 包。
   - 默认加载本地模型目录 `models/Qwen3-ASR-1.7B`，避免每次运行时重新下载。

2. 从视频提取音频
   - 依赖 `ffmpeg`。
   - 将 `downloads/<平台>/*.mp4` 转为 `audio/<同名>.wav`。
   - 建议统一为 16 kHz mono WAV，方便 ASR 处理。

3. 调用 Qwen3-ASR 转写
   - 默认模型使用 `Qwen/Qwen3-ASR-1.7B`，优先保证转写质量。
   - GPU 可用时走 CUDA；没有 GPU 时允许 CPU fallback，但会明显变慢。
   - 语言默认自动检测，也可以后续加参数指定 `Chinese`、`English` 等。

4. 保存转写结果
   - 输出目录：`transcripts/`
   - 文本文件：`transcripts/<视频文件名>.txt`
   - 后续可扩展保存 JSON，包括语言、时长、时间戳等元信息。

5. 串联下载和转写
   - 保留当前入口 `./download-video.sh` 不变。
   - 后续新增 `./transcribe-video.sh <video-file>`。
   - 后续新增 `./download-and-transcribe.sh "视频链接"`，执行下载后自动转写最新下载文件。
