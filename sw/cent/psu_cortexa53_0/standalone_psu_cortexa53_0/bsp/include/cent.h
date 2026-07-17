#ifndef CENT_H
#define CENT_H

#include <xil_io.h>

// ISA is 64 bits wide, so we can represent each instruction as a 64-bit unsigned integer
typedef u64 cent_instr_t;

// A program is just an array of these instructions and its length starting at index i in the instruction buffer (16KB, 2048 instructions, 64-bit each)
typedef struct {
    cent_instr_t*   instructions;
    u32             length;
    u32             start_index; // index/location not absolute address, 0-2047
} cent_program_t;

// Static functions to build CENT ISA instructions
// ISA:
// - NOP (No Operation) OPcode 0x1
// - WR_SBK CHid OPsize BK RO CO Rs (Shared Buffer -> PIM Banks) OPcode 0x2
// - RD_SBK CHid OPsize BK RO CO Rd (PIM Banks -> Shared Buffer) OPcode 0x3
// - WR_ABK CHid RO CO Rs (Shared Buffer -> All 16 PIM Banks) OPcode 0x4
// - COPY_BKGB CHmask OPsize BK RO CO Gb (PIM Banks -> Global Buffer) OPcode 0x5
// - COPY_GBBK CHmask OPsize BK RO CO Gb (Global Buffer -> PIM Banks) OPcode 0x6
// - WR_BIAS CHmask Rs Regid (Shared Buffer -> PIM PU Accumulation Regs) OPcode 0x7
// - RD_MAC CHmask Rd Regid (PIM PU Accumulation Regs -> Shared Buffer) OPcode 0x8
// - WR_GB CHmask OPsize Gb Rs (Shared Buffer -> Global Buffer) OPcode 0x9
// - MAC_ABK CHmask OPsize RO CO Gb OPid Regid (Global Buffer * PIM Banks -> PIM PU Accumulation Regs) OPcode 0xA
// - EW_MUL CHmask OPsize RO CO (Element-wise Mult in PIM Bank Groups) OPcode 0xB
// - AF CHmask AFid Regid (Apply activation function to PIM PU Accumulation Regs) OPcode 0xC
// - PNM OPsize Funcid Rd Rs (PNM functions from/to SBUF) OPcode 0xD

// CENT ISA Opcodes
typedef enum {
    CENT_OP_INVALID   = 0x0,
    CENT_OP_NOP       = 0x1,
    CENT_OP_WR_SBK    = 0x2,
    CENT_OP_RD_SBK    = 0x3,
    CENT_OP_WR_ABK    = 0x4,
    CENT_OP_COPY_BKGB = 0x5,
    CENT_OP_COPY_GBBK = 0x6,
    CENT_OP_WR_BIAS   = 0x7,
    CENT_OP_RD_MAC    = 0x8,
    CENT_OP_WR_GB     = 0x9,
    CENT_OP_MAC_ABK   = 0xA,
    CENT_OP_EW_MUL    = 0xB,
    CENT_OP_AF        = 0xC,
    CENT_OP_PNM       = 0xD
} cent_opcode_t;

// PIM MAC operation IDs
typedef enum {
    MAC_OP_GEMV       = 0x0,
    MAC_OP_VECTOR_DOT = 0x1
} cent_pim_mac_opid_t;

// PIM AF function IDs/activation function IDs
typedef enum {
    AFID_SIGMOID    = 0x0,
    AFID_TANH       = 0x1,
    AFID_GELU       = 0x2,
    AFID_RELU       = 0x3,
    AFID_LEAKY_RELU = 0x4
} cent_pim_afid_t;

// PNM Instruction Function IDs
typedef enum {
    PNM_FUNCID_EXP     = 0x0,
    PNM_FUNCID_RED     = 0x1,
    PNM_FUNCID_ACC     = 0x2,
    PNM_FUNCID_SUB     = 0x3,
    PNM_FUNCID_INV     = 0x4,
    PNM_FUNCID_SQRT    = 0x5,
    PNM_FUNCID_MULT    = 0x6,
    PNM_FUNCID_DIV     = 0x7
    // TODO: add other PNM functions.
} cent_pnm_funcid_t;

