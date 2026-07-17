#ifndef GPT2_TEST_H
#define GPT2_TEST_H

#include <stdbool.h>
#include <xil_types.h>

// GPT2 input vector (128x1), x0 = tok_emb + pos_emb for one token. Input to transformer block 0 and expected outputs
extern const u16 x0[128];
extern const u16 ln1_out_torch[128];
extern const u16 q_out_torch[128];
extern const u16 k_out_torch[128];
extern const u16 v_out_torch[128];

extern const u16 all_128[128]; // Helper vector of all 128 elements as 128.0 since its a useful constant for various calculations.
extern const u16 all_0[128]; // Helper vector of all 128 elements as 0.0 which can be useful for various calculations.

// GPT2 transformer block 0 parameters for testing
extern const u16 ln1_w[128];
extern const u16 ln1_b[128];
extern const u16 causal_mask[256][256];
extern const u16 q_proj[128][128];
extern const u16 k_proj[128][128];
extern const u16 v_proj[128][128];
extern const u16 out_proj[128][128];
extern const u16 ln2_w[128];
extern const u16 ln2_b[128];
extern const u16 ff_net_0_w[512][128];
extern const u16 ff_net_0_b[512];
extern const u16 ff_net_2_w[128][512];
extern const u16 ff_net_2_b[128];

bool cent_test_nanogpt2_block0_layernorm1();
bool cent_test_nanogpt2_block0_attention_proj();

#endif // GPT2_TEST_H