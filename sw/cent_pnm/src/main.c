#include "pnm.h"
#include "cent.h"
#include <stdbool.h>
#include "xinterrupt_wrap.h"
#include "xparameters.h"
#include "xil_printf.h"

#define PNM_IRQ_ID   122 // From hardware, pl_ps_irq0 [1]
#define PNM_IRQ_PRIO 0x8

XScuGic InterruptController; // The interrupt controller instance

volatile bool pnm_request_pending = false;

void pnm_irq_handler(void *CallbackRef) {

    // read cent status register to check if the interrupt is for a pending PNM request (pnm_req_sticky bit is set, bit 4)
    u32 status = cent_read_status();
    if (status & 0x10) {

        // Set the pnm_request_pending flag to notify main loop.
        pnm_request_pending = true;

        // Clear the pnm_req_sticky bit by writing 1 to it (clears the interrupt in turn)
        cent_write_status(0x10);
    }

}

int pnm_interrupt_setup() {
    int Status;
    u32 IntrId;
    UINTPTR IntcBaseAddr;

    Status = XGetEncodedIntrId(PNM_IRQ_ID, XINTR_IS_LEVEL_TRIGGERED, XINTR_IS_SPI, XINTC_TYPE_IS_SCUGIC, &IntrId);
    if (Status != XST_SUCCESS) {
        xil_printf("Failed to get encoded interrupt ID for PNM_IRQ_ID %d\r\n", PNM_IRQ_ID);
        return XST_FAILURE;
    }

    IntcBaseAddr = XGetEncodedIntcBaseAddr(XPAR_XSCUGIC_0_BASEADDR, XINTC_TYPE_IS_SCUGIC);

    Status = XSetupInterruptSystem(&InterruptController, (void *)pnm_irq_handler, IntrId, IntcBaseAddr, PNM_IRQ_PRIO);
    if (Status != XST_SUCCESS) {
        xil_printf("Failed to setup interrupt system for PNM_IRQ_ID %d\r\n", PNM_IRQ_ID);
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

int main()
{
    int Status;
    Status = pnm_interrupt_setup();
    if (Status != XST_SUCCESS) {
        xil_printf("Interrupt setup failed\r\n");
        return XST_FAILURE;
    }

    while(true) {
        if (pnm_request_pending) {
            // Read the current decoded command from the control registers
            u64 curr_dec_cmd = cent_read_curr_dec_cmd();
            pnm_cmd_t current_pnm_cmd = pnm_decode_cmd(curr_dec_cmd);

            if (current_pnm_cmd.opcode != CENT_OP_PNM) {
                xil_printf("FATAL CORRUPTION! received command should have PNM OPcode but has 0x%X: \r\n", current_pnm_cmd.opcode);
                return 1;
            }

            // Read the shared buffer data based on the RS field of the current_pnm_cmd
            u16 data_in[16];
            cent_read_shared_buffer(current_pnm_cmd.rs, data_in);

            // Process the data based on the opcode
            u16 data_out[16];
            switch (current_pnm_cmd.funcid) {
                case PNM_FUNCID_EXP:
                    pnm_process_exp(data_in, data_out);
                    break;
                case PNM_FUNCID_RED:
                    pnm_process_red(data_in, data_out);
                    break;
                case PNM_FUNCID_ACC:
                    // In the case of ACC, we need the value in Rd to do accumulation.
                    cent_read_shared_buffer(current_pnm_cmd.rd, data_out);
                    pnm_process_acc(data_in, data_out); // data_out = data_out + data_in
                    break;
                case PNM_FUNCID_SUB:
                    // In the case of SUB, we need the value in Rd to do subtraction.
                    cent_read_shared_buffer(current_pnm_cmd.rd, data_out);
                    pnm_process_sub(data_in, data_out); // data_out = data_out - data_in
                    break;
                case PNM_FUNCID_INV:
                    pnm_process_inv(data_in, data_out);
                    break;
                case PNM_FUNCID_SQRT:
                    pnm_process_sqrt(data_in, data_out);
                    break;
                case PNM_FUNCID_MULT:
                    // In the case of MULT, we need the value in Rd to do multiplication.
                    cent_read_shared_buffer(current_pnm_cmd.rd, data_out);
                    pnm_process_mult(data_in, data_out); // data_out = data_out * data_in (element-wise multiplication)
                    break;
                case PNM_FUNCID_DIV:
                    // In the case of DIV, we need the value in Rd to do division.
                    cent_read_shared_buffer(current_pnm_cmd.rd, data_out);
                    pnm_process_div(data_in, data_out); // data_out = data_out / data_in (element-wise division)
                    break;
                default:
                    xil_printf("Invalid PNM opcode: 0x%X\r\n", current_pnm_cmd.opcode);
            }

            // Write the output data back to the shared buffer based on the RD field of the current_pnm_cmd
            cent_write_shared_buffer(current_pnm_cmd.rd, data_out);

            // Clear the pending request flag
            pnm_request_pending = false;

            // Fire the pnm_done signal to indicate completion of PNM processing
            cent_fire_pnm_done();
        }
    }

    return 0;
}
