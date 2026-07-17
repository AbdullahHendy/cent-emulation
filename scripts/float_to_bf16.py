import numpy as np
import sys
import torch

def float_to_bf16_hex(x):
    x = torch.tensor(x, dtype=torch.bfloat16)
    t_u16 = x.view(torch.uint16).cpu()
    return f"0x{t_u16.item():04x}"

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python float_to_bf16.py <number>")
        sys.exit(1)

    try:
        num = float(sys.argv[1])
    except ValueError:
        print("Error: argument must be a number")
        sys.exit(1)

    print(float_to_bf16_hex(num))
