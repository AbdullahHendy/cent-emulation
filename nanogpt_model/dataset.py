"""
dataset.py — Dataset and DataLoader utilities for NanoGPT.

Language modelling is a self-supervised task: given a sequence of tokens,
predict the next token at every position.  That means we don't need any
hand-labelled data — the labels are simply the inputs shifted one step to
the right.

  input  : [t0, t1, t2, ..., t_{T-1}]
  target : [t1, t2, t3, ..., t_T    ]

The model sees input[i] and must predict target[i] = input[i+1].
"""

import torch
from torch.utils.data import Dataset, DataLoader, random_split
import numpy as np
from typing import Tuple


class TextDataset(Dataset):
    """
    Sliding-window character-language-model dataset.

    Given a long token sequence of length N and a context window of
    length T (= max_seq_len), this dataset has N - T examples:
      example i  →  tokens[i : i+T]   (input)
                    tokens[i+1 : i+T+1] (target, shifted by 1)

    Args:
        text      : raw string to train on
        tokenizer : Tokenizer instance (from tokenizer.py)
        max_seq_len: context window length T
    """

    def __init__(self, text: str, tokenizer, max_seq_len: int):
        self.max_seq_len = max_seq_len

        # Tokenize the entire corpus once and store as a 1-D int32 tensor.
        # For 1 MB of Shakespeare text this is ~300k tokens — fits easily in RAM.
        token_ids = tokenizer.encode(text)
        self.tokens = torch.tensor(token_ids, dtype=torch.long)

        print(f"Dataset: {len(text):,} characters → {len(self.tokens):,} tokens")
        print(f"Context window: {max_seq_len} tokens → {len(self):,} training examples")

    def __len__(self) -> int:
        # Each example uses (max_seq_len + 1) consecutive tokens
        # (max_seq_len for input + 1 extra for the final target label).
        return len(self.tokens) - self.max_seq_len

    def __getitem__(self, idx: int) -> Tuple[torch.Tensor, torch.Tensor]:
        """
        Returns a single (input, target) pair.

        Shapes:
          x : (max_seq_len,)  — token ids fed into the model
          y : (max_seq_len,)  — token ids the model must predict (x shifted +1)
        """
        # Grab a chunk of max_seq_len+1 tokens starting at idx.
        chunk = self.tokens[idx : idx + self.max_seq_len + 1]  # (T+1,)
        x = chunk[:-1]   # (T,)  — input tokens
        y = chunk[1:]    # (T,)  — target tokens (each is "next token" for x)
        return x, y


def get_dataloader(
    text: str,
    tokenizer,
    max_seq_len: int,
    batch_size: int,
    val_fraction: float = 0.1,
    num_workers: int = 0,
) -> Tuple[DataLoader, DataLoader]:
    """
    Build train and validation DataLoaders from raw text.

    Splits the dataset (not the raw text) so that both splits see the same
    tokenised sequence — only the *indices* are partitioned.

    Args:
        text         : raw training corpus
        tokenizer    : Tokenizer instance
        max_seq_len  : context window length
        batch_size   : examples per batch
        val_fraction : fraction of examples held out for validation
        num_workers  : DataLoader worker processes (0 = main process only)

    Returns:
        (train_loader, val_loader)
    """
    dataset = TextDataset(text, tokenizer, max_seq_len)

    n_val   = int(len(dataset) * val_fraction)
    n_train = len(dataset) - n_val

    train_ds, val_ds = random_split(
        dataset, [n_train, n_val],
        generator=torch.Generator().manual_seed(42),  # reproducible split
    )

    train_loader = DataLoader(
        train_ds,
        batch_size=batch_size,
        shuffle=True,
        num_workers=num_workers,
        pin_memory=True,   # speeds up CPU→GPU transfer when CUDA is available
        drop_last=True,    # keeps every batch the same size
    )
    val_loader = DataLoader(
        val_ds,
        batch_size=batch_size,
        shuffle=False,
        num_workers=num_workers,
        pin_memory=True,
        drop_last=True,
    )

    print(f"Train: {n_train:,} examples ({len(train_loader):,} batches)")
    print(f"Val  : {n_val:,} examples ({len(val_loader):,} batches)")
    return train_loader, val_loader


def get_batch(
    tokens: torch.Tensor,
    max_seq_len: int,
    batch_size: int,
    device: str,
) -> Tuple[torch.Tensor, torch.Tensor]:
    """
    Fast random batch sampler — useful during training when you want to
    avoid DataLoader overhead (e.g. for the quick eval inside the loop).

    Picks `batch_size` random starting positions and extracts overlapping
    windows.  This is the approach used in Karpathy's minGPT / nanoGPT.

    Args:
        tokens     : 1-D tensor of all token ids  shape (N,)
        max_seq_len: context length T
        batch_size : B
        device     : "cpu" / "cuda" / "mps"

    Returns:
        x : (B, T)  input token ids
        y : (B, T)  target token ids
    """
    # Sample B random start indices such that the full window fits.
    ix = torch.randint(len(tokens) - max_seq_len, (batch_size,))

    # Stack windows into (B, T) tensors.
    x = torch.stack([tokens[i     : i + max_seq_len    ] for i in ix])  # (B, T)
    y = torch.stack([tokens[i + 1 : i + max_seq_len + 1] for i in ix])  # (B, T)

    # Move to device (no-op if already there).
    return x.to(device), y.to(device)