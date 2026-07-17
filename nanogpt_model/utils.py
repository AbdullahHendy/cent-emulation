"""
utils.py — Training helpers for NanoGPT.

Contains standalone utility functions used by train.py and generate.py:
  - set_seed          : reproducibility
  - count_parameters  : formatted parameter count
  - estimate_loss     : validation loop
  - save_checkpoint   : persist model state
  - load_checkpoint   : restore model state
  - get_lr            : cosine schedule with linear warmup
"""

import os
import math
import random
import numpy as np
import torch
from torch.utils.data import DataLoader
from config import Config


# ─────────────────────────────────────────────────────────────────────────────
# Reproducibility
# ─────────────────────────────────────────────────────────────────────────────

def set_seed(seed: int = 42) -> None:
    """
    Set all random seeds to `seed` for reproducible runs.

    Covers Python's random module, NumPy, and PyTorch (CPU + GPU).
    Note: full determinism on GPU also requires setting
    CUBLAS_WORKSPACE_CONFIG, which we skip here for simplicity.
    """
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)


# ─────────────────────────────────────────────────────────────────────────────
# Parameter counting
# ─────────────────────────────────────────────────────────────────────────────

def count_parameters(model: torch.nn.Module) -> str:
    """
    Return a formatted string of the number of trainable parameters.

    Examples:
        "10.2M"   for 10_200_000 parameters
        "512.0K"  for    512_000 parameters
        "1234"    for      1_234 parameters
    """
    n = sum(p.numel() for p in model.parameters() if p.requires_grad)
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    elif n >= 1_000:
        return f"{n / 1_000:.1f}K"
    return str(n)


# ─────────────────────────────────────────────────────────────────────────────
# Validation loss estimation
# ─────────────────────────────────────────────────────────────────────────────

@torch.no_grad()
def estimate_loss(
    model: torch.nn.Module,
    dataloader: DataLoader,
    eval_steps: int,
    device: str,
) -> float:
    """
    Estimate the mean cross-entropy loss over `eval_steps` batches.

    We switch the model to eval mode (disables dropout) and average the loss
    over multiple batches to reduce variance in the estimate.

    Args:
        model      : NanoGPT instance
        dataloader : validation DataLoader
        eval_steps : number of batches to average over
        device     : target device string

    Returns:
        mean loss as a Python float
    """
    model.eval()

    losses = []
    loader_iter = iter(dataloader)

    for _ in range(min(eval_steps, len(dataloader))):
        try:
            x, y = next(loader_iter)
        except StopIteration:
            # If the dataloader is exhausted before eval_steps, restart it.
            loader_iter = iter(dataloader)
            x, y = next(loader_iter)

        x, y = x.to(device), y.to(device)
        with torch.autocast(device_type=device, dtype=torch.bfloat16):
            _, loss = model(x, y)
        losses.append(loss.item())

    model.train()

    return float(np.mean(losses))


# ─────────────────────────────────────────────────────────────────────────────
# Checkpoint management
# ─────────────────────────────────────────────────────────────────────────────

def save_checkpoint(
    model: torch.nn.Module,
    optimizer: torch.optim.Optimizer,
    step: int,
    loss: float,
    path: str,
) -> None:
    """
    Save model and optimizer state to a .pt file.

    We save everything needed to resume training from this exact point:
      • model state dict          (weights)
      • optimizer state dict      (momentum buffers, adaptive learning rates)
      • current step and loss     (metadata)
      • model config              (architecture hyper-parameters)

    Args:
        model    : NanoGPT instance
        optimizer: AdamW optimizer
        step     : current training step
        loss     : current loss value (used to track best checkpoint)
        path     : file path, e.g. "checkpoints/best_model.pt"
    """
    # Create parent directory if it doesn't exist.
    os.makedirs(os.path.dirname(path), exist_ok=True)

    # Convert model weights to bfloat16
    model_state = model.state_dict()
    model_state = {
        k: v.detach().to(torch.bfloat16).cpu()
        for k, v in model_state.items()
    }

    checkpoint = {
        "model_state_dict":     model_state,
        "optimizer_state_dict": optimizer.state_dict(),
        "step":                 step,
        "loss":                 loss,
        "config":               model.config,
    }
    torch.save(checkpoint, path)
    print(f"  → Checkpoint saved to {path}  (step={step}, loss={loss:.4f})")


