#include "utils.h"
#include "cent.h"

void print_vec(const u16* vec, int length) {
    xil_printf("{");
    for (int i = 0; i < length; i++) {
        xil_printf("0x%04X", vec[i]);
        if (i < length - 1) {
            xil_printf(", ");
        }
    }
    xil_printf("}\r\n");
}

void print_mat(const u16* mat, int rows, int cols) {
    xil_printf("{\r\n");
    for (int i = 0; i < rows; i++) {
        xil_printf("  {");
        for (int j = 0; j < cols; j++) {
            xil_printf("0x%04X", mat[i * cols + j]);
            if (j < cols - 1) {
                xil_printf(", ");
            }
        }
        xil_printf("}");
        if (i < rows - 1) {
            xil_printf(",");
        }
        xil_printf("\r\n");
    }
    xil_printf("}\r\n");
}

// helper to clean the hardware state before a test, can be useful when running multiple tests back to back to ensure a clean state for each test.
void cent_test_init() {
    // Soft reset interrupts the program execution pipeline bring hardware back to the IDLE state
    cent_soft_reset();
}