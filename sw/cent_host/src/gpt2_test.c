#include "gpt2_test.h"
#include "utils.h"
#include "cent.h"
#include "pnm.h"
#include <math.h>
#include <sleep.h>
#include <stdio.h>
#include <xil_types.h>

/*
 *    Check cent_test.c functons for more details on the testing approach. We will ommit detailed comments in this file.
 */

const u16 x0[128] = {0xbd53, 0xbdaf, 0xbc5d, 0x3d34, 0xbd06, 0xbe26, 0x3c5a, 0xbdba, 0xbd9c, 0x3d00, 0x3e1e, 0x3d33, 0x3de2, 0x3ba0, 0x3ca4, 0x3c67, 0xbcde, 0x3b00, 0xbe0a, 0xbd0c, 0x3c6b, 0xbe09, 0x3efa, 0x3ca1, 0xbd82, 0xbdeb, 0x3dfc, 0xbca4, 0x3cf8, 0xbda8, 0x3dd6, 0xbe2a, 0xbc18, 0x3d34, 0x3e00, 0xbdae, 0x3d56, 0xbd95, 0x3d85, 0x3d80, 0xbdde, 0x3cd6, 0xbbd8, 0x3e33, 0xbd38, 0x3cb2, 0xbd31, 0x3ea8, 0xbdc7, 0xbe0f, 0xbd0d, 0x3b40, 0xbd0e, 0x3d86, 0x3d76, 0xbca4, 0x3b7e, 0x3bc8, 0xbd30, 0xbdb0, 0xbf95, 0x3ca4, 0x3e47, 0xbd8e, 0xbdd0, 0x3ec0, 0x3c8b, 0x3dfb, 0xbd65, 0xbb90, 0xbcd8, 0x3bea, 0x3ce3, 0xbd8c, 0xbcab, 0xbd13, 0xbe4f, 0xbc8e, 0xbdff, 0x3bb0, 0x3d10, 0x3e24, 0x3e35, 0x3da2, 0x3d60, 0xbcca, 0x3d07, 0x3c61, 0xba9c, 0x3d48, 0x3d90, 0xbd02, 0x3d77, 0x3d7c, 0x3dd2, 0x3de9, 0x3cc4, 0x3e16, 0xbcc4, 0x3cda, 0xbdf8, 0xbe3c, 0x3e0b, 0x3dcd, 0x3d35, 0xbc2a, 0xbd46, 0x3db6, 0xbd12, 0x3e07, 0xbe28, 0xbd23, 0xbdbb, 0xbd52, 0xbd95, 0x3c9d, 0x3d8c, 0xbe9d, 0x3d28, 0x3b39, 0x3d4f, 0xbd90, 0xbd8c, 0xbdf9, 0x3dea, 0x3dd4, 0x3dad, 0x3dca};
const u16 all_128[128] = {0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300, 0x4300};
const u16 all_0[128] = {0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000};
const u16 ln1_out_torch[128] = {0xbe83, 0xbf1d, 0xbe3a, 0x3ed4, 0xbe1f, 0xbf8b, 0x3e44, 0xbf47, 0xbf21, 0x3e3a, 0x3f94, 0x3e8d, 0x3f81, 0x3ea6, 0x3d7a, 0x3dbb, 0xbe8d, 0x3df8, 0xbf83, 0xbec8, 0x3e58, 0xbf8f, 0x403c, 0x3e30, 0xbef0, 0xbf57, 0x3f5e, 0xbe92, 0x3eed, 0xbf1b, 0x3f2f, 0xbf97, 0xbe7f, 0x3e8f, 0x3f83, 0xbf07, 0x3ef5, 0xbf16, 0x3f16, 0x3ecf, 0xbf4f, 0x3d09, 0xbea0, 0x3f9e, 0xbef2, 0x3dc1, 0xbe85, 0x4005, 0xbf4d, 0xbfa7, 0xbec1, 0x3d73, 0xbe0a, 0x3ef7, 0x3f0a, 0xbeb0, 0xbd2b, 0x3e74, 0xbec1, 0xbf0b, 0xc0f1, 0x3e30, 0x3fad, 0xbf2a, 0xbf2a, 0x4012, 0x3e86, 0x3f65, 0xbec6, 0xbeb1, 0xbe91, 0x3e40, 0x3e51, 0xbf44, 0xbe37, 0xbdb2, 0xbfda, 0x3dfa, 0xbf74, 0x3d93, 0x3d66, 0x3f8c, 0x3fac, 0x3f35, 0x3edd, 0xbd67, 0x3ef8, 0x3dde, 0x3dd5, 0x3f27, 0x3f14, 0xbcca, 0x3eab, 0x3ee1, 0x3f58, 0x3f3a, 0x3e24, 0x3f6d, 0xbe93, 0xbe0c, 0xbf3d, 0xbfa3, 0x3f8a, 0x3f58, 0x3ee5, 0xbd81, 0xbeab, 0x3f4c, 0xbde8, 0x3f91, 0xbf21, 0xbe11, 0xbf52, 0xbe77, 0xbf3d, 0x3e83, 0x3f0b, 0xc017, 0x3ee8, 0x3c6e, 0x3eeb, 0xbf03, 0xbedf, 0xbf92, 0x3f4d, 0x3f81, 0x3f45, 0x3ed2};
const u16 q_out_torch[128] = {0xbfad, 0x3fc9, 0xbed7, 0xbfc2, 0x3f8f, 0x3f1e, 0x3f54, 0x3eda, 0x3f5e, 0xbccb, 0x3fae, 0x3f23, 0xbd9f, 0xbfce, 0xbd36, 0x3f84, 0x3d66, 0x3f66, 0xbed3, 0xbfa7, 0x3fbc, 0x3eb3, 0x3e3d, 0x3f4a, 0x3f43, 0xbe23, 0xbfa4, 0x3fe7, 0xbfa9, 0xbf44, 0xbece, 0xbf82, 0xbf88, 0xbf8c, 0xc005, 0xbe89, 0x3fbf, 0xbf12, 0xbfba, 0x3f95, 0x3ffe, 0x3f4d, 0x3f30, 0x3fcb, 0x3d87, 0x3ded, 0xbf08, 0x3eaa, 0x3cfd, 0x3e4c, 0x3e91, 0x3ffd, 0xbf56, 0xbf0b, 0x4004, 0x3fa6, 0xbf5d, 0xbf89, 0xbf48, 0xbd8c, 0x3ec8, 0xbe90, 0xbe8e, 0x3fde, 0x3f18, 0xbf52, 0x3eb2, 0xbf5d, 0x3e81, 0xbf39, 0xbe18, 0x3f1e, 0x3f6b, 0x3eca, 0xbf2a, 0x3fbb, 0x3ee3, 0xbf48, 0x3ef5, 0x3f66, 0x3f90, 0xbf5f, 0xbfdb, 0xbf65, 0x3ec7, 0x3ee3, 0x3ebe, 0x3f38, 0x3ea5, 0xbf4c, 0x3ed9, 0x3efd, 0xbfc3, 0xbfa8, 0x3f2a, 0x3db4, 0xbea9, 0x3f2c, 0xbfb0, 0x3ec4, 0xbe30, 0xbe8f, 0xbfb8, 0xbf5e, 0x3fb8, 0xbf4f, 0x3e21, 0xbf7a, 0xbf48, 0xbfb1, 0x3fe0, 0x3f81, 0xbf49, 0xbfef, 0xbf5f, 0xbcc2, 0x3d06, 0xbe1f, 0xc008, 0x3f81, 0x3fa3, 0xbfb6, 0xc011, 0x3f20, 0xbe2c, 0xbeb2, 0x3ec5, 0xbf93};
const u16 k_out_torch[128] = {0x3f75, 0xbeb1, 0x3fc1, 0x3d1d, 0x3f13, 0xbe0f, 0xbf4b, 0x3fea, 0x3f5b, 0xbf69, 0x3f7e, 0xbebe, 0xbfa9, 0xbff4, 0xbfdf, 0xbed6, 0xbf0e, 0xbf3f, 0xc011, 0xbe14, 0xbecf, 0x4017, 0xbf43, 0x3f4d, 0x3f66, 0xbefe, 0x3ffe, 0x3ed8, 0x3de9, 0xbf96, 0xbf93, 0xbedb, 0xbece, 0xbf20, 0xbe9c, 0x3f3f, 0x401a, 0xbea1, 0x3f9b, 0x3f18, 0xbea0, 0xbf51, 0xbfde, 0xbe17, 0x3ec0, 0xbfd1, 0xbf94, 0xbe47, 0x3f64, 0x3fba, 0xbc46, 0x3f27, 0xbf8e, 0x3fe7, 0xbf35, 0xbfa8, 0xbf8a, 0x3e1e, 0xbf4e, 0x3f14, 0x3e88, 0xbfa7, 0xbe27, 0x3f6f, 0x3e40, 0x3ed4, 0x3f1b, 0xbf06, 0xbe1e, 0x3eb3, 0xbf30, 0xbf7b, 0xbd5f, 0xbebd, 0x3ee7, 0xbf75, 0x3dbf, 0x3ea4, 0x3f00, 0xbe44, 0xbf8e, 0x3eae, 0x3f91, 0xbe53, 0x3f11, 0x3ec2, 0xbe01, 0xbf24, 0x3e0d, 0x3e37, 0x3edd, 0xbdbc, 0x3dbe, 0x3ea1, 0x3f11, 0x3f5d, 0x3f40, 0x3eea, 0xbf49, 0x3fc8, 0x3f4b, 0xbfee, 0x3f52, 0xbf85, 0xbdac, 0x3f43, 0x3f1b, 0x3fe9, 0x3fd2, 0x3f7b, 0xbf9f, 0x3fce, 0x3f59, 0x3ee7, 0x3ed9, 0xbf75, 0xbe2d, 0xbee6, 0xbfc8, 0xbfbc, 0xbf81, 0x3f65, 0xbebb, 0xbfc6, 0x3f59, 0xbfc3, 0x3f82, 0x3f28};
const u16 v_out_torch[128] = {0xbebb, 0x3c20, 0x3d5e, 0xbd7c, 0x3d67, 0xbd6e, 0xbd4c, 0xbde0, 0x3de2, 0xbe06, 0xbd58, 0x3dd6, 0xbb56, 0xbde5, 0x3e07, 0xbe2c, 0xbdbe, 0xbd03, 0x3e90, 0xbd3d, 0x3d92, 0x3d88, 0x3da0, 0x3e5a, 0xbde6, 0xbe99, 0xbcbe, 0x3db5, 0x3e65, 0xbd04, 0x3d40, 0xbdc9, 0xbcd2, 0x3d30, 0x3d06, 0xbd5a, 0xbc63, 0xbd50, 0xbdd0, 0xbdd1, 0xbd8d, 0xbe45, 0x3d80, 0xbe00, 0x3b49, 0xbd9a, 0x3e04, 0x3c52, 0x3e4c, 0xbe37, 0x3e03, 0xbd74, 0x3d42, 0x3e86, 0xbc5c, 0xbe70, 0xbe0f, 0xbdfe, 0xbe20, 0xbd46, 0xbea7, 0x3db6, 0xba44, 0x3d78, 0x3e9c, 0x3e1a, 0x3cc1, 0x3d84, 0xbdce, 0x3dec, 0xbdb1, 0xbd51, 0x3dc6, 0xbcd6, 0xbe8c, 0xbe4f, 0x3e47, 0xbe4e, 0x3d57, 0xbdc3, 0xbe01, 0x3eaa, 0x3e47, 0xbe39, 0xbe8a, 0x3e21, 0x3ded, 0xbed1, 0x3e49, 0xbdb4, 0xbe66, 0xbc81, 0x3e3d, 0x3d67, 0x3e1c, 0x3e05, 0xbcbd, 0x3de0, 0xbcb3, 0xbdd3, 0x3cc6, 0x3df3, 0xbbeb, 0x3dc9, 0x3cdf, 0x3d94, 0x3d99, 0x3e05, 0xbe07, 0x3e0a, 0xbd9c, 0x3e17, 0x3d01, 0x3cc2, 0xbaf4, 0x3cad, 0xbddb, 0x3d98, 0xbdf1, 0xbeb0, 0x3c8f, 0x3dd0, 0x3e2b, 0xbeb3, 0xbd50, 0xbe58, 0x3e16, 0x3da8};

