# Script to generate C code for model weights from the trained checkpoint

import torch
from config import Config
from utils import bf16_matrix_to_c_u16, bf16_vector_to_c_u16
import os

def main():
    # Load the trained model checkpoint
    checkpoint_path = "checkpoints/best_model_bf16.pt"

    # Add to safe globals to allow loading Config from the checkpoint
    torch.serialization.add_safe_globals([Config])

    checkpoint = torch.load(checkpoint_path, map_location="cpu")
    model_state_dict = checkpoint["model_state_dict"]

    # Print the keys in the model state dict to verify it loaded correctly
    print("Model state dict keys:")
    for key in model_state_dict.keys():
        print(f"  {key}")

    # Create output directory for generated C code if it doesn't exist 
    os.makedirs("c_gen", exist_ok=True)
    OUT_FILE = "c_gen/gpt2_weights.h"
    HEADER_GUARD = "GPT2_WEIGHTS_H"

    # list to hold all generated C code lines
    all_items = []

    # Block 0
    # LayerNorm 1 (ln1) weights and biases
    if "blocks.0.ln1.weight" in model_state_dict and "blocks.0.ln1.bias" in model_state_dict:
        print(f"\nblocks.0.ln1.weight found in checkpoint and is of size {model_state_dict['blocks.0.ln1.weight'].shape}:")
        all_items.append(bf16_vector_to_c_u16(model_state_dict["blocks.0.ln1.weight"].view(-1, 1), "ln1_w")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility
        print(f"\nblocks.0.ln1.bias found in checkpoint and is of size {model_state_dict['blocks.0.ln1.bias'].shape}:")
        all_items.append(bf16_vector_to_c_u16(model_state_dict["blocks.0.ln1.bias"].view(-1, 1), "ln1_b")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility
    else:
        print("\nblocks.0.ln1.weight and/or blocks.0.ln1.bias NOT found in checkpoint.")

    # CausalSelfAttention mask
    if "blocks.0.attn.causal_mask" in model_state_dict:
        print(f"\nblocks.0.attn.causal_mask found in checkpoint and is of size {model_state_dict['blocks.0.attn.causal_mask'].shape}:")
        all_items.append(bf16_matrix_to_c_u16(model_state_dict["blocks.0.attn.causal_mask"][0][0], "causal_mask")) # get last 2 dimensions only

    # Attention projection weights Wq, Wk, Wv, Wo
    for proj in ["q_proj", "k_proj", "v_proj", "out_proj"]:
        key = f"blocks.0.attn.{proj}.weight"
        if key in model_state_dict:
            print(f"\n{key} found in checkpoint and is of size {model_state_dict[key].shape}:")
            all_items.append(bf16_matrix_to_c_u16(model_state_dict[key], proj)) # Convert to C array format
        else:
            print(f"\n{key} NOT found in checkpoint.")

    # LayerNorm 2 (ln2) weights and biases
    if "blocks.0.ln2.weight" in model_state_dict and "blocks.0.ln2.bias" in model_state_dict:
        print(f"\nblocks.0.ln2.weight found in checkpoint and is of size {model_state_dict['blocks.0.ln2.weight'].shape}:")
        all_items.append(bf16_vector_to_c_u16(model_state_dict["blocks.0.ln2.weight"].view(-1, 1), "ln2_w")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility
        print(f"\nblocks.0.ln2.bias found in checkpoint and is of size {model_state_dict['blocks.0.ln2.bias'].shape}:")
        all_items.append(bf16_vector_to_c_u16(model_state_dict["blocks.0.ln2.bias"].view(-1, 1), "ln2_b")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility
    else:
        print("\nblocks.0.ln2.weight and/or blocks.0.ln2.bias NOT found in checkpoint.")

    # FeedForward 0,2 weights and biases
    for ff in ["ff.net.0", "ff.net.2"]:
        key_w = f"blocks.0.{ff}.weight"
        key_b = f"blocks.0.{ff}.bias"
        if key_w in model_state_dict and key_b in model_state_dict:
            print(f"\n{key_w} found in checkpoint and is of size {model_state_dict[key_w].shape}:")
            all_items.append(bf16_matrix_to_c_u16(model_state_dict[key_w], ff.replace(".", "_") + "_w")) # Convert to C array format
            print(f"\n{key_b} found in checkpoint and is of size {model_state_dict[key_b].shape}:")
            all_items.append(bf16_vector_to_c_u16(model_state_dict[key_b].view(-1, 1), ff.replace(".", "_") + "_b")) # Reshape to (hidden_size, 1) for bf16_vector_to_c_u16 compatibility
        else:
            print(f"\n{key_w} and/or {key_b} NOT found in checkpoint.")

    # Final code
    final_code = f"""#ifndef {HEADER_GUARD}\n#define {HEADER_GUARD}\n\n#include <xil_io.h>\n\n"""

    final_code += "\n\n".join(all_items) # Add all generated C code items to the final code string

    final_code += f"""\n\n#endif // {HEADER_GUARD}"""

    with open(OUT_FILE, "w") as f:
        f.write(final_code)


if __name__ == "__main__":
    main()