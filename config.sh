#!/usr/bin/env bash
# Central configuration for the social-media-downloader project.
# Sourced by all shell scripts so model paths only need to be changed here.

# Default local Qwen3-ASR model directory.
# Override at runtime by setting DEFAULT_MODEL_DIR in the environment.
export DEFAULT_MODEL_DIR="${DEFAULT_MODEL_DIR:-D:\models\Qwen3-ASR-1.7B-hf}"
