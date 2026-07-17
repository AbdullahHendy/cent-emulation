"""
model.py — NanoGPT model architecture.

This implements a decoder-only transformer (GPT-style) from scratch using
only PyTorch primitives.  The architecture follows the GPT-2 paper with the
"pre-norm" variant popularised by Andrej Karpathy's nanoGPT:
  • Layer normalisation is applied *before* each sub-layer (Pre-LN).
  • This is more stable to train than the original Post-LN GPT.

Module hierarchy:
  NanoGPT
  └── TransformerBlock  x num_layers
      ├── CausalSelfAttention
      └── FeedForward

Tensor dimension abbreviations used in comments throughout this file:
  B  = batch size
  T  = sequence length (time steps, ≤ max_seq_len)
  C  = embed_dim (channels / model width)
  H  = num_heads
  hs = head size = C // H
"""

import math
import torch
import torch.nn as nn
import torch.nn.functional as F
from config import Config


# ─────────────────────────────────────────────────────────────────────────────
# 1.  Causal Self-Attention
# ─────────────────────────────────────────────────────────────────────────────

class CausalSelfAttention(nn.Module):
    """
    Multi-head self-attention with a causal (look-ahead) mask.

    "Causal" means each position can only attend to itself and earlier
    positions — never to future tokens.  This is enforced by masking out
    the upper triangle of the attention weight matrix before softmax.

    For each head the computation is:
      Q = x W_q,  K = x W_k,  V = x W_v          # (B, T, hs)
      scores = Q K^T / sqrt(hs)                    # (B, H, T, T)
      scores = masked_fill(upper_tri, -inf)        # causal mask
      attn   = softmax(scores)                     # (B, H, T, T)
      out    = attn V                              # (B, H, T, hs)
    Then concat all heads and project: out W_proj  # (B, T, C)
    """

    def __init__(self, config: Config):
        super().__init__()
        assert config.embed_dim % config.num_heads == 0

        self.num_heads = config.num_heads
        self.embed_dim = config.embed_dim
        self.head_size = config.embed_dim // config.num_heads  # hs = C / H

        # Separate Q, K, V projection matrices (each maps C → C).
        # Using separate Linear layers makes the code easy to follow;
        # a single fused projection of size 3C would be slightly faster.
        self.q_proj = nn.Linear(config.embed_dim, config.embed_dim, bias=False)
        self.k_proj = nn.Linear(config.embed_dim, config.embed_dim, bias=False)
        self.v_proj = nn.Linear(config.embed_dim, config.embed_dim, bias=False)

        # Output projection: maps the concatenated head outputs back to C.
        self.out_proj = nn.Linear(config.embed_dim, config.embed_dim, bias=False)

        # Dropout applied to attention weights (regularises which tokens are
        # attended to) and to the output projection.
        self.attn_dropout = nn.Dropout(config.dropout)
        self.proj_dropout = nn.Dropout(config.dropout)

        # Register the causal mask as a buffer (not a parameter — it's constant).
        # Shape: (1, 1, max_seq_len, max_seq_len)
        # torch.tril gives the lower triangle (True = keep, False = mask).
        mask = torch.tril(
            torch.ones(config.max_seq_len, config.max_seq_len)
        ).view(1, 1, config.max_seq_len, config.max_seq_len)
        self.register_buffer("causal_mask", mask)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args:
            x: (B, T, C)  — token embeddings + positional encodings

        Returns:
            out: (B, T, C)  — contextualised representations
        """
        B, T, C = x.shape

        # ── Project to Q, K, V ──────────────────────────────────────────────
        q = self.q_proj(x)   # (B, T, C)
        k = self.k_proj(x)   # (B, T, C)
        v = self.v_proj(x)   # (B, T, C)

        # ── Reshape to (B, H, T, hs) for multi-head attention ────────────────
        # Split the C-dim into H heads each of size hs, then transpose so
        # the head dimension comes before the time dimension.
        q = q.view(B, T, self.num_heads, self.head_size).transpose(1, 2)  # (B, H, T, hs)
        k = k.view(B, T, self.num_heads, self.head_size).transpose(1, 2)  # (B, H, T, hs)
        v = v.view(B, T, self.num_heads, self.head_size).transpose(1, 2)  # (B, H, T, hs)

        # ── Scaled dot-product attention scores ──────────────────────────────
        # Divide by sqrt(hs) to keep the dot products from growing too large,
        # which would push softmax into regions of very small gradients.
        scale = 1.0 / math.sqrt(self.head_size)
        scores = torch.matmul(q, k.transpose(-2, -1)) * scale  # (B, H, T, T)

        # ── Apply causal mask ─────────────────────────────────────────────────
        # Positions where the mask is 0 (upper triangle) get -inf so that
        # softmax produces 0 attention weight there — future tokens are invisible.
        scores = scores.masked_fill(
            self.causal_mask[:, :, :T, :T] == 0,
            float("-inf")
        )  # (B, H, T, T)

        # ── Softmax + dropout ────────────────────────────────────────────────
        attn = F.softmax(scores, dim=-1)   # (B, H, T, T)  rows sum to 1
        attn = self.attn_dropout(attn)     # (B, H, T, T)

        # ── Weighted sum of values ────────────────────────────────────────────
        out = torch.matmul(attn, v)        # (B, H, T, hs)

        # ── Concatenate heads and project ────────────────────────────────────
        # contiguous() is required before view() because transpose() creates a
        # non-contiguous tensor in memory.
        out = out.transpose(1, 2).contiguous().view(B, T, C)  # (B, T, C)
        out = self.proj_dropout(self.out_proj(out))            # (B, T, C)

        return out


# ─────────────────────────────────────────────────────────────────────────────
# 2.  Feed-Forward Network
# ─────────────────────────────────────────────────────────────────────────────

class FeedForward(nn.Module):
    """
    Position-wise feed-forward network (FFN) applied after attention.

    The FFN processes each token position independently (no cross-position
    interaction).  It expands the representation to a higher-dimensional
    "intermediate" space and then projects back:

      FFN(x) = dropout( W_2 GELU( W_1 x + b_1 ) + b_2 )

    The inner dimension is 4 x embed_dim, following the GPT-2 paper.
    GELU (Gaussian Error Linear Unit) is used instead of ReLU because it
    provides smoother gradients near zero.
    """

    def __init__(self, config: Config):
        super().__init__()
        inner_dim = 4 * config.embed_dim   # expansion ratio = 4 (standard GPT)

        self.net = nn.Sequential(
            nn.Linear(config.embed_dim, inner_dim),   # (C → 4C)
            nn.GELU(),                                 # smooth activation
            nn.Linear(inner_dim, config.embed_dim),   # (4C → C)
            nn.Dropout(config.dropout),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args / Returns:  (B, T, C)  — shape is unchanged
        """
        return self.net(x)  # (B, T, C) → (B, T, 4C) → (B, T, C)


