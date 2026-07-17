import torch
import torch.nn.functional as F
from config import Config
from utils import bf16_matrix_to_c_u16, bf16_vector_to_c_u16
from tokenizer import Tokenizer
torch.backends.cuda.matmul.allow_bf16_reduced_precision_reduction = True
torch.backends.cuda.allow_fp16_bf16_reduction_math_sdp(True)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

# Tokenize the work "All"
prompt = "All"
tokenizer = Tokenizer()
tokens_ids = tokenizer.encode(prompt)

idx = torch.tensor([tokens_ids], dtype=torch.long, device=device)  # (1, T)
T = idx.size(1) # Should be 1 here for the single token "All"

print(f"Token IDs for '{prompt}': {tokens_ids} | Shape of idx: {idx.shape} and T: {T}")

# Load the trained model checkpoint
checkpoint_path = "checkpoints/best_model_bf16.pt"

# Add to safe globals to allow loading Config from the checkpoint
torch.serialization.add_safe_globals([Config])

checkpoint = torch.load(checkpoint_path, map_location=device)
model_state_dict = checkpoint["model_state_dict"]

# Print the keys in the model state dict to verify it loaded correctly
print("Model state dict keys:")
for key in model_state_dict.keys():
    print(f"  {key}")

# Extract tok_emb and pos_emb weights
tok_emb_weights = model_state_dict["tok_emb.weight"]
pos_emb_weights = model_state_dict["pos_emb.weight"]

# Extract Wq, Wk, Wv, Wo weights for block 0
Wq = model_state_dict["blocks.0.attn.q_proj.weight"]  # (hidden_size, hidden_size)
Wk = model_state_dict["blocks.0.attn.k_proj.weight"]  # (hidden_size, hidden_size)
Wv = model_state_dict["blocks.0.attn.v_proj.weight"]  # (hidden_size, hidden_size)
Wo = model_state_dict["blocks.0.attn.out_proj.weight"]  # (hidden_size, hidden_size)

tok_emb = tok_emb_weights[tokens_ids]  # (1, T, hidden_size)
pos = torch.arange(T, device=device) 
pos_emb = pos_emb_weights[pos]  # (T, hidden_size)

# Add token and position embeddings
x0 = tok_emb + pos_emb  # (1, T, hidden_size)
print(bf16_vector_to_c_u16(x0[0].view(-1, 1), "x0")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility

# Extract block 0 ln1 weights and biases (LayerNorm 1)
ln1_weight = model_state_dict["blocks.0.ln1.weight"] # (hidden_size,)
ln1_bias = model_state_dict["blocks.0.ln1.bias"] # (hidden_size,)

# For sanity check use F.layer_norm to compute the output of the first LayerNorm
ln1_out_torch = F.layer_norm(x0, normalized_shape=ln1_weight.shape, weight=ln1_weight, bias=ln1_bias, eps=1e-6)  # (1, T, hidden_size)
print(bf16_vector_to_c_u16(ln1_out_torch.view(-1, 1), "ln1_out_torch")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility

# F.linear performs: y = x @ W^T
q_out_torch = F.linear(ln1_out_torch, Wq, bias=None)
k_out_torch = F.linear(ln1_out_torch, Wk, bias=None)
v_out_torch = F.linear(ln1_out_torch, Wv, bias=None)

print(bf16_vector_to_c_u16(q_out_torch[0].view(-1, 1), "q_out_torch")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility
print(bf16_vector_to_c_u16(k_out_torch[0].view(-1, 1), "k_out_torch")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility
print(bf16_vector_to_c_u16(v_out_torch[0].view(-1, 1), "v_out_torch")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility

# TODO: Do the rest of the computations for block 0

print(f"\n--- Execution Trace ---")
print(f"Input Tokens: {tokens_ids}")
print(f"Shape after Embedding: {x0.shape}")
print(f"Shape after LayerNorm: {ln1_out_torch.shape}")
print(f"Shape after Q Projection: {q_out_torch.shape}")
print(f"Shape after K Projection: {k_out_torch.shape}")
print(f"Shape after V Projection: {v_out_torch.shape}")