bool cent_test_nanogpt2_block0_layernorm1() {

    xil_printf("\r\n--- Running GPT2 Block 0 LayerNorm1 Test (PNM) ---\r\n");


    // Steps to test layernorm1 in transformer block 0:
    // 1) Write the constant vector of all 128 elements as 128.0 to be used for mean and variance calculations to shared buffer index 0-7
    // 1) Write the input vector x0 (128 elements) to shared buffer index 8-15
    // 2) Write the layernorm1 parameters (ln1_w at shared buffer index 16-23 and ln1_b at shared buffer index 24-31) respectively
    // 3) Write the program_instructions as an array of cent_instr_t to instruction buffer to do layernorm1 on x0:
    //    a) Mean calculation
    //    b) Mean centering
    //    c) Variance calculation and stddev calculation
    //    d) stddev normalization
    //    e) Scaling and shifting with ln1_w and ln1_b
    // 4) Set control registers
    // 5) Fire doorbell

    // Program is as follows:
    // Mean calculation:
    // 1x PNM with PNM_FUNCID_RED with OPsize=8 to calculate partial sums for mean and write to shared buffer index 32-39 (since we have 8 partial sums for 128 elements with OPsize=8)
    // 7x PNM with PNM_FUNCID_ACC with OPsize=1 to accumulate the partial sums all into shared buffer index 32 (the final sum)
    // 1x PNM with PNM_FUNCID_DIV with OPsize=1 to divide by the constant 128.0 at index 0 to get the final mean at index 32
    // Mean centering:
    // 1x PNM with PNM_FUNCID_ACC with OPsize=8 to copy x0 from index 8-15 to index 40-47 to do mean centering without losing the original x0
    // 8x PNM with PNM_FUNCID_SUB with OPsize=1 to subtract the mean at index 32 from each of the 128 elements at index 40-47 and write the mean centered results back to index 40-47
    // Variance calculation:
    // 1x PNM with PNM_FUNCID_ACC with OPsize=8 to copy the mean centered vector from index 40-47 to index 48-55 to do variance calculation without losing the mean centered vector
    // 1x PNM with PNM_FUNCID_MULT with OPsize=8 to square each of the mean centered elements at index 48-55 and write the squared results to index 48-55
    // 1x PNM with PNM_FUNCID_RED with OPsize=8 to calculate partial sums for variance and write to shared buffer index 56-63 (since we have 8 partial sums for 128 elements with OPsize=8)
    // 7x PNM with PNM_FUNCID_ACC with OPsize=1 to accumulate the partial sums all into shared buffer index 56 (the final variance sum)
    // 1x PNM with PNM_FUNCID_DIV with OPsize=1 to divide the variance sum at index 56 by the constant 128.0 at index 0 to get the final variance at index 56
    // 1x PNM with PNM_FUNCID_SQRT with OPsize=1 to calculate the stddev of the variance at index 56 and write to index 56
    // Stddev normalization:
    // 8x PNM with PNM_FUNCID_DIV with OPsize=1 to divide each of the mean centered elements at index 40-47 by the stddev at index 56 and write the stddev normalized results to index 40-47
    // Scaling and shifting:
    // 1x PNM with PNM_FUNCID_MULT with OPsize=8 to multiply each of the stddev normalized elements at index 40-47 with the corresponding ln1_w scaling factor at index 16-23 and write the results to index 40-47
    // 1x PNM with PNM_FUNCID_ACC with OPsize=8 to add the ln1_b shifting factor at index 24-31 to each of the scaled elements at index 40-47 and write the final layernorm results to index 40-47

    xil_printf("Loading constant vector, input vector x0 and layernorm1 parameters ln1_w and ln1_b...\r\n");

    // Load constant vector, input vector x0 and layernorm1 parameters ln1_w and ln1_b to shared buffer index 0-31
    for (int i = 0; i < 8; i++) {
        cent_write_shared_buffer(0 + i, &all_128[16 * i]); // index 0-7 for constant vector of all 128.0
        cent_write_shared_buffer(8 + i, &x0[16 * i]); // index 8-15 for input vector x0
        cent_write_shared_buffer(16 + i, &ln1_w[16 * i]); // index 16-23 for ln1_w
        cent_write_shared_buffer(24 + i, &ln1_b[16 * i]); // index 24-31 for ln1_b
    }

    cent_instr_t program_instructions[40];
    u32 program_length = 40;
    u32 program_start_index = 0;

    program_instructions[0] = build_nop(); // First instruction is NOP since we are only testing PNM functionality here and want to isolate it as much as possible, the second instruction will be the PNM instruction to perform mean calculation for layernorm1

    program_instructions[1] = build_pnm(8, PNM_FUNCID_RED, 32, 8); // Mean calculation partial sum

    for (int i = 1; i < 8; i++) {
        program_instructions[1 + i - 1] = build_pnm(1, PNM_FUNCID_ACC, 32, 32 + i); // Accumulate mean partial sums
    }

    program_instructions[8] = build_pnm(1, PNM_FUNCID_DIV, 32, 0); // Divide by 128.0 to get mean

    program_instructions[9] = build_pnm(8, PNM_FUNCID_ACC, 40, 8); // Copy x0 to index 40-47 for mean centering

    for (int i = 0; i < 8; i++) {
        program_instructions[10 + i] = build_pnm(1, PNM_FUNCID_SUB, 40 + i, 32); // Subtract mean from x0 for mean centering
    }

    program_instructions[18] = build_pnm(8, PNM_FUNCID_ACC, 48, 40); // Copy mean centered vector to index 48-55 for variance calculation

    program_instructions[19] = build_pnm(8, PNM_FUNCID_MULT, 48, 48); // Square mean centered elements for variance calculation

    program_instructions[20] = build_pnm(8, PNM_FUNCID_RED, 56, 48); // Variance calculation partial sum

    for (int i = 1; i < 8; i++) {
        program_instructions[21 + i - 1] = build_pnm(1, PNM_FUNCID_ACC, 56, 56 + i); // Accumulate variance partial sums
    }

    program_instructions[28] = build_pnm(1, PNM_FUNCID_DIV, 56, 0); // Divide by 128.0 to get variance

    program_instructions[29] = build_pnm(1, PNM_FUNCID_SQRT, 56, 56); // Take sqrt of variance to get stddev

    for (int i = 0; i < 8; i++) {
        program_instructions[30 + i] = build_pnm(1, PNM_FUNCID_DIV, 40 + i, 56); // Divide mean centered elements by stddev for stddev normalization
    }

    program_instructions[38] = build_pnm(8, PNM_FUNCID_MULT, 40, 16); // Scale with ln1_w

    program_instructions[39] = build_pnm(8, PNM_FUNCID_ACC, 40, 24); // Shift with ln1_b to get final layernorm output

    cent_program_t program = {
        .instructions = program_instructions,
        .length = program_length,
        .start_index = program_start_index
    };

    xil_printf("Loading program into instruction buffer\r\n");
    cent_load_program(&program);

    xil_printf("Writing control registers to start execution\r\n");
    cent_write_ctrl(0x3); // Enable and Irq Enable
    cent_write_cmd_base(program.start_index * sizeof(cent_instr_t));
    cent_write_cmd_len(program.length);
    cent_fire_doorbell();

    xil_printf("Polling status register...\r\n");
    u32 status;
    do {
        status = cent_read_status();
    } while (status & 0x2);

    if (status & 0x0C) {
        xil_printf("HARDWARE ERROR ABORT! Status: 0x%08X\r\n", status);
        cent_write_status(status);
        return false;
    }

    u32 perf = cent_read_perf();
    xil_printf("Performance in cycles: %u\r\n", perf);

    cent_write_status(status);

    u16 result[128];
    for (int i = 0; i < 8; i++) {
        cent_read_shared_buffer(40 + i, &result[16 * i]); // Read final layernorm output from index 40-47
    }

    xil_printf("Block 0 - LayerNorm1 Result:\r\n");
    print_vec(result, 128);

    // Verify results
    bool passed = true;
    const float tol = 0.5f; // Specifically for layernorm GPT2 model
    for (int i = 0; i < 128; i++) {
        float err = fabsf(bf16_to_float(result[i]) - bf16_to_float(ln1_out_torch[i]));
        printf("result[%d] = 0x%04X, expected = 0x%04X, abs error = %f\r\n", i, result[i], ln1_out_torch[i], err);
        if (err > tol) {
            passed = false;
        }
    }

    if (passed) {
        printf("GPT2 Block 0 - LayerNorm1 Test Passed with max error < %f!!\r\n", tol);
    } else {
        xil_printf("GPT2 Block 0 - LayerNorm1 Test Failed!! See output above.\r\n");
    }

    return passed;
}

