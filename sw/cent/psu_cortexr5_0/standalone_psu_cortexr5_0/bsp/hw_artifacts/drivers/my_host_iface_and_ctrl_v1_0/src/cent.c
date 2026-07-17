#include "cent.h"
#include "xparameters.h"

void cent_load_program(cent_program_t* program) {
    // Get instructions, length, and start index from the program struct
    cent_instr_t* instructions = program->instructions;
    u32 length = program->length;
    u32 start_index = program->start_index; // this is an index/location, not an absolute address, so it should be between 0 and 2047

    // Effective start address in the instruction buffer
    u32 eff_start_address = XPAR_AXI_BRAM_CTRL_INSTR_BASEADDR + (start_index * sizeof(cent_instr_t)); // (8 bytes for 64-bit instructions)

    // Load each instruction into the instruction buffer at the correct address
    for (u32 i = 0; i < length; i++) {
        // Calculate the address to write this instruction to
        u32 instr_address = eff_start_address + (i * sizeof(cent_instr_t));
        // Write the instruction to the instruction buffer
        Xil_Out64(instr_address, instructions[i]);
    }
}

void cent_write_shared_buffer(u16 index, const u16 data[16]) {

    u32 eff_address = XPAR_AXI_BRAM_CTRL_SHARED_BASEADDR + (index * sizeof(u16) * 16); // 32 bytes per entry

    // Write the 256-bit vector (16 16-bit values) using memcpy to write all 16 values "at once"
    memcpy((void*)(uintptr_t)eff_address, data, sizeof(u16) * 16);
}

void cent_read_shared_buffer(u16 index, u16 data[16]) {

    u32 eff_address = XPAR_AXI_BRAM_CTRL_SHARED_BASEADDR + (index * sizeof(u16) * 16); // 32 bytes per entry

    // Read the 256-bit vector (16 16-bit values) using memcpy to read all 16 values "at once"
    memcpy(data, (void*)(uintptr_t)eff_address, sizeof(u16) * 16);
}

u32 cent_read_ver_id() {
    return Xil_In32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_VER_ID_REG_OFFSET);
}

u32 cent_read_status() {
    return Xil_In32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_STATUS_REG_OFFSET);
}

void cent_write_status(u32 value) {
    Xil_Out32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_STATUS_REG_OFFSET, value);
}

u32 cent_read_perf() {
    return Xil_In32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_PERF_REG_OFFSET);
}

u32 cent_read_curr_pc() {
    return Xil_In32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_CURR_PC_REG_OFFSET);
}

void cent_write_ctrl(u32 value) {
    Xil_Out32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_CTRL_REG_OFFSET, value);
}

void cent_write_cmd_base(u32 value) {
    Xil_Out32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_CMD_BASE_REG_OFFSET, value);
}

void cent_write_cmd_len(u32 value) {
    Xil_Out32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_CMD_LEN_REG_OFFSET, value);
}

void cent_fire_doorbell() {
    Xil_Out32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_DOORBELL_REG_OFFSET, 0x1); // any value will fire pulse
}

void cent_soft_reset() {
    Xil_Out32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_SOFT_RST_REG_OFFSET, 0x1); // any value will fire pulse
}

u64 cent_read_curr_dec_cmd() {
    u32 bot = Xil_In32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_CURR_DEC_CMD_BOT_REG_OFFSET);
    u32 top = Xil_In32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_CURR_DEC_CMD_TOP_REG_OFFSET);
    
    return (((u64)top) << 32) | bot;
}

void cent_fire_pnm_done() {
    Xil_Out32(XPAR_XMY_HOST_IFACE_AND_CTRL_0_BASEADDR + IFACE_CTR_PNM_DONE_REG_OFFSET, 0x1); // any value will fire pulse
}
