#!/usr/bin/env python3
import argparse
import json
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Transcribe a local video/audio file with Qwen3-ASR.")
    parser.add_argument("media", help="Path to a local video or audio file.")
    parser.add_argument("--model-dir", default="models/Qwen3-ASR-1.7B", help="Local Qwen3-ASR model directory.")
    parser.add_argument("--audio-dir", default="audio", help="Directory for extracted WAV files.")
    parser.add_argument("--output-dir", default="transcripts", help="Directory for transcript outputs.")
    parser.add_argument("--language", default=None, help='Optional language hint, for example "Chinese" or "English".')
    parser.add_argument("--device", choices=["auto", "cuda", "cpu"], default="auto", help="Inference device.")
    parser.add_argument("--max-new-tokens", type=int, default=1024, help="Maximum generated tokens.")
    parser.add_argument("--keep-audio", action="store_true", help="Keep extracted WAV file. WAV is kept by default if extraction succeeds.")
    parser.add_argument("--force-audio", action="store_true", help="Re-extract WAV even if it already exists.")
    return parser.parse_args()


def safe_stem(path: Path) -> str:
    return "".join(ch if ch.isalnum() or ch in "._- " else "_" for ch in path.stem).strip() or "media"


def get_ffmpeg_exe() -> str:
    try:
        import imageio_ffmpeg
    except ImportError as exc:
        raise RuntimeError("Missing imageio-ffmpeg. Run ./transcribe-video.sh once to install ASR dependencies.") from exc
    return imageio_ffmpeg.get_ffmpeg_exe()


def extract_audio(media_path: Path, wav_path: Path, force: bool) -> None:
    if wav_path.exists() and not force:
        return

    wav_path.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        get_ffmpeg_exe(),
        "-y",
        "-i",
        str(media_path),
        "-vn",
        "-ac",
        "1",
        "-ar",
        "16000",
        "-f",
        "wav",
        str(wav_path),
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg failed extracting audio from {media_path}:\n{result.stderr[-4000:]}")


def choose_device(device: str):
    import torch

    if device == "cpu":
        return "cpu", torch.float32
    if device == "cuda":
        if not torch.cuda.is_available():
            raise RuntimeError("CUDA requested, but torch.cuda.is_available() is false.")
        return "cuda:0", torch.bfloat16
    if torch.cuda.is_available():
        return "cuda:0", torch.bfloat16
    return "cpu", torch.float32


def write_outputs(output_base: Path, result, source_media: Path, wav_path: Path, model_dir: Path) -> None:
    output_base.parent.mkdir(parents=True, exist_ok=True)

    text = getattr(result, "text", "") or ""
    language = getattr(result, "language", "") or ""
    time_stamps = getattr(result, "time_stamps", None)

    txt_path = output_base.with_suffix(".txt")
    json_path = output_base.with_suffix(".json")

    txt_path.write_text(text.strip() + "\n", encoding="utf-8")

    payload = {
        "source_media": str(source_media),
        "audio": str(wav_path),
        "model_dir": str(model_dir),
        "language": language,
        "text": text,
        "time_stamps": [
            {
                "text": getattr(item, "text", ""),
                "start_time": getattr(item, "start_time", None),
                "end_time": getattr(item, "end_time", None),
            }
            for item in (time_stamps or [])
        ],
    }
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    print(f"Transcript: {txt_path}")
    print(f"Metadata: {json_path}")


def main() -> int:
    args = parse_args()
    media_path = Path(args.media).expanduser().resolve()
    model_dir = Path(args.model_dir).expanduser().resolve()

    if not media_path.exists():
        print(f"Media file does not exist: {media_path}", file=sys.stderr)
        return 1
    if not model_dir.exists():
        print(f"Model directory does not exist: {model_dir}", file=sys.stderr)
        return 1

    audio_dir = Path(args.audio_dir).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()
    stem = safe_stem(media_path)
    wav_path = audio_dir / f"{stem}.wav"
    output_base = output_dir / stem

    print(f"Extracting audio: {wav_path}")
    extract_audio(media_path, wav_path, force=args.force_audio)

    import torch
    from qwen_asr import Qwen3ASRModel

    device_map, dtype = choose_device(args.device)
    print(f"Loading model: {model_dir}")
    print(f"Device: {device_map}, dtype: {dtype}")

    model = Qwen3ASRModel.from_pretrained(
        str(model_dir),
        dtype=dtype,
        device_map=device_map,
        max_inference_batch_size=1,
        max_new_tokens=args.max_new_tokens,
    )

    print("Transcribing...")
    results = model.transcribe(
        audio=str(wav_path),
        language=args.language,
        return_time_stamps=False,
    )
    if not results:
        raise RuntimeError("Qwen3-ASR returned no transcription result.")

    write_outputs(output_base, results[0], media_path, wav_path, model_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
