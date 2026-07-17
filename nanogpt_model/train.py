"""
train.py — NanoGPT training script.

Run with:
    python train.py

What this script does:
  1. Downloads the TinyShakespeare dataset (or creates a synthetic fallback).
  2. Builds train / val DataLoaders.
  3. Instantiates NanoGPT and an AdamW optimizer.
  4. Runs the training loop for config.max_steps steps.
  5. Evaluates on validation set every config.eval_interval steps.
  6. Saves the best checkpoint to checkpoints/best_model.pt.
  7. Prints a sample generation every eval_interval steps.
  8. Reports final stats (params, loss, training time) at the end.
"""

import os
import sys
import time
import requests

import torch
torch.set_float32_matmul_precision('high')

from config import Config
from tokenizer import Tokenizer
from dataset import get_dataloader, get_batch
from model import NanoGPT
from utils import set_seed, estimate_loss, save_checkpoint, get_lr


# ─────────────────────────────────────────────────────────────────────────────
# Dataset download
# ─────────────────────────────────────────────────────────────────────────────

TINYSHAKESPEARE_URL = (
    "https://raw.githubusercontent.com/karpathy/char-rnn"
    "/master/data/tinyshakespeare/input.txt"
)

SYNTHETIC_TEXT = """
To be, or not to be, that is the question:
Whether 'tis nobler in the mind to suffer
The slings and arrows of outrageous fortune,
Or to take arms against a sea of troubles
And by opposing end them. To die—to sleep,
No more; and by a sleep to say we end
The heart-ache and the thousand natural shocks
That flesh is heir to: 'tis a consummation
Devoutly to be wish'd. To die, to sleep;
To sleep, perchance to dream—ay, there's the rub,
For in that sleep of death what dreams may come
When we have shuffled off this mortal coil
Must give us pause. There's the respect
That makes calamity of so long life.
""" * 500   # repeat to get ~50k tokens for a minimal test run


def load_dataset(cache_path: str = "data/tinyshakespeare.txt") -> str:
    """
    Load TinyShakespeare text.

    Tries (in order):
      1. Local cache at `cache_path`.
      2. Download from GitHub.
      3. Synthetic fallback (for offline / CI environments).

    Args:
        cache_path: where to cache the downloaded file

    Returns:
        Raw text as a string.
    """
    # 1. Check cache.
    if os.path.exists(cache_path):
        print(f"Loading dataset from cache: {cache_path}")
        with open(cache_path, "r", encoding="utf-8") as f:
            return f.read()

    # 2. Try to download.
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)
    print(f"Downloading TinyShakespeare from {TINYSHAKESPEARE_URL} …")
    try:
        response = requests.get(TINYSHAKESPEARE_URL, timeout=15)
        response.raise_for_status()
        text = response.text
        with open(cache_path, "w", encoding="utf-8") as f:
            f.write(text)
        print(f"  Saved to {cache_path} ({len(text):,} characters)")
        return text
    except Exception as e:
        print(f"  Download failed: {e}")
        print("  Using synthetic dataset for testing (short run only).")
        return SYNTHETIC_TEXT


# ─────────────────────────────────────────────────────────────────────────────
# Sample generation helper
# ─────────────────────────────────────────────────────────────────────────────

def sample_text(
    model: NanoGPT,
    tokenizer: Tokenizer,
    prompt: str,
    max_new_tokens: int = 150,
    temperature: float = 0.8,
    top_k: int = 40,
    device: str = "cpu",
) -> str:
    """
    Generate a short text sample from a prompt string.

    Encodes the prompt, runs model.generate(), and decodes the result.
    Used at eval checkpoints to qualitatively judge training progress.
    """
    model.eval()
    ids = tokenizer.encode(prompt)
    # Clamp to max_seq_len so we don't overflow positional embeddings.
    ids = ids[-model.config.max_seq_len:]
    idx = torch.tensor([ids], dtype=torch.long, device=device)   # (1, T)

    with torch.no_grad():
        out = model.generate(idx, max_new_tokens, temperature=temperature, top_k=top_k)

    generated_ids = out[0].tolist()
    return tokenizer.decode(generated_ids)


# ─────────────────────────────────────────────────────────────────────────────
# Main training loop
# ─────────────────────────────────────────────────────────────────────────────

