#include "pnm.h"
#include <math.h>

pnm_cmd_t pnm_decode_cmd(u64 curr_dec_cmd) {

    pnm_cmd_t cmd;

    // curr_dec_cmd is structured such that:
    // [63:60] is Opcode (Always CENT_OP_PNM i.e. 0xD)
    // [59:45] is Funcid (0=EXP, 1=RED, 2=ACC, TODO: add more PNM functions when more Funcids get defined)
    // [30:17] is RS (14-bit pointer)
    // [44:31] is RD (14-bit pointer)
    // rest of the bits are reserved and can be ignored
    
    cent_opcode_t raw_opcode = (cent_opcode_t)((curr_dec_cmd >> 60) & 0x0F);

    if (raw_opcode == CENT_OP_PNM) {
        cmd.opcode = CENT_OP_PNM;
    } else {
        cmd.opcode = CENT_OP_INVALID;
    }
    cmd.funcid = (cent_pnm_funcid_t)((curr_dec_cmd >> 45) & 0x1F); // 5 bits for Funcid
    cmd.rs = (curr_dec_cmd >> 17) & 0x3FFF;                        // 14 bits for RS
    cmd.rd = (curr_dec_cmd >> 31) & 0x3FFF;                        // 14 bits for RD

    return cmd;
}

// EXP: output[i] = e^(input[i])
void pnm_process_exp(const u16 input[16], u16 output[16]) {
    for (int i = 0; i < 16; i++) {
        // Convert BF16 input to float, compute exp, then convert back to BF16
        float in_f = bf16_to_float(input[i]);
        float out_f = expf(in_f);
        output[i] = float_to_bf16(out_f);
    }
}

// RED: output[0] = sum of all input[i]
void pnm_process_red(const u16 input[16], u16 output[16]) {
    float sum = 0.0f;
    for (int i = 0; i < 16; i++) {
        sum += bf16_to_float(input[i]);
    }
    output[0] = float_to_bf16(sum);

    // Duplicate the sum across all output elements so that i can be used for things like softmax normalization easily with other instructions like PNM div or EW_MUL
    for (int i = 1; i < 16; i++) {
        output[i] = output[0];
    }
}

// ACC: output[i] = output[i] + input[i] (accumulate input into output)
void pnm_process_acc(const u16 input[16], u16 output[16]) {
    for (int i = 0; i < 16; i++) {
        output[i] = float_to_bf16(bf16_to_float(input[i]) + bf16_to_float(output[i]));
    }
}

// SUB: output[i] = output[i] - input[i] (subtract input from output and store back in output)
void pnm_process_sub(const u16 input[16], u16 output[16]) {
    for (int i = 0; i < 16; i++) {
        output[i] = float_to_bf16(bf16_to_float(output[i]) - bf16_to_float(input[i]));
    }
}

// INV: output[i] = 1 / input[i]
void pnm_process_inv(const u16 input[16], u16 output[16]) {
    for (int i = 0; i < 16; i++) {
        float in_f = bf16_to_float(input[i]);
        float out_f = 1.0f / (in_f + 1e-6f); // ensure no divide-by-zero
        output[i] = float_to_bf16(out_f);
    }
}

// SQRT: output[i] = sqrt(input[i])
void pnm_process_sqrt(const u16 input[16], u16 output[16]) {
    for (int i = 0; i < 16; i++) {
        float in_f = bf16_to_float(input[i]);
        float out_f = sqrtf(in_f > 0.0f ? in_f : 0.0f); // ensure non-negative input for sqrt
        output[i] = float_to_bf16(out_f);
    }
}

// MULT: output[i] = output[i] * input[i] (element-wise multiplication of output and input, store back in output)
void pnm_process_mult(const u16 input[16], u16 output[16]) {
    for (int i = 0; i < 16; i++) {
        output[i] = float_to_bf16(bf16_to_float(input[i]) * bf16_to_float(output[i]));
    }
}

// DIV: output[i] = output[i] / input[i] (element-wise division of output by input, store back in output)
void pnm_process_div(const u16 input[16], u16 output[16]) {
    for (int i = 0; i < 16; i++) {
        float in_f = bf16_to_float(input[i]);
        float out_f = bf16_to_float(output[i]) / (in_f + 1e-6f); // ensure no divide-by-zero
        output[i] = float_to_bf16(out_f);
    }
}
