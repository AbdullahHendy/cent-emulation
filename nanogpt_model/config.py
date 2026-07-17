"""
config.py — Hyperparameter configuration for NanoGPT.

All model and training settings live here so every other file can import
a single Config object instead of scattering magic numbers throughout the code.
"""

from dataclasses import dataclass, field
import torch


@dataclass
class Config:
    # ── Vocabulary ──────────────────────────────────────────────────────────
    # GPT-2 uses Byte-Pair Encoding with exactly 50257 tokens.
    vocab_size: int = 50257

    # ── Model architecture ───────────────────────────────────────────────────
    # embed_dim  : width of every embedding vector (d_model in the paper)
    # num_heads  : how many parallel attention heads per transformer block
    # num_layers : number of stacked transformer blocks (depth of the network)
    # max_seq_len: maximum number of tokens the model can attend to at once
    # dropout    : probability of zeroing an activation during training
    embed_dim:   int   = 128
    num_heads:   int   = 4
    num_layers:  int   = 4
    max_seq_len: int   = 256
    dropout:     float = 0.1

    # ── Training ─────────────────────────────────────────────────────────────
    # batch_size    : sequences processed in one forward/backward pass
    # learning_rate : peak learning rate for AdamW (after warmup)
    # max_steps     : total number of gradient update steps
    # eval_interval : run validation every N steps
    # eval_steps    : number of val batches to average for each eval
    # grad_clip     : max L2 norm for gradient clipping (prevents explosions)
    # warmup_steps  : linearly ramp LR from 0 → learning_rate over this many steps
    batch_size:     int   = 32
    learning_rate:  float = 3e-4
    max_steps:      int   = 30000
    eval_interval:  int   = 5000
    eval_steps:     int   = 50
    grad_clip:      float = 1.0
    warmup_steps:   int   = 100

    # ── Device ───────────────────────────────────────────────────────────────
    # Auto-detect the best available hardware:
    #   CUDA  → NVIDIA GPU  (fastest)
    #   MPS   → Apple Silicon GPU (fast on M-series Macs)
    #   CPU   → fallback    (always available)
    device: str = field(default_factory=lambda: (
        "cuda" if torch.cuda.is_available()
        else "mps" if torch.backends.mps.is_available()
        else "cpu"
    ))

    def __post_init__(self):
        # Sanity-check: embed_dim must be divisible by num_heads so we can
        # split the embedding evenly across attention heads.
        assert self.embed_dim % self.num_heads == 0, (
            f"embed_dim ({self.embed_dim}) must be divisible by "
            f"num_heads ({self.num_heads})"
        )

    def __repr__(self):
        lines = ["Config("]
        for k, v in self.__dict__.items():
            lines.append(f"  {k} = {v!r}")
        lines.append(")")
        return "\n".join(lines)