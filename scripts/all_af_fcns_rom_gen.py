import torch
import struct

def float_to_bf16_hex(value):
    """Converts a standard Python float to a 4-character Bfloat16 Hex string."""
    # Pack the float into 4 bytes (IEEE 754 Single Precision)
    packed = struct.pack('>f', value)
    # Grab the top 2 bytes (which is exactly the Bfloat16 representation)
    bf16_bytes = packed[:2]
    # Convert to hex and strip the '0x'
    return bf16_bytes.hex().upper()

def generate_rom_data(filename):
    print(f"Generating ROM file: {filename}")
    
    # 1. Bounds as defined in HDL (cent-emulation/ip_repo/pim/af_unit.vhd): -8.0 to +8.0 with 512 segments
    num_segments = 512
    x_min = -8.0
    x_max = 8.0
    
    # We need 513 points to calculate 512 deltas
    x_points = torch.linspace(x_min, x_max, num_segments + 1)
    
    # 2. Define the Activation Functions
    # The order MUST match the 'af_sel' binary encoding in VHDL
    # af_sel = "000" -> Sigmoid
    # af_sel = "001" -> Tanh
    # af_sel = "010" -> GELU
    # af_sel = "011" -> ReLU
    # af_sel = "100" -> Leaky ReLU
    # af_sel = "101" to "111" -> Unused (set to 0)
    
    functions = [
        ("Sigmoid", torch.sigmoid(x_points)),
        ("Tanh", torch.tanh(x_points)),
        ("GELU", torch.nn.functional.gelu(x_points)),
        ("ReLU", torch.nn.functional.relu(x_points)),
        ("Leaky_ReLU", torch.nn.functional.leaky_relu(x_points)),
        ("Unused_0", torch.zeros_like(x_points)),
        ("Unused_1", torch.zeros_like(x_points)),
        ("Unused_2", torch.zeros_like(x_points))
    ]
    
    # 3. Write to the .mem file
    with open(filename, 'w') as f:
        # Xilinx .mem file is just raw hex values separated by newlines
        # Each line will be 8 hex characters (4 bytes) representing Y_base and Delta_Y
        # Keep track of total lines to prevent adding an extra newline at the end of the file
        total_lines = len(functions) * num_segments
        current_line = 0

        for index, (name, y_values) in enumerate(functions):
            print(f"  Calculating {name}... (af_sel = {index:03b})")
            
            for i in range(num_segments):
                # Get the start of the segment and the end of the segment
                y_base = y_values[i].item()
                y_next = y_values[i+1].item()
                
                # Calculate Delta Y
                delta_y = y_next - y_base
                
                # Convert to Bfloat16 Hex
                y_base_hex = float_to_bf16_hex(y_base)
                delta_y_hex = float_to_bf16_hex(delta_y)
                
                # Concatenate: Y_base [31:16] & Delta_Y [15:0]
                # Write to file
                current_line += 1
                line = f"{y_base_hex}{delta_y_hex}"
                if current_line < total_lines:
                    f.write(line + "\n")
                else:
                    f.write(line)


    print(f"Done! {len(functions)} functions * {num_segments} words = {total_lines} addresses written.")
    print("Vivado ROM size is 4096 addresses (12-bit).")

if __name__ == "__main__":
    generate_rom_data("all_af_fcns_rom.mem")