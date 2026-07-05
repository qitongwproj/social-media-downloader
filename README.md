# Social Media Downloader

一个本地命令行视频下载和转文字工具。常用入口：

```bash
./video-to-text.sh "视频链接"
./video-to-text.sh --batch urls.txt
./download-video.sh "视频链接"
./transcribe-video.sh "本地视频文件"
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

## 链接直接转文字

单个链接下载并转成 Markdown：

```bash
./video-to-text.sh --language Chinese "完整视频分享链接"
```

批量处理：

```bash
./video-to-text.sh --batch urls.txt --language Chinese
```

批量时跳过失败链接并继续：

```bash
./video-to-text.sh --batch urls.txt --language Chinese --continue-on-error
```

输出：

```text
downloads/<平台>/<视频标题>.<扩展名>
transcripts/<视频标题>.md
```

默认不会保留中间音频文件。需要保留 WAV 时加：

```bash
./video-to-text.sh --keep-audio --language Chinese "完整视频分享链接"
```

## 说明

- 第一次运行会自动创建项目本地 `.venv/`，并安装 `yt-dlp`。
- 默认下载最佳可用视频；如果系统没有 `ffmpeg`，会优先选择单文件 MP4，避免合并失败。
- 下载文件默认保存到 `downloads/<平台>/<视频标题>.<扩展名>`，不额外拼接视频 ID。
- 支持平台取决于 `yt-dlp`，例如小红书、YouTube、TikTok、Bilibili 等。

## 更新下载器

```bash
./download-video.sh --update "视频链接"
```

## ASR 模型

默认转写模型使用：

```text
Qwen/Qwen3-ASR-1.7B-hf
```

使用前需要先将模型权重下载到本地，默认路径是：

```text
D:\models\Qwen3-ASR-1.7B-hf
```

模型目录在仓库之外，不会提交到仓库。

模型路径统一在 [`config.sh`](config.sh) 的 `DEFAULT_MODEL_DIR` 变量中维护，
所有 shell 脚本和 Python 转写脚本都从这里读取。需要更换模型位置时只改这一处。

下载命令示例：

```bash
.venv/bin/hf download Qwen/Qwen3-ASR-1.7B-hf --local-dir "D:\models\Qwen3-ASR-1.7B-hf"
```

`Qwen3-ASR-1.7B-hf` 使用原生 Transformers 接口加载，需要 `transformers==5.13.0`。
`transcribe-video.sh --setup-only` 会安装转写所需依赖。

## 视频转文字

已验证的完整流程：

```bash
./transcribe-video.sh --setup-only
./video-to-text.sh --language Chinese "完整视频分享链接"
```

流程会先用 `yt-dlp` 下载视频，再提取 16 kHz mono WAV 音频，最后使用
`D:\models\Qwen3-ASR-1.7B-hf` 生成 Markdown 转写稿。

转写本地视频或音频文件：

```bash
./transcribe-video.sh "downloads/XiaoHongShu/example.mp4"
```

指定语言可以提升稳定性：

```bash
./transcribe-video.sh --language Chinese "downloads/XiaoHongShu/example.mp4"
```

一键下载并转写：

```bash
./download-and-transcribe.sh "完整视频分享链接"
```

指定下载目录和转写输出目录：

```bash
./download-and-transcribe.sh --download-dir ./downloads --transcript-dir ./transcripts "完整视频分享链接"
```

第一次运行转写会创建独立环境 `.venv-asr/` 并安装 ASR 依赖：

```bash
./transcribe-video.sh --setup-only
```

默认安装 CUDA 12.4 版 PyTorch。需要换 PyTorch 源时可以设置：

```bash
TORCH_INDEX_URL=https://download.pytorch.org/whl/cu121 ./transcribe-video.sh --setup-only
```

转写输出：

```text
transcripts/<视频文件名>.md
```

## 视频转文字实现说明

1. ASR 环境
   - 转写使用独立环境 `.venv-asr/`，避免和下载脚本的 `.venv/` 混在一起。
   - 安装 PyTorch、`imageio-ffmpeg`、`qwen-asr` 和 `transformers==5.13.0`。
   - 对 `Qwen3-ASR-1.7B-hf`，Python 脚本会走原生 Transformers `AutoModelForMultimodalLM` / `AutoProcessor`。
   - 默认加载本地模型目录 `D:\models\Qwen3-ASR-1.7B-hf`，避免运行时重新下载。

2. 音频提取
   - 脚本通过 `imageio-ffmpeg` 提供的 ffmpeg 二进制提取音频。
   - 默认使用临时 16 kHz mono WAV，转写完成后删除。
   - 如果输入本身是 `.wav`、`.mp3`、`.m4a` 等音频文件，会直接转写，不再重复提取。
   - 需要保留音频时传 `--keep-audio`，输出到 `audio/<视频文件名>.wav`。

3. 调用 Qwen3-ASR 转写
   - 默认模型使用 `Qwen/Qwen3-ASR-1.7B-hf`，优先保证转写质量。
   - `--device auto` 会优先使用 CUDA；没有 GPU 时使用 CPU。
   - 默认使用 `--max-new-tokens 4096` 和 `--max-chunk-sec 60`，降低长视频被截断或显存不足的概率。
   - 可以用 `--language Chinese`、`--language English` 等指定语言。

4. 保存转写结果
   - Markdown：`transcripts/<视频文件名>.md`
