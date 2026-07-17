"""
generate.py — Standalone text generation script for NanoGPT.

Usage:
    python generate.py
    python generate.py --prompt "To be or not to be"
    python generate.py --prompt "HAMLET:" --max_tokens 300 --temperature 0.7 --top_k 50

This script:
  1. Loads the model architecture from config.py.
  2. Restores weights from a saved checkpoint.
  3. Encodes a text prompt with the GPT-2 tokenizer.
  4. Runs auto-regressive sampling.
  5. Decodes and prints the generated text.
"""

import argparse
import os
import sys
import torch
torch.set_float32_matmul_precision('high')

from config import Config
from tokenizer import Tokenizer
from model import NanoGPT
from utils import load_checkpoint


# ─────────────────────────────────────────────────────────────────────────────
# Command-line argument parsing
# ─────────────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate text with a trained NanoGPT model.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )

    parser.add_argument(
        "--prompt",
        type=str,
        default="Once upon a time",
        help="Text prompt to seed the generation.",
    )
    parser.add_argument(
        "--max_tokens",
        type=int,
        default=200,
        help="Number of new tokens to generate.",
    )
    parser.add_argument(
        "--temperature",
        type=float,
        default=0.8,
        help=(
            "Sampling temperature. "
            "< 1.0 → more focused / repetitive. "
            "> 1.0 → more random / creative."
        ),
    )
    parser.add_argument(
        "--top_k",
        type=int,
        default=40,
        help=(
            "Top-k sampling: only sample from the k most likely tokens. "
            "Set to 0 to disable (pure temperature sampling)."
        ),
    )
    parser.add_argument(
        "--checkpoint",
        type=str,
        default="checkpoints/best_model_bf16.pt",
        help="Path to the model checkpoint (.pt file).",
    )
    parser.add_argument(
        "--device",
        type=str,
        default=None,
        help="Device override (cuda / mps / cpu).  Defaults to auto-detect.",
    )

    return parser.parse_args()


# ─────────────────────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────────────────────

def main():
    args = parse_args()

    # ── Config & device ───────────────────────────────────────────────────────
    config = Config()
    device = args.device if args.device else config.device
    print(f"Device: {device}")

    # ── Load checkpoint ───────────────────────────────────────────────────────
    if not os.path.exists(args.checkpoint):
        print(f"ERROR: Checkpoint not found at '{args.checkpoint}'")
        print("  Run 'python train.py' first to train the model.")
        sys.exit(1)

    # Load the checkpoint to check if it contains a config.
    torch.serialization.add_safe_globals([Config])
    raw = torch.load(args.checkpoint, map_location="cpu")
    if "config" in raw:
        # Use the saved config so the model architecture matches the checkpoint.
        config = raw["config"]
        print(f"  Using config from checkpoint.")
    else:
        print("  Using default Config (checkpoint has no embedded config).")

    # ── Build model ───────────────────────────────────────────────────────────
    model = NanoGPT(config).to(device)
    step, loss = load_checkpoint(args.checkpoint, model)
    model.eval()

    print(f"  Loaded model: {model.count_parameters()} params | "
          f"trained for {step} steps | checkpoint loss {loss:.4f}")

    # ── Tokenizer ─────────────────────────────────────────────────────────────
    tokenizer = Tokenizer()

    # ── Encode prompt ─────────────────────────────────────────────────────────
    prompt_ids = tokenizer.encode(args.prompt)

    # If the prompt is longer than max_seq_len, truncate from the left
    # (keep the most recent tokens — the model's "working memory").
    if len(prompt_ids) > config.max_seq_len:
        print(f"  Prompt too long ({len(prompt_ids)} tokens); truncating to {config.max_seq_len}.")
        prompt_ids = prompt_ids[-config.max_seq_len:]

    idx = torch.tensor([prompt_ids], dtype=torch.long, device=device)  # (1, T)

    # ── Generate ──────────────────────────────────────────────────────────────
    top_k = args.top_k if args.top_k > 0 else None   # 0 → disable top-k

    print(f"\nGenerating {args.max_tokens} tokens  "
          f"(temperature={args.temperature}, top_k={top_k}) …\n")
    print("─" * 60)

    with torch.no_grad():
        out = model.generate(
            idx,
            max_new_tokens=args.max_tokens,
            temperature=args.temperature,
            top_k=top_k,
        )

    # ── Decode and print ──────────────────────────────────────────────────────
    generated_ids = out[0].tolist()
    full_text = tokenizer.decode(generated_ids)

    print(full_text)
    print("\n" + "─" * 60)
    print(f"Prompt tokens: {len(prompt_ids)} | Generated tokens: {args.max_tokens} | "
          f"Total: {len(generated_ids)}")


if __name__ == "__main__":
    main()