// NOTE: Deviations from the CENT ISA paper:
// NOTE: The WR_ABK instruction is slightly different from the paper since we remove Regid because it seems unrelated to the WR_ABK instruction.
// NOTE: The WR_BIAS instruction is slightly different from the paper since we added Regid for more control over initializing the accumulation registers.
// NOTE: The COPY_BKGB and COPY_GBBK instructions are slightly different from the paper since we added BK to specify which bank to copy from/to and added Gb to decouple CO pim bank from gbuff address.
// NOTE: The MAC_ABK instruction is slightly different from the paper since we added OPid to select between GEMV and Vector dot Product and Gb to decouple CO pim bank from gbuff address.
// NOTE: The WR_GB instruction is slightly different from the paper since we changed CO to be Gb since CO is pim bank related and gbuff address was decoupled from pim bank address through Gb.
// NOTE: The PNM instruction is slightly different from the paper since we use funcid for different PNM functions instead of dedicated instructions
// This is because they all have common "shape" of PNM_INSTR Opsize rd rs in the paper
  

// 0x1: NOP - [63:60] UOP, [59:0] Don't care
static inline cent_instr_t build_nop() {
    return ((u64)CENT_OP_NOP & 0xF) << 60; // Set UOP to 0x1 and the rest of the bits to 0
}

// 0x2: WR_SBK - [63:60] UOP, [59:55] CHid, [54:45] OPsize, [44:41] BK, [40:37] RO, [36:31] CO, [30:17] RS
static inline cent_instr_t build_wr_sbk(u8 chid, u16 opsize, u8 bk, u8 ro, u8 co, u16 rs) {
    return  (((u64)CENT_OP_WR_SBK & 0xF) << 60) |
            (((u64)chid   & 0x1F)        << 55) |
            (((u64)opsize & 0x3FF)       << 45) |
            (((u64)bk     & 0xF)         << 41) |
            (((u64)ro     & 0xF)         << 37) |
            (((u64)co     & 0x3F)        << 31) |
            (((u64)rs     & 0x3FFF)      << 17);
}

// 0x3: RD_SBK - [63:60] UOP, [59:55] CHid, [54:45] OPsize, [44:41] BK, [40:37] RO, [36:31] CO, [30:17] RD
static inline cent_instr_t build_rd_sbk(u8 chid, u16 opsize, u8 bk, u8 ro, u8 co, u16 rd) {
    return  (((u64)CENT_OP_RD_SBK & 0xF) << 60) |
            (((u64)chid   & 0x1F)        << 55) |
            (((u64)opsize & 0x3FF)       << 45) |
            (((u64)bk     & 0xF)         << 41) |
            (((u64)ro     & 0xF)         << 37) |
            (((u64)co     & 0x3F)        << 31) |
            (((u64)rd     & 0x3FFF)      << 17);
}

// 0x4: WR_ABK - [63:60] UOP, [59:55] CHid, [54:51] RO, [50:45] CO, [44:31] RS
static inline cent_instr_t build_wr_abk(u8 chid, u8 ro, u8 co, u16 rs) {
    return  (((u64)CENT_OP_WR_ABK & 0xF) << 60) |
            (((u64)chid   & 0x1F)        << 55) |
            (((u64)ro     & 0xF)         << 51) |
            (((u64)co     & 0x3F)        << 45) |
            (((u64)rs     & 0x3FFF)      << 31);
}

// 0x5: COPY_BKGB - [63:60] UOP, [59:55] CHmask, [54:45] OPsize, [44:41] BK, [40:37] RO, [36:31] CO, [30:25] Gb
static inline cent_instr_t build_copy_bkgb(u8 chmask, u16 opsize, u8 bk, u8 ro, u8 co, u8 gb) {
    return  (((u64)CENT_OP_COPY_BKGB & 0xF) << 60) |
            (((u64)chmask & 0x1F)           << 55) |
            (((u64)opsize & 0x3FF)          << 45) |
            (((u64)bk     & 0xF)            << 41) |
            (((u64)ro     & 0xF)            << 37) |
            (((u64)co     & 0x3F)           << 31) |
            (((u64)gb     & 0x3F)           << 25);
}

