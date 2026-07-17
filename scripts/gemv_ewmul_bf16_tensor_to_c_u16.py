import torch
import torch.nn.functional as F

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

def bf16_tensor_to_c_u16(tensor, name="W"):
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

def bf16_vector_to_c_u16(tensor, name="x"):
    assert tensor.ndim == 2 and tensor.shape[1] == 1
    assert tensor.dtype == torch.bfloat16

    t_u16 = tensor.view(torch.uint16).cpu()
    rows = tensor.shape[0]

    vals = ", ".join(f"0x{t_u16[r, 0].item():04x}" for r in range(rows))

    return f"const u16 {name}[{rows}] = {{{vals}}};"

def gemv_NxN_example(N, bias=True, activation=F.relu):
    W = (torch.randn(N, N, dtype=torch.float32, device=device) * torch.sqrt(torch.tensor(0.5))).to(torch.bfloat16) # gaussian with stddev sqrt(0.5) i.e. var 0.5
    x = (torch.randn(N, 1, dtype=torch.float32, device=device) * 0.5).to(torch.bfloat16) # gaussian with stddev 0.5 i.e. var 0.25
    if bias:
        b = (torch.randn(N, 1, dtype=torch.float32, device=device) * 0.5).to(torch.bfloat16) # gaussian with stddev 0.5 i.e. var 0.25
    else:
        b = torch.zeros(N, 1, dtype=torch.float32, device=device).to(torch.bfloat16)

    # Using F.linear() is not he same as (W @ x) + b for bfloat16 on modern cuda GPUs
    # (W @ x) + b does (W @ x) first in float32 then cast to bfloat16, then adds b in bfloat16. 
    # F.linear() does the whole operation in float32 and then casts the final result to bfloat16.
    y = F.linear(x.view(1, N), W, bias=b.squeeze(1) if bias else None).view(N, 1)
    
    if activation is None:
        res = y
    else:
        y_clamped = torch.clamp(y, -8.0, 8.0)
        res = activation(y_clamped)

    print(bf16_tensor_to_c_u16(W, name=f"W_{N}x{N}"))
    print(bf16_vector_to_c_u16(x, name=f"x_{N}x1"))
    print(bf16_vector_to_c_u16(b, name=f"bias_{N}x1"))
    if activation is None:
        print(bf16_vector_to_c_u16(res, name=f"expected_result_{N}x1_gemv"))
    else:
        print(bf16_vector_to_c_u16(res, name=f"expected_result_{N}x1_gemv_{activation.__name__}"))

def ewmul_N_example(N):
    a = (torch.randn(N, 1, dtype=torch.float32, device=device) * 0.5).to(torch.bfloat16) # gaussian with stddev 0.5 i.e. var 0.25
    b = (torch.randn(N, 1, dtype=torch.float32, device=device) * 0.5).to(torch.bfloat16) # gaussian with stddev 0.5 i.e. var 0.25

    res = torch.mul(a, b)

    print(bf16_vector_to_c_u16(a, name=f"a_{N}x1"))
    print(bf16_vector_to_c_u16(b, name=f"b_{N}x1"))
    print(bf16_vector_to_c_u16(res, name=f"expected_result_{N}x1_ewmul"))

if __name__ == "__main__":
    print("Using device:", device)

    # Example usage for a 128x128 weight matrix and 128x1 input vector and a 128x1 bias vector, all in bf16. No activation function.
    N = 16
    activ = F.relu  # Change to F.relu or F.sigmoid or any other activation
    bias = True  # Change to True to include random bias
    gemv_NxN_example(N, bias=bias, activation=activ)
    ewmul_N_example(N)