def train():
    # ── Setup ─────────────────────────────────────────────────────────────────
    config = Config()
    set_seed(42)

    print("=" * 60)
    print("NanoGPT Training")
    print("=" * 60)
    print(config)
    print()

    # ── Data ──────────────────────────────────────────────────────────────────
    text = load_dataset()
    tokenizer = Tokenizer()

    train_loader, val_loader = get_dataloader(
        text,
        tokenizer,
        max_seq_len=config.max_seq_len,
        batch_size=config.batch_size,
    )

    # Also keep the full token tensor for fast random batch sampling during training.
    # This avoids DataLoader overhead in the hot loop.
    all_tokens = torch.tensor(tokenizer.encode(text), dtype=torch.long)
    n_train_tokens = int(len(all_tokens) * 0.9)
    train_tokens = all_tokens[:n_train_tokens]
    val_tokens   = all_tokens[n_train_tokens:]

    # ── Model ─────────────────────────────────────────────────────────────────
    model = NanoGPT(config).to(config.device)
    optimizer = model.configure_optimizers(
        learning_rate=config.learning_rate,
        weight_decay=0.1,
    )

    print(f"\nTraining on: {config.device}")
    print(f"Total parameters: {model.count_parameters()}")
    print()

    # ── Training loop ─────────────────────────────────────────────────────────
    best_val_loss = float("inf")
    train_start   = time.time()
    last_train_loss = float("nan")

    model.train()

    for step in range(config.max_steps):

        # ── Learning rate schedule ───────────────────────────────────────────
        # Manually update the LR at each step (PyTorch schedulers can also do
        # this, but the manual approach is clearer for educational purposes).
        lr = get_lr(step, config)
        for param_group in optimizer.param_groups:
            param_group["lr"] = lr

        # ── Get a training batch ──────────────────────────────────────────────
        # We use the fast random-sampling approach rather than DataLoader
        # iteration for the training hot loop.
        x, y = get_batch(train_tokens, config.max_seq_len, config.batch_size, config.device)

        # ── Forward pass ──────────────────────────────────────────────────────
        with torch.autocast(device_type=config.device, dtype=torch.bfloat16):
            logits, loss = model(x, y)

        # ── Backward pass ────────────────────────────────────────────────────
        optimizer.zero_grad(set_to_none=True)   # clear old gradients
        loss.backward()                          # compute new gradients

        # Gradient clipping: if the gradient norm exceeds grad_clip, rescale
        # all gradients so the total norm equals grad_clip.  Prevents
        # catastrophic gradient explosions.
        if config.grad_clip > 0.0:
            torch.nn.utils.clip_grad_norm_(model.parameters(), config.grad_clip)

        optimizer.step()

        last_train_loss = loss.item()

        # ── Logging every 100 steps ──────────────────────────────────────────
        if step % 100 == 0:
            elapsed = time.time() - train_start
            steps_per_sec = (step + 1) / elapsed if elapsed > 0 else 0
            eta_sec = (config.max_steps - step) / steps_per_sec if steps_per_sec > 0 else 0
            eta_min = eta_sec / 60

            print(
                f"step {step:5d}/{config.max_steps} | "
                f"loss {last_train_loss:.4f} | "
                f"lr {lr:.2e} | "
                f"{steps_per_sec:.1f} step/s | "
                f"ETA {eta_min:.1f} min"
            )

        # ── Evaluation + checkpoint every eval_interval steps ────────────────
        if (step + 1) % config.eval_interval == 0 or step == config.max_steps - 1:
            print("\n" + "─" * 50)
            print(f"Evaluation at step {step + 1}")

            # Estimate validation loss.
            val_loss = estimate_loss(model, val_loader, config.eval_steps, config.device)
            model.train()   # switch back to train mode after estimate_loss

            print(f"  train loss : {last_train_loss:.4f}")
            print(f"  val loss   : {val_loss:.4f}")

            # Save best checkpoint.
            checkpoint_path = "checkpoints/best_model_bf16.pt"
            if val_loss < best_val_loss:
                best_val_loss = val_loss
                save_checkpoint(
                    model, optimizer, step + 1, val_loss,
                    path=checkpoint_path,
                )

            # Generate a sample to qualitatively check training progress.
            print("\n  Sample generation:")
            print("  " + "·" * 40)
            sample = sample_text(
                model, tokenizer,
                prompt="HAMLET:\n",
                max_new_tokens=150,
                device=config.device,
            )
            # Indent sample output for readability.
            for line in sample.split("\n")[:10]:
                print(f"  {line}")
            print("  " + "·" * 40 + "\n")

            model.train()

    # ── Final stats ───────────────────────────────────────────────────────────
    total_time = time.time() - train_start
    print("\n" + "=" * 60)
    print("Training complete!")
    print(f"  Total parameters  : {model.count_parameters()}")
    print(f"  Final train loss  : {last_train_loss:.4f}")
    print(f"  Best val loss     : {best_val_loss:.4f}")
    print(f"  Total time        : {total_time / 60:.1f} minutes")
    print(f"  Checkpoint saved  : {checkpoint_path}")
    print("=" * 60)


# ─────────────────────────────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    train()