// 0x6: COPY_GBBK - [63:60] UOP, [59:55] CHmask, [54:45] OPsize, [44:41] BK, [40:37] RO, [36:31] CO, [30:25] Gb
static inline cent_instr_t build_copy_gbbk(u8 chmask, u16 opsize, u8 bk, u8 ro, u8 co, u8 gb) {
    return  (((u64)CENT_OP_COPY_GBBK & 0xF) << 60) |
            (((u64)chmask & 0x1F)           << 55) |
            (((u64)opsize & 0x3FF)          << 45) |
            (((u64)bk     & 0xF)            << 41) |
            (((u64)ro     & 0xF)            << 37) |
            (((u64)co     & 0x3F)           << 31) |
            (((u64)gb     & 0x3F)           << 25);
}

// 0x7: WR_BIAS - [63:60] UOP, [59:55] CHmask, [54:41] RS, [40:36] Regid (Regid is an addition to the paper's WR_BIAS)
static inline cent_instr_t build_wr_bias(u8 chmask, u16 rs, u8 regid) {
    return  (((u64)CENT_OP_WR_BIAS & 0xF) << 60) |
            (((u64)chmask & 0x1F)         << 55) |
            (((u64)rs     & 0x3FFF)       << 41) |
            (((u64)regid  & 0x1F)         << 36);
}

// 0x8: RD_MAC - [63:60] UOP, [59:55] CHmask, [54:41] RD, [40:36] Regid
static inline cent_instr_t build_rd_mac(u8 chmask, u16 rd, u8 regid) {
    return  (((u64)CENT_OP_RD_MAC & 0xF) << 60) |
            (((u64)chmask & 0x1F)        << 55) |
            (((u64)rd     & 0x3FFF)      << 41) |
            (((u64)regid  & 0x1F)        << 36);
}

// 0x9: WR_GB - [63:60] UOP, [59:55] CHmask, [54:45] OPsize, [44:39] Gb, [38:25] RS
static inline cent_instr_t build_wr_gb(u8 chmask, u16 opsize, u8 gb, u16 rs) {
    return  (((u64)CENT_OP_WR_GB & 0xF) << 60) |
            (((u64)chmask & 0x1F)       << 55) |
            (((u64)opsize & 0x3FF)      << 45) |
            (((u64)gb     & 0x3F)       << 39) |
            (((u64)rs     & 0x3FFF)     << 25);
}

// 0xA: MAC_ABK - [63:60] UOP, [59:55] CHmask, [54:45] OPsize, [44:41] RO, [40:35] CO, [34:29] Gb, [28] OPid, [27:23] Regid
static inline cent_instr_t build_mac_abk(u8 chmask, u16 opsize, u8 ro, u8 co, u8 gb, cent_pim_mac_opid_t opid, u8 regid) {
    return  (((u64)CENT_OP_MAC_ABK & 0xF) << 60) |
            (((u64)chmask & 0x1F)         << 55) |
            (((u64)opsize & 0x3FF)        << 45) |
            (((u64)ro     & 0xF)          << 41) |
            (((u64)co     & 0x3F)         << 35) |
            (((u64)gb     & 0x3F)         << 29) |
            (((u64)opid   & 0x1)          << 28) |
            (((u64)regid  & 0x1F)         << 23);
}

// 0xB: EW_MUL - [63:60] UOP, [59:55] CHmask, [54:45] OPsize, [44:41] RO, [40:35] CO
static inline cent_instr_t build_ew_mul(u8 chmask, u16 opsize, u8 ro, u8 co) {
    return  (((u64)CENT_OP_EW_MUL & 0xF) << 60) |
            (((u64)chmask & 0x1F)        << 55) |
            (((u64)opsize & 0x3FF)       << 45) |
            (((u64)ro     & 0xF)         << 41) |
            (((u64)co     & 0x3F)        << 35);
}

