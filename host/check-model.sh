#!/usr/bin/env bash
set -u
MODEL="${OLLAMA_MODEL:-hf.co/HauhauCS/Gemma4-12B-QAT-Uncensored-HauhauCS-Balanced:Q4_K_M}"
if ! command -v ollama >/dev/null 2>&1; then
  echo "Ollama CLI not found on this host. Start/fix Ollama before using the VM harness." >&2
  exit 1
fi
echo "Model: $MODEL"
if ! ollama show "$MODEL"; then
  echo "Ollama could not find this exact model tag. Check 'ollama list' and adjust OLLAMA_MODEL in the guest service environment." >&2
  exit 1
fi
INFO="$(ollama show "$MODEL" 2>&1 || true)"
if ! grep -qi 'tools' <<<"$INFO"; then
  echo "WARNING: Ollama output does not advertise tool capability. Tool calling must be smoke-tested before unattended work."
fi
if ! grep -qi 'vision' <<<"$INFO"; then
  echo "WARNING: Ollama output does not advertise vision. The Gemma4 QAT model card documents a separate mmproj; verify image input using the dashboard health endpoint and a screenshot task."
fi
