"""
tokenizer.py — Thin wrapper around tiktoken's GPT-2 BPE tokenizer.

tiktoken is OpenAI's fast BPE tokenizer written in Rust.
We wrap it so the rest of the codebase never imports tiktoken directly —
making it easy to swap out the tokenizer later.
"""

import tiktoken


class Tokenizer:
    """
    Wraps tiktoken's GPT-2 encoding.

    GPT-2 BPE tokenizer facts:
      • Vocabulary size : 50,257 tokens
      • Special tokens  : <|endoftext|> has id 50256
      • Byte-pair encoding means subword units — it handles any UTF-8 text
        without ever producing an <UNK> token.
    """

    def __init__(self):
        # Load the exact encoding used by GPT-2.
        # tiktoken downloads and caches the merge rules on first use.
        self._enc = tiktoken.get_encoding("gpt2")

    # ── Core API ─────────────────────────────────────────────────────────────

    def encode(self, text: str) -> list[int]:
        """
        Convert a string into a list of integer token ids.

        Example:
            tokenizer.encode("Hello world")
            → [15496, 995]   (GPT-2 BPE ids)
        """
        return self._enc.encode(text, allowed_special={"<|endoftext|>"})

    def decode(self, tokens: list[int]) -> str:
        """
        Convert a list of token ids back into a human-readable string.

        Note: decoding may produce bytes that aren't valid UTF-8 at the
        boundaries of truncated sequences; tiktoken handles this gracefully.
        """
        return self._enc.decode(tokens)

    # ── Properties ───────────────────────────────────────────────────────────

    @property
    def vocab_size(self) -> int:
        """Total number of tokens in the vocabulary (always 50257 for GPT-2)."""
        return self._enc.n_vocab

    @property
    def eot_token(self) -> int:
        """The end-of-text token id (50256 for GPT-2)."""
        return self._enc.eot_token

    def __repr__(self):
        return f"Tokenizer(encoding=gpt2, vocab_size={self.vocab_size})"


# ── Quick smoke-test ──────────────────────────────────────────────────────────
if __name__ == "__main__":
    tok = Tokenizer()
    text = "Hello, world! This is NanoGPT."
    ids = tok.encode(text)
    recovered = tok.decode(ids)
    print(f"Original : {text!r}")
    print(f"Token ids: {ids}")
    print(f"Decoded  : {recovered!r}")
    print(f"Vocab size: {tok.vocab_size}")
    assert recovered == text, "Round-trip encode/decode failed!"
    print("✓ Tokenizer smoke-test passed.")