// 0xC: AF - [63:60] UOP, [59:55] CHmask, [54:52] AFid, [51:47] Regid
static inline cent_instr_t build_af(u8 chmask, cent_pim_afid_t afid, u8 regid) {
    return  (((u64)CENT_OP_AF & 0xF) << 60) |
            (((u64)chmask & 0x1F)    << 55) |
            (((u64)afid   & 0x7)     << 52) |
            (((u64)regid  & 0x1F)    << 47);
}

// 0xD: PNM - [63:60] UOP, [59:50] OPsize, [49:45] Funcid, [44:31] RD, [30:17] RS
static inline cent_instr_t build_pnm(u16 opsize, cent_pnm_funcid_t funcid, u16 rd, u16 rs) {
    return  (((u64)CENT_OP_PNM & 0xF) << 60) |
            (((u64)opsize & 0x3FF)    << 50) |
            (((u64)funcid & 0x1F)     << 45) |
            (((u64)rd     & 0x3FFF)   << 31) |
            (((u64)rs     & 0x3FFF)   << 17);
}

// Instruction Buffer 16KB (2048x64), can hold up to 2048 instructions
void cent_load_program(cent_program_t* program);

// Shared Buffer 512KB (16384x256), can hold up to 16384 256-bit vectors (16 16-bit bf16 values per vector)
void cent_write_shared_buffer(u16 index, const u16 data[16]); // index/location, not absolute address, 0-16383
void cent_read_shared_buffer(u16 index, u16 data[16]); // index/location, not absolute address, 0-16383

// Host Interface and Control Registers:
// - 0x0:  ver_id_reg (RO)
// - 0x4:  status_reg -> `status_reg <= (31 downto 5 => '0') & pnm_req_sticky & err_sticky(1) & err_sticky(0) & busy & done_sticky` -> write 1 to clear `sticky`
// - 0x8:  perf_reg (RO)
// - 0xC:  curr_pc_reg (RO)
// - 0x10: ctrl_reg -> `0: en, 1: irq_en`
// - 0x14: cmd_base_reg (RW)
// - 0x18: cmd_len_reg (RW)
// - 0x1C: doorbell (any value to fire pulse)
// - 0x20: soft_rst (any value to fire pulse)
// - 0x24: curr_dec_cmd_bot_reg (RO) - current command's bottom 32 bits of the decoded instruction (after instruction decoding)
// - 0x28: curr_dec_cmd_top_reg (RO) - current command's top 32 bits of the decoded instruction (after instruction decoding)
// - 0x2C: pnm_done (any value to fire pulse)
#define IFACE_CTR_VER_ID_REG_OFFSET           0x0
#define IFACE_CTR_STATUS_REG_OFFSET           0x4
#define IFACE_CTR_PERF_REG_OFFSET             0x8
#define IFACE_CTR_CURR_PC_REG_OFFSET          0xC
#define IFACE_CTR_CTRL_REG_OFFSET             0x10
#define IFACE_CTR_CMD_BASE_REG_OFFSET         0x14
#define IFACE_CTR_CMD_LEN_REG_OFFSET          0x18
#define IFACE_CTR_DOORBELL_REG_OFFSET         0x1C
#define IFACE_CTR_SOFT_RST_REG_OFFSET         0x20
#define IFACE_CTR_CURR_DEC_CMD_BOT_REG_OFFSET 0x24
#define IFACE_CTR_CURR_DEC_CMD_TOP_REG_OFFSET 0x28
#define IFACE_CTR_PNM_DONE_REG_OFFSET         0x2C

u32 cent_read_ver_id();
u32 cent_read_status();
void cent_write_status(u32 value); // to clear sticky bits
u32 cent_read_perf();
u32 cent_read_curr_pc();
void cent_write_ctrl(u32 value);
void cent_write_cmd_base(u32 value);
void cent_write_cmd_len(u32 value);
void cent_fire_doorbell();
void cent_soft_reset();
u64 cent_read_curr_dec_cmd();
void cent_fire_pnm_done();

#endif // CENT_H
