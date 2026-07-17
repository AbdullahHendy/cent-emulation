#include "cent_test.h"
#include "gpt2_test.h"
#include <cent.h>
#include "utils.h"
#include <sleep.h>


int main()
{
    // Latest ver id is 05022026, assert we are on latest.
    u32 version = cent_read_ver_id();
    if (version != 0x07152026) {
        xil_printf("Error: Incompatible version of CENT detected! Expected 0x07152026 but got 0x%08X\r\n", version);
        return -1;
    } else {
        xil_printf("CENT Version ID: 0x%08X\r\n", version);
    }

    // // TODO: Figure out a better mailbox way for R5 to notify host about when it's ready instead of just sleeping for some time
    msleep(500); // Sleep for 500 ms to give PNM R5 to setup interrupt GIC in case the cent program has early PNM instruction that need interrupt handling

    cent_test_gemv_16x16_relu_pnm_acc();

    msleep(500);
    cent_test_init();
    cent_test_ew_mul_16x1();

    msleep(500);
    cent_test_init();
    cent_test_nanogpt2_block0_layernorm1();

    msleep(500);
    cent_test_init();
    cent_test_nanogpt2_block0_attention_proj();

    return 0;
}
