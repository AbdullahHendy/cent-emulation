import sys
import struct


def bf16_hex_to_float(bf16_str):
    """
    Convert a bfloat16 hex string (e.g. '0x4049')
    into a Python float.
    """
    # Remove optional 0x prefix
    bf16 = int(bf16_str, 16)

    # Place BF16 in the upper 16 bits of a float32
    float_bits = bf16 << 16

    # Reinterpret as IEEE-754 float32
    return struct.unpack('>f', struct.pack('>I', float_bits))[0]


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python bf16_to_float.py <bf16_hex>")
        print("Example: python bf16_to_float.py 0x4049")
        sys.exit(1)

    try:
        result = bf16_hex_to_float(sys.argv[1])
        print(result)
    except ValueError:
        print("Error: argument must be a valid hexadecimal BF16 value")
        sys.exit(1)

