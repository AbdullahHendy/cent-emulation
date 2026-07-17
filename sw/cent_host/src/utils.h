#ifndef UTILS_H
#define UTILS_H

#include <xil_io.h>

void print_vec(const u16* vec, int length);
void print_mat(const u16* mat, int rows, int cols);

// helper to clean the hardware state before a test, can be useful when running multiple tests back to back to ensure a clean state for each test.
void cent_test_init();


#endif // UTILS_H