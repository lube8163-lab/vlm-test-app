#!/usr/bin/env python3
"""
Experimental CoreML conversion probe for transformer-based VLMs.

This script is intentionally conservative:
- It tries to load a model with Transformers.
- It runs a minimal forward pass.
- It attempts TorchScript tracing and CoreML conversion.

Goal: quickly identify unsupported ops / shape issues for Phase 2.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def fail(msg: str, code: int = 1) -> None:
    print(f"[ERROR] {msg}")
    raise SystemExit(code)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", required=True, help="Local model directory")
    parser.add_argument("--out", required=True, help="Output .mlpackage path")
    parser.add_argument("--max-tokens", type=int, default=16)
    args = parser.parse_args()

    model_dir = Path(args.model_dir)
    out_path = Path(args.out)

    if not model_dir.exists():
        fail(f"model-dir does not exist: {model_dir}")

    try:
        import torch
        import coremltools as ct
        from transformers import AutoTokenizer, AutoModelForCausalLM
    except Exception as exc:
        fail(f"missing dependency: {exc}")

    print("[1/4] Loading tokenizer/model...")
    try:
        tok = AutoTokenizer.from_pretrained(model_dir, trust_remote_code=True)
        model = AutoModelForCausalLM.from_pretrained(
            model_dir,
            trust_remote_code=True,
            torch_dtype=torch.float16,
            low_cpu_mem_usage=True,
        )
        model.eval()
    except Exception as exc:
        fail(f"failed to load model from {model_dir}: {exc}")

    prompt = "Describe the image briefly."
    print("[2/4] Building dummy text inputs...")
    try:
        inputs = tok(prompt, return_tensors="pt")
        input_ids = inputs["input_ids"][:, : args.max_tokens]
        attention_mask = inputs["attention_mask"][:, : args.max_tokens]
    except Exception as exc:
        fail(f"tokenizer failed: {exc}")

    class Wrapper(torch.nn.Module):
        def __init__(self, base_model):
            super().__init__()
            self.base_model = base_model

        def forward(self, input_ids, attention_mask):
            out = self.base_model(input_ids=input_ids, attention_mask=attention_mask)
            return out.logits

    wrapped = Wrapper(model)

    print("[3/4] Tracing TorchScript...")
    try:
        with torch.no_grad():
            traced = torch.jit.trace(wrapped, (input_ids, attention_mask), strict=False)
    except Exception as exc:
        fail(f"torch.jit.trace failed (often custom op / dynamic shape issue): {exc}")

    print("[4/4] Converting to CoreML...")
    try:
        mlmodel = ct.convert(
            traced,
            inputs=[
                ct.TensorType(name="input_ids", shape=input_ids.shape, dtype=input_ids.numpy().dtype),
                ct.TensorType(
                    name="attention_mask",
                    shape=attention_mask.shape,
                    dtype=attention_mask.numpy().dtype,
                ),
            ],
            convert_to="mlprogram",
        )
        out_path.parent.mkdir(parents=True, exist_ok=True)
        mlmodel.save(str(out_path))
    except Exception as exc:
        fail(f"coreml conversion failed: {exc}")

    print(f"[OK] Saved: {out_path}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
