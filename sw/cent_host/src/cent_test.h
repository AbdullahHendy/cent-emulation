#ifndef CENT_TEST_H
#define CENT_TEST_H

#include <stdbool.h>
#include <xil_types.h>

// Example Matrix W and vector x and bias for testing GEMV with their results after applying activation function
// TEST 1: 16x16 W, 16x1 GEMV with ReLU Activation
extern const u16 W_16x16[16][16];
extern const u16 x_16x1[16];
extern const u16 bias_16x1[16];
extern const u16 expected_result_16x1_gemv_relu[16];

// TEST 2: 32x32 W, 32x1 GEMV with No Activation
extern const u16 W_32x32[32][32];
extern const u16 x_32x1[32];
extern const u16 bias_32x1[32];
extern const u16 expected_result_32x1_gemv[32];

// TEST 3: 128x128 W, 128x1 GEMV with No Activation
extern const u16 W_128x128[128][128];
extern const u16 x_128x1[128];
extern const u16 bias_128x1[128];
extern const u16 expected_result_128x1_gemv[128];

// TEST 4: 16x16 W, 16x1 GEMV with ReLU Activation plus PNM Accumulation +1
// Uses the same W, x, and bias as TEST 1 but with PNM Accumulation function (+1) after the GEMV and ReLU Activation
extern const u16 x_16x1_ones[16];
extern const u16 expected_result_16x1_gemv_relu_pnm_acc[16];

// Example Vector a and vector b for testing EW MUL with their results
// TEST 5: 16x1 a, 16x1 b, Element-wise Multiplication
extern const u16 a_16x1[16];
extern const u16 b_16x1[16];
extern const u16 expected_result_16x1_ew_mul[16];

bool cent_test_gemv_16x16_relu();
bool cent_test_gemv_32x32();
bool cent_test_gemv_128x128();
bool cent_test_gemv_16x16_relu_pnm_acc();
bool cent_test_ew_mul_16x1();

#endif // CENT_TEST_H