def load_checkpoint(
    path: str,
    model: torch.nn.Module,
    optimizer: torch.optim.Optimizer = None,
) -> tuple[int, float]:
    """
    Load model (and optionally optimizer) weights from a checkpoint file.

    Args:
        path      : path to the .pt checkpoint file
        model     : NanoGPT instance (must have the same architecture as saved)
        optimizer : if provided, also restore optimizer state

    Returns:
        (step, loss) — the training step and loss at the time of saving
    """
    if not os.path.exists(path):
        raise FileNotFoundError(f"Checkpoint not found: {path}")

    torch.serialization.add_safe_globals([Config])
    checkpoint = torch.load(path, map_location="cpu")

    model.load_state_dict(checkpoint["model_state_dict"])

    if optimizer is not None and "optimizer_state_dict" in checkpoint:
        optimizer.load_state_dict(checkpoint["optimizer_state_dict"])

    step = checkpoint.get("step", 0)
    loss = checkpoint.get("loss", float("inf"))

    print(f"Loaded checkpoint from {path}  (step={step}, loss={loss:.4f})")
    return step, loss


# ─────────────────────────────────────────────────────────────────────────────
# Learning rate schedule
# ─────────────────────────────────────────────────────────────────────────────

def get_lr(step: int, config) -> float:
    """
    Cosine decay learning rate schedule with a linear warm-up phase.

    The schedule has three regions:
      1. Warm-up  (0 … warmup_steps):
             LR increases linearly from 0 to learning_rate.
             Prevents large gradient steps at the start of training when
             the model weights are random and the loss landscape is steep.

      2. Cosine decay  (warmup_steps … max_steps):
             LR decreases from learning_rate to min_lr following a
             half-cosine curve.  Smooth decay helps fine convergence.

      3. Flat minimum  (> max_steps):
             LR stays at min_lr (not relevant for finite training runs).

    Args:
        step   : current training step (0-indexed)
        config : Config dataclass

    Returns:
        learning rate as a float
    """
    min_lr = config.learning_rate * 0.1   # decay to 10 % of peak LR

    # 1. Linear warm-up.
    if step < config.warmup_steps:
        return config.learning_rate * (step + 1) / config.warmup_steps

    # 3. After training ends, hold at min_lr.
    if step > config.max_steps:
        return min_lr

    # 2. Cosine decay in the middle.
    # Map step into [0, 1] within the decay window.
    progress = (step - config.warmup_steps) / (config.max_steps - config.warmup_steps)
    # Cosine value goes from 1 (start) to 0 (end) → LR goes from peak to min.
    cosine_decay = 0.5 * (1.0 + math.cos(math.pi * progress))
    return min_lr + (config.learning_rate - min_lr) * cosine_decay


# ─────────────────────────────────────────────────────────────────────────────
# Helpers for C code generation of model weights
# ─────────────────────────────────────────────────────────────────────────────

def bf16_matrix_to_c_u16(tensor: torch.Tensor, name: str = "W") -> str:
    """
    Convert a 2D bfloat16 tensor to a C array of uint16_t values.

    Args:
    tensor : 2D PyTorch tensor with dtype torch.bfloat16
    name   : variable name for the generated C array

    Returns:
    A string containing the C code for a 2D array of uint16_t values of the input tensor, formatted as:
    const u16 W[rows][cols] = {
        {0x0000, 0x0000, ...},
        {0x0000, 0x0000, ...},
        ...
    };
    """
    assert tensor.ndim == 2, "Only 2D tensors supported"
    assert tensor.dtype == torch.bfloat16, "Tensor must be bfloat16"

    rows, cols = tensor.shape

    # View bf16 as uint16
    t_u16 = tensor.view(torch.uint16).cpu()

    lines = []
    for r in range(rows):
        row_vals = ", ".join(f"0x{t_u16[r, c].item():04x}" for c in range(cols))
        lines.append(f"{{{row_vals}}}")

    body = ",\n    ".join(lines)

    return f"const u16 {name}[{rows}][{cols}] = {{\n    {body}\n}};"

def bf16_vector_to_c_u16(tensor: torch.Tensor, name: str = "x") -> str:
    """
    Convert a 2D bfloat16 tensor with shape (N, 1) to a C array of uint16_t values.

    Args:
    tensor : 2D PyTorch tensor with shape (N, 1) and dtype torch.bfloat16
    name   : variable name for the generated C array

    Returns:
    A string containing the C code for a 1D array of uint16_t values of the input tensor, formatted as:
    const u16 x[N] = {0x0000, 0x0000, ...};
    """

    assert tensor.ndim == 2 and tensor.shape[1] == 1
    assert tensor.dtype == torch.bfloat16

    t_u16 = tensor.view(torch.uint16).cpu()
    rows = tensor.shape[0]

    vals = ", ".join(f"0x{t_u16[r, 0].item():04x}" for r in range(rows))

    return f"const u16 {name}[{rows}] = {{{vals}}};"