bool cent_test_nanogpt2_block0_attention_proj() {
    // Look at cent_test.c, especially cent_test_gemv_128x128() for reference on how to store input vector, weight matrix, etc.
    // The cent_test_gemv_128x128() test covers 1 GEMV only but idea is the same but for 3 GEMVs.


    // In this test, we will use the torch output of layernorm1 as the input to the attention projection

    xil_printf("\r\n--- Running GPT2 Block 0 Attention Projection Test (PIM) ---\r\n");

    xil_printf("Loading input vector (output of layernorm1) and weight matrices for attention projection...\r\n");
    // output vec has 8 subvectors, write to shared buffer index 0-7
    for (int i = 0; i < 8; i++) {
        cent_write_shared_buffer(i, &ln1_out_torch[16 * i]);
    }

    // Write Q, K, V matrices in "row-major tile" order in shared buffer for OPsize=64 writes.
    // Q uses SBUF 8-1031, K uses 1032-2055, V uses 2056-3079.
    for (int r = 0; r < 16; r++) { // 16 rows per tile
        for (int h_tile = 0; h_tile < 8; h_tile++) { // 8 horizontal tiles
            for (int v_tile = 0; v_tile < 8; v_tile++) { // 8 vertical tiles
                int w_row = r + (16 * h_tile);
                int w_col = v_tile * 16;

                // SBUF indices calculated to pack all 64 tiles linearly per row
                int q_sbuf_idx = 8 + (64 * r) + (h_tile * 8) + v_tile;
                int k_sbuf_idx = 1032 + (64 * r) + (h_tile * 8) + v_tile;
                int v_sbuf_idx = 2056 + (64 * r) + (h_tile * 8) + v_tile;

                cent_write_shared_buffer(q_sbuf_idx, &q_proj[w_row][w_col]);
                cent_write_shared_buffer(k_sbuf_idx, &k_proj[w_row][w_col]);
                cent_write_shared_buffer(v_sbuf_idx, &v_proj[w_row][w_col]);
            }
        }
    }

    // Zero bias vector to initialize registers in PIM PU
    for (int i = 0; i < 8; i++) {
        cent_write_shared_buffer(3080 + i, &all_0[16 * i]); // bias vector at index 3080-3087
    }

    // Build program:
    // 48x WR_SBK
    //          16 WR_SBK with OPsize=8 for Wq RO=0,CO=0-63
    //          16 WR_SBK with OPsize=8 for Wk RO=1,CO=0-63
    //          16 WR_SBK with OPsize=8 for Wv RO=2,CO=0-63
    // 1x  WR_GB idx 0-7 for input vector (output of layernorm1)
    // 24x WR_BIAS to regids 0-7, 8-15, 16-23 for q_proj, k_proj, v_proj respectively
    // 24x MAC_ABK
    //          8 MAC_ABK with OPsize=8 RO=0,CO=0,8,..,56,GB=0 regid:0-7 for q_proj
    //          8 MAC_ABK with OPsize=8 RO=1,CO=0,8,..,56,GB=0 regid:8-15 for k_proj
    //          8 MAC_ABK with OPsize=8 RO=2,CO=0,8,..,56,GB=0 regid:16-23 for v_proj
    // 24x RD_MAC to read q_proj, k_proj, v_proj results from regid 0-7, 8-15, 16-23 to shared buffer index 3088-3095, 3096-3103, 3104-3111 respectively
    cent_instr_t program_instructions[121];
    u32 program_length = 121;
    u32 program_start_index = 0;

    int idx = 0;

    // Wq WR_SBK
    for (int i = 0; i < 16; i++) {
        program_instructions[idx++] = build_wr_sbk(0, 64, i, 0, 0, 8 + (64 * i));       // Q -> RO=0
        program_instructions[idx++] = build_wr_sbk(0, 64, i, 1, 0, 1032 + (64 * i));    // K -> RO=1
        program_instructions[idx++] = build_wr_sbk(0, 64, i, 2, 0, 2056 + (64 * i));    // V -> RO=2
    }

    program_instructions[idx++] = build_wr_gb(0, 8, 0, 0);

    for (int i = 0; i < 8; i++) {
        program_instructions[idx++] = build_wr_bias(0, 3080 + i, 0 + i);  // Regs 0-7 for Q
        program_instructions[idx++] = build_wr_bias(0, 3080 + i, 8 + i);  // Regs 8-15 for K
        program_instructions[idx++] = build_wr_bias(0, 3080 + i, 16 + i); // Regs 16-23 for V
    }

    for (int i = 0; i < 8; i++) {
        // Q_proj: Compute RO=0, accumulate in Regs 0-7
        program_instructions[idx++] = build_mac_abk(0, 8, 0, i * 8, 0, MAC_OP_GEMV, 0 + i);
        // K_proj: Compute RO=1, accumulate in Regs 8-15
        program_instructions[idx++] = build_mac_abk(0, 8, 1, i * 8, 0, MAC_OP_GEMV, 8 + i);
        // V_proj: Compute RO=2, accumulate in Regs 16-23
        program_instructions[idx++] = build_mac_abk(0, 8, 2, i * 8, 0, MAC_OP_GEMV, 16 + i);
    }

    for (int i = 0; i < 8; i++) {
        program_instructions[idx++] = build_rd_mac(0, 3088 + i, 0 + i);  // Q Results
        program_instructions[idx++] = build_rd_mac(0, 3096 + i, 8 + i);  // K Results
        program_instructions[idx++] = build_rd_mac(0, 3104 + i, 16 + i); // V Results
    }

    cent_program_t program = {
        .instructions = program_instructions,
        .length = program_length,
        .start_index = program_start_index
    };

    xil_printf("Loading program into instruction buffer\r\n");
    cent_load_program(&program);

    xil_printf("Writing control registers to start execution\r\n");
    cent_write_ctrl(0x1);
    cent_write_cmd_base(program.start_index * sizeof(cent_instr_t));
    cent_write_cmd_len(program.length);
    cent_fire_doorbell();

    xil_printf("Polling status register...\r\n");
    u32 status;
    do {
        status = cent_read_status();
    } while (status & 0x2);

    u32 perf = cent_read_perf();
    xil_printf("Performance in cycles: %u\r\n", perf);

    cent_write_status(status);

    u16 q_result[128];
    u16 k_result[128];
    u16 v_result[128];
    for (int i = 0; i < 8; i++) {
        cent_read_shared_buffer(3088 + i, &q_result[16 * i]);
        cent_read_shared_buffer(3096 + i, &k_result[16 * i]);
        cent_read_shared_buffer(3104 + i, &v_result[16 * i]);
    }

    xil_printf("Block 0 - Attention Projection Results (Q, K, V):\r\n");

    // Verify
    bool passed = true;
    const float tol = 0.0f; // PIM GEMV only operations should completely match torch output for attention projection
    for (int i = 0; i < 128; i++) {
        float q_err = fabsf(bf16_to_float(q_result[i]) - bf16_to_float(q_out_torch[i]));
        float k_err = fabsf(bf16_to_float(k_result[i]) - bf16_to_float(k_out_torch[i]));
        float v_err = fabsf(bf16_to_float(v_result[i]) - bf16_to_float(v_out_torch[i]));
        printf("q_result[%d] = 0x%04X, expected = 0x%04X, abs error = %f\r\n", i, q_result[i], q_out_torch[i], q_err);
        printf("k_result[%d] = 0x%04X, expected = 0x%04X, abs error = %f\r\n", i, k_result[i], k_out_torch[i], k_err);
        printf("v_result[%d] = 0x%04X, expected = 0x%04X, abs error = %f\r\n", i, v_result[i], v_out_torch[i], v_err);
        if (q_err > tol || k_err > tol || v_err > tol) {
            passed = false;
        }
    }
    if (passed) {
        printf("GPT2 Block 0 - Attention Projection Test Passed with max error < %f!!\r\n", tol);
    } else {
        xil_printf("GPT2 Block 0 - Attention Projection Test Failed!! See output above.\r\n");
    }

    return passed;
}