# ─────────────────────────────────────────────────────────────────────────────
# 3.  Transformer Block
# ─────────────────────────────────────────────────────────────────────────────

class TransformerBlock(nn.Module):
    """
    One transformer decoder block: Attention + FFN, both with Pre-LN + residual.

    Pre-LN (Layer Norm applied *before* the sub-layer) is:
      x = x + Attention( LayerNorm(x) )
      x = x + FFN(       LayerNorm(x) )

    Compared to the original Post-LN, Pre-LN has more stable gradients and
    usually doesn't require learning-rate warm-up, though we still use warmup
    as good practice.

    The residual connections (x + ...) let gradients flow directly to early
    layers, solving the vanishing-gradient problem in deep networks.
    """

    def __init__(self, config: Config):
        super().__init__()
        self.ln1  = nn.LayerNorm(config.embed_dim)    # norm before attention
        self.attn = CausalSelfAttention(config)
        self.ln2  = nn.LayerNorm(config.embed_dim)    # norm before FFN
        self.ff   = FeedForward(config)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Args / Returns:  (B, T, C)
        """
        # Attention sub-layer with Pre-LN and residual connection.
        x = x + self.attn(self.ln1(x))   # (B, T, C)

        # FFN sub-layer with Pre-LN and residual connection.
        x = x + self.ff(self.ln2(x))     # (B, T, C)

        return x


# ─────────────────────────────────────────────────────────────────────────────
# 4.  NanoGPT — the full model
# ─────────────────────────────────────────────────────────────────────────────

class NanoGPT(nn.Module):
    """
    GPT-2 style decoder-only transformer.

    Forward pass (high level):
      1. Look up token embeddings          (B, T) → (B, T, C)
      2. Add learned positional embeddings (B, T, C) + (1, T, C)
      3. Apply dropout to the combined embedding
      4. Pass through num_layers transformer blocks
      5. Apply final layer norm
      6. Project to vocabulary logits      (B, T, C) → (B, T, vocab_size)

    Weight tying: the output projection shares its weight matrix with the
    token embedding table.  This is a well-established trick that reduces
    parameters and improves generalisation (Press & Wolf, 2017).
    """

    def __init__(self, config: Config):
        super().__init__()
        self.config = config

        # ── Embeddings ────────────────────────────────────────────────────────
        # Token embedding: maps each integer token id to a vector of size C.
        self.tok_emb = nn.Embedding(config.vocab_size, config.embed_dim)

        # Positional embedding: one learned vector per position 0 … max_seq_len-1.
        # These capture the *order* of tokens — transformers are otherwise
        # permutation-invariant and would have no sense of position.
        self.pos_emb = nn.Embedding(config.max_seq_len, config.embed_dim)

        self.emb_dropout = nn.Dropout(config.dropout)

        # ── Transformer blocks ────────────────────────────────────────────────
        self.blocks = nn.ModuleList(
            [TransformerBlock(config) for _ in range(config.num_layers)]
        )

        # ── Final layer norm ──────────────────────────────────────────────────
        # Applied after the last transformer block and before the output head.
        self.ln_f = nn.LayerNorm(config.embed_dim)

        # ── Output (language model) head ──────────────────────────────────────
        # Projects from embed_dim to vocab_size to produce logits.
        # No bias term — standard in GPT-2.
        self.lm_head = nn.Linear(config.embed_dim, config.vocab_size, bias=False)

        # ── Weight tying ──────────────────────────────────────────────────────
        # Share parameters between the input token embedding and output head.
        # tok_emb maps  vocab_size → embed_dim  (shape: vocab_size × embed_dim)
        # lm_head maps  embed_dim  → vocab_size  (shape: vocab_size × embed_dim transposed)
        # So they share the same weight matrix.
        self.lm_head.weight = self.tok_emb.weight

        # ── Weight initialisation ─────────────────────────────────────────────
        self.apply(self._init_weights)

        # Special scaled init for residual projections (GPT-2 paper, Appendix B).
        # Dividing by sqrt(num_layers) keeps the variance of the residual stream
        # roughly constant as we stack more layers.
        for name, param in self.named_parameters():
            if name.endswith("out_proj.weight") or name.endswith("net.2.weight"):
                nn.init.normal_(param, mean=0.0, std=0.02 / math.sqrt(2 * config.num_layers))

        total = self.count_parameters()
        print(f"NanoGPT initialised — {total} parameters")

    # ── Weight initialisation ─────────────────────────────────────────────────

    def _init_weights(self, module):
        """
        Standard GPT-2 initialisation:
          - Linear layers: N(0, 0.02) weights, zeros biases
          - Embedding tables: N(0, 0.02)
          - LayerNorm: ones weights, zeros biases (identity transform at init)
        """
        if isinstance(module, nn.Linear):
            nn.init.normal_(module.weight, mean=0.0, std=0.02)
            if module.bias is not None:
                nn.init.zeros_(module.bias)
        elif isinstance(module, nn.Embedding):
            nn.init.normal_(module.weight, mean=0.0, std=0.02)
        elif isinstance(module, nn.LayerNorm):
            nn.init.ones_(module.weight)
            nn.init.zeros_(module.bias)

    # ── Forward pass ──────────────────────────────────────────────────────────

    def forward(
        self,
        idx: torch.Tensor,
        targets: torch.Tensor = None,
    ):
        """
        Args:
            idx     : (B, T)  token ids
            targets : (B, T)  target token ids (optional; required for loss)

        Returns:
            logits  : (B, T, vocab_size)
            loss    : scalar cross-entropy loss if targets provided, else None
        """
        B, T = idx.shape
        assert T <= self.config.max_seq_len, (
            f"Sequence length {T} exceeds max_seq_len {self.config.max_seq_len}"
        )

        # ── Embedding lookup ──────────────────────────────────────────────────
        # Token embeddings: one vector per token in the sequence.
        tok = self.tok_emb(idx)               # (B, T, C)

        # Positional embeddings: one vector per position 0..T-1.
        pos = torch.arange(T, device=idx.device)    # (T,)
        pos = self.pos_emb(pos)               # (T, C)  — broadcast over batch

        # Combine and apply dropout.
        x = self.emb_dropout(tok + pos)       # (B, T, C)

        # ── Transformer blocks ────────────────────────────────────────────────
        for block in self.blocks:
            x = block(x)                      # (B, T, C)

        # ── Final norm + head ─────────────────────────────────────────────────
        x = self.ln_f(x)                      # (B, T, C)
        logits = self.lm_head(x)              # (B, T, vocab_size)

        # ── Loss ──────────────────────────────────────────────────────────────
        loss = None
        if targets is not None:
            # Reshape for F.cross_entropy which expects (N, C) predictions and
            # (N,) targets.  Here N = B*T and C = vocab_size.
            loss = F.cross_entropy(
                logits.view(B * T, -1),   # (B*T, vocab_size)
                targets.view(B * T),      # (B*T,)
            )

        return logits, loss

    # ── Text generation ───────────────────────────────────────────────────────

    @torch.no_grad()
    def generate(
        self,
        idx: torch.Tensor,
        max_new_tokens: int,
        temperature: float = 1.0,
        top_k: int = None,
    ) -> torch.Tensor:
        """
        Auto-regressively generate `max_new_tokens` tokens.

        At each step:
          1. Feed the context window through the model to get logits.
          2. Divide logits by temperature (higher → more random).
          3. Optionally keep only the top-k logits (nucleus-style pruning).
          4. Sample from the softmax distribution.
          5. Append the new token to the sequence and repeat.

        Args:
            idx            : (B, T)  seed token ids (prompt)
            max_new_tokens : how many new tokens to generate
            temperature    : > 1 = more random, < 1 = more deterministic
            top_k          : if set, zero out all but top-k logits before sampling

        Returns:
            idx : (B, T + max_new_tokens)  original prompt + generated tokens
        """
        self.eval()

        for _ in range(max_new_tokens):
            # Crop the context to max_seq_len if it's grown too long.
            idx_cond = idx[:, -self.config.max_seq_len:]   # (B, T')

            # Forward pass — we only need the logit at the *last* position.
            # Using bf16
            with torch.autocast(device_type=idx.device.type, dtype=torch.bfloat16):
                logits, _ = self(idx_cond)                 # (B, T', vocab_size)
            logits = logits[:, -1, :]                      # (B, vocab_size)

            # Apply temperature scaling.
            if temperature != 1.0:
                logits = logits / temperature              # (B, vocab_size)

            # Apply top-k filtering: zero out all logits outside the top k.
            if top_k is not None:
                top_k = min(top_k, logits.size(-1))
                # Get the value of the k-th largest logit for each batch item.
                threshold = torch.topk(logits, top_k).values[:, -1, None]  # (B, 1)
                logits = logits.masked_fill(logits < threshold, float("-inf"))

            # Convert logits to probabilities and sample one token per batch item.
            probs = F.softmax(logits, dim=-1)              # (B, vocab_size)
            next_token = torch.multinomial(probs, num_samples=1)  # (B, 1)

            # Append the new token to the running sequence.
            idx = torch.cat([idx, next_token], dim=1)     # (B, T+1)

        return idx

    # ── Utilities ─────────────────────────────────────────────────────────────

    def count_parameters(self) -> str:
        """
        Returns a human-readable parameter count like "10.2M".
        Counts only trainable parameters.
        """
        n = sum(p.numel() for p in self.parameters() if p.requires_grad)
        if n >= 1_000_000:
            return f"{n / 1_000_000:.1f}M"
        elif n >= 1_000:
            return f"{n / 1_000:.1f}K"
        return str(n)

    def configure_optimizers(self, learning_rate: float, weight_decay: float = 0.1):
        """
        Build an AdamW optimizer with weight decay applied *only* to 2-D
        parameters (weight matrices).  Biases, embeddings, and LayerNorm
        parameters are explicitly excluded from weight decay because decaying
        them doesn't help and can hurt training stability.

        Args:
            learning_rate : peak LR (will be scheduled externally)
            weight_decay  : L2 regularisation strength for weight matrices

        Returns:
            torch.optim.AdamW
        """
        decay_params    = []
        no_decay_params = []

        for name, param in self.named_parameters():
            if not param.requires_grad:
                continue
            if param.dim() >= 2:
                # 2-D+ params are weight matrices — apply decay.
                decay_params.append(param)
            else:
                # 1-D params are biases, LayerNorm scales/shifts, embeddings — no decay.
                no_decay_params.append(param)

        param_groups = [
            {"params": decay_params,    "weight_decay": weight_decay},
            {"params": no_decay_params, "weight_decay": 0.0},
        ]

        n_decay    = sum(p.numel() for p in decay_params)
        n_no_decay = sum(p.numel() for p in no_decay_params)
        print(f"Optimizer param groups: {n_decay:,} with decay | {n_no_decay:,} without decay")

        optimizer = torch.optim.AdamW(
            param_groups,
            lr=learning_rate,
            betas=(0.9, 0.95),   # GPT-3 paper recommendations
            eps=1e-8,
        )
        return optimizer