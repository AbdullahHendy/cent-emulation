#ifndef PNM_H
#define PNM_H

#include <xil_io.h>
#include "cent.h"

// PNM command defined as: PNM Funcid, Rd, Rs
typedef struct {
    cent_opcode_t     opcode;  // [63:60] 4 bits (Should always decode to CENT_OP_PNM)
    cent_pnm_funcid_t funcid;  // [49:45] 5 bits 
    u16               rd;      // [44:31] 14 bits
    u16               rs;      // [30:17] 14 bits
} pnm_cmd_t;


// Decode the raw curr_dec_cmd value read from the IFACE_CTR_CURR_DEC_CMD_BOT_REG and IFACE_CTR_CURR_DEC_CMD_TOP_REG registers into a pnm_cmd_t struct
pnm_cmd_t pnm_decode_cmd(u64 curr_dec_cmd);

// Functions for the PNM actual logic
// TODO: add more functions when more PNM Funcids get defined
void pnm_process_exp(const u16 input[16], u16 output[16]);
void pnm_process_red(const u16 input[16], u16 output[16]);
void pnm_process_acc(const u16 input[16], u16 output[16]);
void pnm_process_sub(const u16 input[16], u16 output[16]);
void pnm_process_inv(const u16 input[16], u16 output[16]);
void pnm_process_sqrt(const u16 input[16], u16 output[16]);
void pnm_process_mult(const u16 input[16], u16 output[16]);
void pnm_process_div(const u16 input[16], u16 output[16]);


// Helper function for BF16 to float conversion and vice versa, since R5 does not have native BF16 support.
// BF16 is just the top 16 bits of a standard IEEE 754 32-bit float. (both have 1 sign bit and 8 exponent bits)
static float bf16_to_float(u16 bf16_val) {
    u32 val = ((u32)bf16_val) << 16;
    float f;
    memcpy(&f, &val, sizeof(float));
    return f;
}

static u16 float_to_bf16(float f_val) {
    u32 val;
    memcpy(&val, &f_val, sizeof(float));
    // Round to nearest even: ((val >> 16) & 1u) determines if the future bf16 value is odd or even
    // if odd it becomes val += 0x8000u (increment upper 16 bits, round up), if even it becomes val += 0x7FFFu (do nothing to upper 16 bits, round down)
    val += 0x7FFFu + ((val >> 16) & 1u); 
    return (u16)(val >> 16);
}

#endif // PNM_H