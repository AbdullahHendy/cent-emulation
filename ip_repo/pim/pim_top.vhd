library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

library xpm;
use xpm.vcomponents.all;

entity pim_top is
    generic (
        -- shared buff is 16KB byte addressable
        SHARED_BUFF_DATA_WIDTH  : integer := 256;
        SHARED_BUFF_ADDR_WIDTH  : integer := 19; -- byte addressed, 512 KB, 256 wide, 16384 deep
        GLOBAL_BUFF_DATA_WIDTH  : integer := 256;
        GLOBAL_BUFF_ADDR_WIDTH  : integer := 6; -- "word" addressed, word is 256-bits, matches pim_cmd co field size in instructions with CO field
        PIM_CMD_WIDTH           : integer := 64;
        ACC_REGS_ADDR_WIDTH     : integer := 5; -- 32 registers
        PIM_BANK_NUM_BANKS      : integer := 16;
        PIM_BANK_LANE_NUMS      : integer := 16;
        PIM_BANK_LANE_WIDTH     : integer := 16;
        PIM_BANK_ADDR_WIDTH     : integer := 10; -- "word" addressed, word is 256-bits, 1024 locations for 32KB banks
        EW_MUL_BANK_GROUPS      : integer := 4; 
        MAC_LANE_NUMS           : integer := 16;
        MAC_INPUT_LANE_WIDTH    : integer := 16; -- single input MAC lane is 16-bit BF16 value
        MAC_RESULT_LANE_WIDTH   : integer := 32   -- single output MAC result is 32-bit FP32
    );

    port ( 
        clk   : in std_logic;
        rst_n : in std_logic;
         
        -- BRAM interface (Shared Buffer)
        shared_addr  : out std_logic_vector(SHARED_BUFF_ADDR_WIDTH-1 downto 0);
        shared_din   : out std_logic_vector(SHARED_BUFF_DATA_WIDTH-1 downto 0);
        shared_dout  : in  std_logic_vector(SHARED_BUFF_DATA_WIDTH-1 downto 0);
        shared_en    : out std_logic;
        shared_we    : out std_logic_vector((SHARED_BUFF_DATA_WIDTH/8)-1 downto 0);
        shared_clk   : out std_logic;
        shared_rst   : out std_logic;
         
        -- PIM interface (PIM block)
        pim_cmd_valid  : in std_logic;
        pim_cmd_ready  : out  std_logic;
        pim_cmd        : in  std_logic_vector(PIM_CMD_WIDTH-1 downto 0); 
        pim_done_pulse : out  std_logic
     );

end pim_top;

architecture Behavioral of pim_top is

    -- States def
    type state_t is (
        IDLE,
        DECODE,
        
        EXEC_WR_SBK_READ,       -- read from SBUF
        EXEC_WR_SBK_WRITE,      -- write to PIM bank
        
        EXEC_WR_ABK_READ,       -- read from SBUF
        EXEC_WR_ABK_WRITE,      -- write to PIM bank
        
        EXEC_WR_GB_READ,        -- read from SBUF
        EXEC_WR_GB_WRITE,       -- write to GBUF
        
        EXEC_WR_BIAS_READ,      -- read from SBUF
        EXEC_WR_BIAS_WRITE,     -- write to one acc reg in all banks
        
        EXEC_RD_MAC_READ,       -- read from one acc reg in all banks
        EXEC_RD_MAC_CAST_FIRE,  -- enable cast units to cast acc reg output (16xFP32) to (16xBF16) for SBUF
        EXEC_RD_MAC_CAST_WAIT,  -- wait for cast units to finish 
        EXEC_RD_MAC_WRITE,      -- write to SBUF
        
        EXEC_MAC_ABK_READ,      -- read from GBUF, PIM banks, acc regs
        EXEC_MAC_ABK_MAC_FIRE,  -- enable MAC units using OPid-selected mode
        EXEC_MAC_ABK_MAC_WAIT,  -- wait for mac unit to finish
        EXEC_MAC_ABK_WRITE,     -- write to one acc reg in all banks
        
        EXEC_AF_READ,           -- read from one acc reg in all banks
        EXEC_AF_CAST_FIRE,      -- enable cast units to cast acc reg output (16xFP32) to (16xBF16) for AF units
        EXEC_AF_CAST_WAIT,
        EXEC_AF_AF_FIRE,        -- enable af units
        EXEC_AF_AF_WAIT,        -- wait for af units to finish
        EXEC_AF_WRITE,          -- write to one acc reg in all banks
        
        EXEC_EW_MUL_READ,       -- read all PIM banks at address ro&co
        EXEC_EW_MUL_FIRE,       -- enable ew_mul_groups units
        EXEC_EW_MUL_WAIT,       -- wait for ew_mul_groups to fnish
        EXEC_EW_MUL_WRITE,      -- write result to all EW_MUL_BANK_GROUPS      
        
        EXEC_RD_SBK_READ,       -- read from selected PIM bank
        EXEC_RD_SBK_WRITE,      -- write to SBUF        
       
        EXEC_COPY_BKGB_READ,    -- read selected PIM bank
        EXEC_COPY_BKGB_WRITE,   -- write to GBUF
        
        EXEC_COPY_GBBK_READ,    -- read GBUF word
        EXEC_COPY_GBBK_WRITE,   -- write to PIM bank       
       
        DONE,
        ERROR
        -- TODO: there is not currently meaningful handling of error
    );
    
    signal curr_state : state_t := IDLE;
    signal next_state : state_t := IDLE;
    
    constant PIM_BANK_DATA_WIDTH       : integer := PIM_BANK_LANE_NUMS * PIM_BANK_LANE_WIDTH;
    constant ACC_REGS_DATA_WIDTH       : integer := PIM_BANK_NUM_BANKS * MAC_RESULT_LANE_WIDTH; -- acc regs hold fp32 values (mac units output)
    constant SHARED_BUFF_WORD_BYTES    : integer := SHARED_BUFF_DATA_WIDTH / 8; -- stride when dealing with shared buff
    constant EW_MUL_BANKS_PER_GROUP    : integer := PIM_BANK_NUM_BANKS / EW_MUL_BANK_GROUPS; -- How many banks per bank group
    constant EW_MUL_RESULT_BANK_OFFSET : integer := 2; -- e.g. In bank group 0, result of bank0 * bank1 goes to bank2
    
    -- pim_cmd fields latch signals
    -- pim_cmd is the same as the original CENT instruction but with its OPSize (if applicable) cleared to 0, since it handled by cmd_engine
    
    signal uop_reg     : std_logic_vector(3 downto 0);
    signal ch_id_reg   : std_logic_vector(4 downto 0);
    signal ch_mask_reg : std_logic_vector(4 downto 0);
    signal bk_reg      : std_logic_vector(3 downto 0);
    signal ro_reg      : std_logic_vector(3 downto 0);
    signal co_reg      : std_logic_vector(5 downto 0);
    signal gb_reg      : std_logic_vector(5 downto 0);
    signal rs_reg      : std_logic_vector(13 downto 0); -- passed from pim_cmd as "word" address, i.e "locations"
    signal rd_reg      : std_logic_vector(13 downto 0); -- passed from pim_cmd as "word" address, i.e "locations"
    signal regid_reg   : std_logic_vector(4 downto 0);
    signal opid_reg    : std_logic;                     -- passed from MAC_ABK and select MAC units mode (GEMV vs Vector dot Product)
    signal afid_reg    : std_logic_vector(2 downto 0);
    
    signal rst         : std_logic;
    
    -- SBUF signal
    signal shared_dout_padded : std_logic_vector((PIM_BANK_NUM_BANKS*MAC_RESULT_LANE_WIDTH)-1 downto 0); -- To convert 16xBF16 SBUF data to 16xFP32 for acc regs write(WR_BIAS)
    
    -- GBUF
    -- Inputs:  16xBF16
    -- Outputs: 16xBF16
    signal gbuf_en      : std_logic;
    signal gbuf_wr_en   : std_logic;
    signal gbuf_addr    : std_logic_vector(GLOBAL_BUFF_ADDR_WIDTH-1 downto 0);
    signal gbuf_wr_data : std_logic_vector(GLOBAL_BUFF_DATA_WIDTH-1 downto 0);
    signal gbuf_rd_data : std_logic_vector(GLOBAL_BUFF_DATA_WIDTH-1 downto 0);
    
    -- Accumulation regs (all banks)
    -- Inputs:  16xFP32
    -- Outputs: 16xFP32
    signal acc_regs_en             : std_logic;
    signal acc_regs_wr_en          : std_logic;
    signal acc_regs_addr           : std_logic_vector(ACC_REGS_ADDR_WIDTH-1 downto 0);
    signal acc_regs_wr_data        : std_logic_vector(ACC_REGS_DATA_WIDTH-1 downto 0);
    signal acc_regs_rd_data        : std_logic_vector(ACC_REGS_DATA_WIDTH-1 downto 0);
    signal acc_regs_rd_data_casted : std_logic_vector((PIM_BANK_NUM_BANKS*MAC_INPUT_LANE_WIDTH)-1 downto 0); -- casted acc reg data from 16xFP32 to 16xBF16 for components that need it
    
    -- PIM banks
    -- Inputs:  16xBF16
    -- Outputs: 16xBF16
    component pim_banks
        generic (
            NUM_BANKS  : integer := PIM_BANK_NUM_BANKS;
            LANE_NUMS  : integer := PIM_BANK_LANE_NUMS;
            LANE_WIDTH : integer := PIM_BANK_LANE_WIDTH;
            ADDR_WIDTH : integer := PIM_BANK_ADDR_WIDTH
        );
        port (
            clk         : in  std_logic;
            rst_n       : in  std_logic;
            bank_sel    : in  std_logic_vector(3 downto 0);
            en          : in  std_logic;
            wr_en       : in  std_logic;
            wr_all      : in  std_logic;
            addr        : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
            wr_data     : in  std_logic_vector((LANE_NUMS*LANE_WIDTH)-1 downto 0);
            rd_data     : out std_logic_vector((LANE_NUMS*LANE_WIDTH)-1 downto 0);
            rd_data_all : out std_logic_vector((NUM_BANKS*LANE_NUMS*LANE_WIDTH)-1 downto 0)
        );
    end component; 
    signal pim_bank_bank_sel    : std_logic_vector(3 downto 0);
    signal pim_bank_en          : std_logic;            
    signal pim_bank_wr_en       : std_logic;
    signal pim_bank_wr_all      : std_logic; -- Writes bank i with 16 replicas of lane i of wr_data, ignore bank_sel
    signal pim_bank_addr        : std_logic_vector(PIM_BANK_ADDR_WIDTH-1 downto 0);
    signal pim_bank_wr_data     : std_logic_vector(PIM_BANK_DATA_WIDTH-1 downto 0);
    signal pim_bank_rd_data     : std_logic_vector(PIM_BANK_DATA_WIDTH-1 downto 0); -- Output of selected bank
    signal pim_bank_rd_data_all : std_logic_vector((PIM_BANK_NUM_BANKS * PIM_BANK_DATA_WIDTH)-1 downto 0); -- Output of all banks for MAC
    
    -- MAC units (all banks)
    -- Inputs:  A:16xBF16 --- B:16x16xBF16
    -- Outputs: 16xFP32    
    component mac_units
        generic (
            NUM_BANKS        : integer := PIM_BANK_NUM_BANKS;
            LANE_NUMS        : integer := MAC_LANE_NUMS;
            INPUT_LANE_WIDTH : integer := MAC_INPUT_LANE_WIDTH;
            RESULT_LANE_WIDTH: integer := MAC_RESULT_LANE_WIDTH              
        );
        port (
            clk           : in  std_logic;
            rst_n         : in  std_logic;
            en_pulse      : in  std_logic;
            mode          : in  std_logic; -- '0' = GEMV (GBUF), '1' = Vector Dot Product (Neighbor Bank)
            gbuf_data     : in  std_logic_vector((LANE_NUMS*INPUT_LANE_WIDTH)-1 downto 0); -- From Global Buffer
            bank_data_all : in  std_logic_vector((NUM_BANKS*LANE_NUMS*INPUT_LANE_WIDTH)-1 downto 0); -- From all PIM banks
            acc_init_all  : in  std_logic_vector((NUM_BANKS * RESULT_LANE_WIDTH)-1 downto 0); -- From Accumulator Regfile
            result_all    : out std_logic_vector((NUM_BANKS * RESULT_LANE_WIDTH)-1 downto 0);
            valid         : out std_logic
        );
    end component;
    signal mac_en_pulse      : std_logic;
    signal mac_mode          : std_logic;
    signal mac_gbuf_data     : std_logic_vector(GLOBAL_BUFF_DATA_WIDTH-1 downto 0);
    signal mac_bank_data_all : std_logic_vector((PIM_BANK_NUM_BANKS * PIM_BANK_DATA_WIDTH)-1 downto 0);
    signal mac_acc_init_all  : std_logic_vector((PIM_BANK_NUM_BANKS * MAC_RESULT_LANE_WIDTH)-1 downto 0);
    signal mac_result_all    : std_logic_vector((PIM_BANK_NUM_BANKS * MAC_RESULT_LANE_WIDTH)-1 downto 0);
    signal mac_valid         : std_logic;


    -- AF units (all banks)
    -- Inputs:  16xBF16
    -- Outputs: 16xBF16    
    component af_units is
        generic (
            NUM_BANKS       : integer := PIM_BANK_NUM_BANKS;
            AC_FCNS_NUM     : integer := 5;
            ROM_ADDR_WIDTH  : integer := 12; -- 512 segments for each function clog(512*5) = 12
            ROM_DATA_WIDTH  : integer := 32; -- 16 for Y[a] and 16 for delta Y: (Y[b] - Y[a])
            FRACTION_WIDTH  : integer := 6; -- see above
            LANE_WIDTH      : integer := MAC_INPUT_LANE_WIDTH  -- 256/16 = 16-bit / lane
            
        );
        port ( 
            clk         : in std_logic;
            rst_n       : in std_logic;
                
            en_pulse    : in std_logic;
            input_x_all : in std_logic_vector(NUM_BANKS*LANE_WIDTH-1 downto 0); -- 16 bf16 inputs from all bank acc registers
            af_sel      : in std_logic_vector(2 downto 0); -- 5 activation functions supported (Sigmoid, Tanh, GELU, ReLU, and leaky ReLU)  stay constant until output is valid 
                
            result_all  : out std_logic_vector(NUM_BANKS*LANE_WIDTH-1 downto 0);
            valid       : out std_logic -- asserted when output data is valid
         );     
    end component;  
    signal af_en_pulse           : std_logic;
    signal af_input_x_all        : std_logic_vector(PIM_BANK_NUM_BANKS*MAC_INPUT_LANE_WIDTH-1 downto 0);
    signal af_af_sel             : std_logic_vector(2 downto 0);
    signal af_result_all         : std_logic_vector(PIM_BANK_NUM_BANKS*MAC_INPUT_LANE_WIDTH-1 downto 0);
    signal af_result_all_padded  : std_logic_vector(PIM_BANK_NUM_BANKS*MAC_RESULT_LANE_WIDTH-1 downto 0); -- To convert 16xBF16 af units result to 16xFP32 for acc regs write (AF)
    signal af_valid              : std_logic;
    
    -- Casting units (all banks)
    -- Inputs:  16xFP32 
    -- Outputs: 16xBF16
    component fp32_to_bf16_units is
        generic (
            NUM_BANKS  : integer := PIM_BANK_NUM_BANKS;
            FP32_WIDTH : integer := MAC_RESULT_LANE_WIDTH; -- 32-bit input lane
            BF16_WIDTH : integer := MAC_INPUT_LANE_WIDTH   -- 16-bit output lane
        );
        port (
            clk           : in  std_logic;
            
            en_pulse      : in  std_logic; 
            fp32_data_all : in  std_logic_vector((NUM_BANKS * FP32_WIDTH)-1 downto 0); -- 512-bit from Regfile
            
            bf16_data_all : out std_logic_vector((NUM_BANKS * BF16_WIDTH)-1 downto 0); -- 256-bit to downstream e.g. AF/SBUFF
            valid         : out std_logic  -- Pulse when cast is complete
        );
    end component;
    signal cast_en_pulse      : std_logic;
    signal cast_fp32_data_all : std_logic_vector((PIM_BANK_NUM_BANKS * MAC_RESULT_LANE_WIDTH)-1 downto 0);
    signal cast_bf16_data_all : std_logic_vector((PIM_BANK_NUM_BANKS * MAC_INPUT_LANE_WIDTH)-1 downto 0);
    signal cast_valid         : std_logic;
    
    -- EW_MUL units (4 bank groups)
    -- Inputs: 16x16xBF16
    -- Outputs
    component ew_mul_groups is
        generic (
            NUM_BANKS   : integer := PIM_BANK_NUM_BANKS;
            BANK_GROUPS : integer := EW_MUL_BANK_GROUPS;
            LANE_NUMS   : integer := PIM_BANK_LANE_NUMS;
            LANE_WIDTH  : integer := PIM_BANK_LANE_WIDTH
        );
        port (
            clk           : in  std_logic;
            en_pulse      : in  std_logic;
            bank_data_all : in  std_logic_vector((NUM_BANKS*LANE_NUMS*LANE_WIDTH)-1 downto 0);
            result_groups : out std_logic_vector((BANK_GROUPS*LANE_NUMS*LANE_WIDTH)-1 downto 0);
            valid         : out std_logic
        );
    end component;
    signal ew_mul_en_pulse          : std_logic;
    signal ew_mul_bank_data_all     : std_logic_vector((PIM_BANK_NUM_BANKS * PIM_BANK_DATA_WIDTH)-1 downto 0);
    signal ew_mul_result_groups     : std_logic_vector((EW_MUL_BANK_GROUPS * PIM_BANK_DATA_WIDTH)-1 downto 0);
    signal ew_mul_result_groups_reg : std_logic_vector((EW_MUL_BANK_GROUPS * PIM_BANK_DATA_WIDTH)-1 downto 0);
    signal ew_mul_valid             : std_logic;
    signal ew_mul_write_idx         : integer range 0 to EW_MUL_BANK_GROUPS-1; -- pim_banks doesn't have a way for parallel writes to select banks, we do it sequentially and keep track of the idx
    
begin
    -- not rst
    rst <= not rst_n;

    -- combinational pass-through for buffers clk and resets
    shared_rst     <= rst;
    shared_clk     <= clk;

    pim_cmd_ready <= '1' when curr_state = IDLE else '0';

    -- curr state process (1)
    p_curr_state_reg : process(clk, rst_n)
    begin
        if rst_n = '0' then
            curr_state <= IDLE;
        elsif rising_edge(clk) then
            curr_state <= next_state;
        end if;
    end process;


    -- next state process (2)
    p_next_state: process(curr_state, pim_cmd_valid, uop_reg, mac_valid, af_valid, cast_valid, ew_mul_valid, ew_mul_write_idx)
    begin
        next_state <= curr_state;
        case curr_state is
            when IDLE =>
                if (pim_cmd_valid = '1') then
                    next_state <= DECODE;
                end if;
                
            when DECODE =>
                case uop_reg is
                
                    when x"2" =>
                        next_state <= EXEC_WR_SBK_READ;
                    
                    when x"3" =>
                        next_state <= EXEC_RD_SBK_READ;
                    
                    when x"4" =>
                        next_state <= EXEC_WR_ABK_READ;
                    
                    when x"5" =>
                        next_state <= EXEC_COPY_BKGB_READ;
                    
                    when x"6" =>
                        next_state <= EXEC_COPY_GBBK_READ;

                    when x"7" =>
                        next_state <= EXEC_WR_BIAS_READ;
                        
                    when x"8" =>
                        next_state <= EXEC_RD_MAC_READ;
                        
                    when x"9" => 
                        next_state <= EXEC_WR_GB_READ;
                        
                    when x"A" =>
                        next_state <= EXEC_MAC_ABK_READ;
                    
                    when x"B" => 
                        next_state <= EXEC_EW_MUL_READ;
                    
                    when x"C" =>
                        next_state <= EXEC_AF_READ;
                    
                    when others =>
                        next_state <= ERROR;
                end case; 
            -- WR_SBK
            when EXEC_WR_SBK_READ =>
                next_state <= EXEC_WR_SBK_WRITE;
            when EXEC_WR_SBK_WRITE =>
                next_state <= DONE;
                
            -- WR_ABK
            when EXEC_WR_ABK_READ =>
                next_state <= EXEC_WR_ABK_WRITE;
            when EXEC_WR_ABK_WRITE =>
                next_state <= DONE;
                        
            -- WR_BIAS
            when EXEC_WR_BIAS_READ =>
                next_state <= EXEC_WR_BIAS_WRITE;
            when EXEC_WR_BIAS_WRITE =>
                next_state <= DONE;
            
            -- RD_MAC
            when EXEC_RD_MAC_READ =>
                next_state <= EXEC_RD_MAC_CAST_FIRE;
            when EXEC_RD_MAC_CAST_FIRE =>
                next_state <= EXEC_RD_MAC_CAST_WAIT;
            when EXEC_RD_MAC_CAST_WAIT =>
                if (cast_valid = '1') then
                    next_state <= EXEC_RD_MAC_WRITE;
                else
                    next_state <= EXEC_RD_MAC_CAST_WAIT;
                end if;
            when EXEC_RD_MAC_WRITE =>
                next_state <= DONE;                
            
            -- WR_GB
            when EXEC_WR_GB_READ =>
                next_state <= EXEC_WR_GB_WRITE;
            when EXEC_WR_GB_WRITE =>
                next_state <= DONE;
            
            -- MAC_ABK
            when EXEC_MAC_ABK_READ =>
                next_state <= EXEC_MAC_ABK_MAC_FIRE;
            when EXEC_MAC_ABK_MAC_FIRE =>
                next_state <= EXEC_MAC_ABK_MAC_WAIT;
            when EXEC_MAC_ABK_MAC_WAIT =>
                if (mac_valid = '1') then
                    next_state <= EXEC_MAC_ABK_WRITE;
                else
                    next_state <= EXEC_MAC_ABK_MAC_WAIT;
                end if;
            when EXEC_MAC_ABK_WRITE =>
                next_state <= DONE;
            
            -- AF      
            when EXEC_AF_READ =>
                next_state <= EXEC_AF_CAST_FIRE;
            when EXEC_AF_CAST_FIRE =>
                next_state <= EXEC_AF_CAST_WAIT;
            when EXEC_AF_CAST_WAIT =>
                if (cast_valid = '1') then
                    next_state <= EXEC_AF_AF_FIRE;
                else
                    next_state <= EXEC_AF_CAST_WAIT;
                end if;
            when EXEC_AF_AF_FIRE =>
                next_state <= EXEC_AF_AF_WAIT;
            when EXEC_AF_AF_WAIT =>
                if (af_valid = '1') then
                    next_state <= EXEC_AF_WRITE;
                else
                    next_state <= EXEC_AF_AF_WAIT;
                end if;
            when EXEC_AF_WRITE =>
                next_state <= DONE;                         
            
            -- EW_MUL
            when EXEC_EW_MUL_READ =>
                next_state <= EXEC_EW_MUL_FIRE;
            when EXEC_EW_MUL_FIRE =>
                next_state <= EXEC_EW_MUL_WAIT;
            when EXEC_EW_MUL_WAIT =>
                if (ew_mul_valid = '1') then
                    next_state <= EXEC_EW_MUL_WRITE;
                else
                    next_state <= EXEC_EW_MUL_WAIT;
                end if;
            when EXEC_EW_MUL_WRITE =>
                if (ew_mul_write_idx < EW_MUL_BANK_GROUPS-1) then
                    next_state <= EXEC_EW_MUL_WRITE;
                else
                    next_state <= DONE;
                end if;
                            
            -- RD_SBK
            when EXEC_RD_SBK_READ =>
                next_state <= EXEC_RD_SBK_WRITE;
            when EXEC_RD_SBK_WRITE =>
                next_state <= DONE;
            
            -- COPY_BKGB
            when EXEC_COPY_BKGB_READ =>
                next_state <= EXEC_COPY_BKGB_WRITE;
            when EXEC_COPY_BKGB_WRITE =>
                next_state <= DONE;
            
            -- COPY_GBBK
            when EXEC_COPY_GBBK_READ =>
                next_state <= EXEC_COPY_GBBK_WRITE;
            when EXEC_COPY_GBBK_WRITE =>
                next_state <= DONE;            
            
            -- DONE
            when DONE => 
                next_state <= IDLE;
            
            -- ERROR
            when ERROR =>
                next_state <= IDLE;
            
            when others => 
                next_state <= ERROR;
        
        end case;
    
    end process;
    
    -- outputs process (3)
    p_output : process(clk, rst_n)
    begin
        if rst_n = '0' then        
            
            -- shared buffer
            shared_addr <= (others => '0');
            shared_din  <= (others => '0');
            shared_en   <= '0';
            shared_we   <= (others => '0');
            
            -- pim_cmd fields latch
            uop_reg     <= (others => '0');
            ch_id_reg   <= (others => '0');
            ch_mask_reg <= (others => '0');
            bk_reg      <= (others => '0');
            ro_reg      <= (others => '0');
            co_reg      <= (others => '0');
            gb_reg      <= (others => '0');
            rs_reg      <= (others => '0');
            rd_reg      <= (others => '0');
            regid_reg   <= (others => '0');
            opid_reg    <= '0';
            afid_reg    <= (others => '0');
            
            -- pim done signal
            pim_done_pulse <= '0';
            
            -- GBUF
            gbuf_en      <= '0';
            gbuf_wr_en   <= '0';
            gbuf_addr    <= (others => '0');
            gbuf_wr_data <= (others => '0');
            
            -- accumulation regs
            acc_regs_en      <= '0';
            acc_regs_wr_en   <= '0';
            acc_regs_addr    <= (others => '0');
            acc_regs_wr_data <= (others => '0');
            
            -- pim
            pim_bank_bank_sel    <= (others => '0');
            pim_bank_en          <= '0';        
            pim_bank_wr_en       <= '0';
            pim_bank_wr_all      <= '0';
            pim_bank_addr        <= (others => '0');
            pim_bank_wr_data     <= (others => '0');       
            
            -- mac units
            mac_en_pulse      <= '0';
            mac_mode          <= '0';
            mac_gbuf_data     <= (others => '0');
            mac_bank_data_all <= (others => '0');
            mac_acc_init_all  <= (others => '0');
            
            -- af units
            af_en_pulse    <= '0';
            af_input_x_all <= (others => '0');
            af_af_sel      <= (others => '0');
            
            -- casting units
            cast_en_pulse      <= '0';
            cast_fp32_data_all <= (others => '0');
            
            -- ew_mul_groups units
            ew_mul_en_pulse          <= '0';
            ew_mul_bank_data_all     <= (others => '0');
            ew_mul_result_groups_reg <= (others => '0');
                             
        elsif rising_edge(clk) then

            shared_en       <= '0'; -- only enable shared buff when needed
            shared_we       <= (others => '0');
            gbuf_en         <= '0';
            gbuf_wr_en      <= '0';
            acc_regs_en     <= '0';
            acc_regs_wr_en  <= '0';
            pim_bank_en     <= '0';
            pim_bank_wr_en  <= '0';
            pim_bank_wr_all <= '0';
            mac_en_pulse    <= '0';
            af_en_pulse     <= '0';
            cast_en_pulse   <= '0';
            ew_mul_en_pulse <= '0';
            
            pim_done_pulse <= '0'; -- entity output      
                        
            -- idle, reset outputs
            if (curr_state = IDLE) then          
                
                -- shared buffer
                shared_addr <= (others => '0');
                shared_din  <= (others => '0');
                shared_en   <= '0';
                shared_we   <= (others => '0');
                
                -- pim_cmd fields latch
                uop_reg     <= (others => '0');
                ch_id_reg   <= (others => '0');
                ch_mask_reg <= (others => '0');
                bk_reg      <= (others => '0');
                ro_reg      <= (others => '0');
                co_reg      <= (others => '0');
                gb_reg      <= (others => '0');
                rs_reg      <= (others => '0');
                rd_reg      <= (others => '0');
                regid_reg   <= (others => '0');
                opid_reg    <= '0';
                afid_reg    <= (others => '0'); 
                
                -- pim done signal
                pim_done_pulse <= '0';
                
                -- GBUF
                gbuf_en      <= '0';
                gbuf_wr_en   <= '0';
                gbuf_addr    <= (others => '0');
                gbuf_wr_data <= (others => '0');
                
                -- accumulation regs
                acc_regs_en      <= '0';
                acc_regs_wr_en   <= '0';
                acc_regs_addr    <= (others => '0');
                acc_regs_wr_data <= (others => '0');
                
                -- pim
                pim_bank_bank_sel    <= (others => '0');
                pim_bank_en          <= '0';        
                pim_bank_wr_en       <= '0';
                pim_bank_wr_all      <= '0';
                pim_bank_addr        <= (others => '0');
                pim_bank_wr_data     <= (others => '0');        
                         
                -- mac units
                mac_en_pulse      <= '0';
                mac_mode          <= '0';
                mac_gbuf_data     <= (others => '0');
                mac_bank_data_all <= (others => '0');
                mac_acc_init_all  <= (others => '0');
                
                -- af units
                af_en_pulse    <= '0';
                af_input_x_all <= (others => '0');
                af_af_sel      <= (others => '0');   
                
                -- casting units
                cast_en_pulse      <= '0';
                cast_fp32_data_all <= (others => '0');    
                
                -- ew_mul_groups units
                ew_mul_en_pulse          <= '0';
                ew_mul_bank_data_all     <= (others => '0');
                ew_mul_result_groups_reg <= (others => '0');
            end if;
            
            if (next_state = DECODE) then
                -- latch pim_cmd fields when about to go to DECODE
                -- Latch PIM micro-op into its respective local fields. PIM commands are exactly like original ones handled by cmd_engine but with OPsize already handled by cmd_engine 
                uop_reg     <= pim_cmd(63 downto 60);
                
                case pim_cmd(63 downto 60) is                
                    -- WR_SBK CHid OPsize BK RO CO Rs (Shared Buffer -> PIM Banks)
                    -- e.g. 0010_XXXXX_XXXXXXXXXX_XXXX_XXXX_XXXXXX_XXXXXXXXXXXXXX_00000000000000000
                    when x"2" =>
                        ch_id_reg <= pim_cmd(59 downto 55);
                        bk_reg    <= pim_cmd(44 downto 41);
                        ro_reg    <= pim_cmd(40 downto 37);
                        co_reg    <= pim_cmd(36 downto 31);
                        rs_reg    <= pim_cmd(30 downto 17);                        
            
                    -- RD_SBK CHid OPsize BK RO CO Rd (PIM Banks -> Shared Buffer)
                    -- e.g. 0011_XXXXX_XXXXXXXXXX_XXXX_XXXX_XXXXXX_XXXXXXXXXXXXXX_00000000000000000
                    when x"3" =>
                        ch_id_reg <= pim_cmd(59 downto 55);
                        bk_reg    <= pim_cmd(44 downto 41);
                        ro_reg    <= pim_cmd(40 downto 37);
                        co_reg    <= pim_cmd(36 downto 31);
                        rd_reg    <= pim_cmd(30 downto 17);
            
                    -- NOTE: The WR_ABK instruction is made slightly different than the paper by removing the Regid field in the paper, seems unrelated to the instruction description
                    -- WR_ABK CHid RO CO Rs (Shared Buffer -> All 16 PIM Banks)
                    -- e.g. 0100_XXXXX_XXXX_XXXXXX_XXXXXXXXXXXXXX_0000000000000000000000000000000 
                    when x"4" =>
                        ch_id_reg <= pim_cmd(59 downto 55);
                        ro_reg    <= pim_cmd(54 downto 51);
                        co_reg    <= pim_cmd(50 downto 45);
                        rs_reg    <= pim_cmd(44 downto 31);

                    -- NOTE: The COPY_BKGB instruction is made slightly different than the paper by adding a BK field to select which bank is data copied from and Gb to select gbuff address instead of sharing CO between pim banks and gbuff
                    -- COPY_BKGB CHmask OPsize BK RO CO Gb (PIM Banks -> Global Buffer)
                    -- e.g. 0101_XXXXX_XXXXXXXXXX_XXXX_XXXX_XXXXXX_XXXXXX_0000000000000000000000000
                    when x"5" =>
                        ch_mask_reg <= pim_cmd(59 downto 55);
                        bk_reg      <= pim_cmd(44 downto 41);
                        ro_reg      <= pim_cmd(40 downto 37);
                        co_reg      <= pim_cmd(36 downto 31);
                        gb_reg      <= pim_cmd(30 downto 25);
            
                    -- NOTE: The COPY_GBBK instruction is made slightly different than the paper by adding a BK field to select which bank is data copied to and Gb to select gbuff address instead of sharing CO between pim banks and gbuff
                    -- COPY_GBBK CHmask OPsize BK RO CO Gb (Global Buffer -> PIM Banks)
                    -- e.g. 0110_XXXXX_XXXXXXXXXX_XXXX_XXXX_XXXXXX_XXXXXX_0000000000000000000000000
                    when x"6" =>
                        ch_mask_reg <= pim_cmd(59 downto 55);
                        bk_reg      <= pim_cmd(44 downto 41);
                        ro_reg      <= pim_cmd(40 downto 37);
                        co_reg      <= pim_cmd(36 downto 31);
                        gb_reg      <= pim_cmd(30 downto 25);
            
                    -- NOTE: The WR_BIAS instruction is made slightly different than the paper by adding Regid, allowing for more control over PU reg file initialization.
                    -- WR_BIAS CHmask Rs Regid (Shared Buffer -> PIM PU Accumulation Regs)
                    -- e.g. 0111_XXXXX_XXXXXXXXXXXXXX_XXXXX_000000000000000000000000000000000000            
                    when x"7" =>
                        ch_mask_reg <= pim_cmd(59 downto 55);
                        rs_reg      <= pim_cmd(54 downto 41);
                        regid_reg   <= pim_cmd(40 downto 36);
            
                    -- RD_MAC CHmask Rd Regid (PIM PU Accumulation Regs -> Shared Buffer)
                    -- e.g. 1000_XXXXX_XXXXXXXXXXXXXX_XXXXX_000000000000000000000000000000000000            
                    when x"8" =>
                        ch_mask_reg <= pim_cmd(59 downto 55);
                        rd_reg      <= pim_cmd(54 downto 41);
                        regid_reg   <= pim_cmd(40 downto 36);
            
                    -- NOTE: The WR_GB instruction is made slightly different than the paper by changing CO to Gb, CO selects col in pim banks and is decoupled from gbuff, added Gb for gbuff address
                    -- WR_GB CHmask OPsize Gb Rs (Shared Buffer -> Global Buffer)
                    -- e.g. 1001_XXXXX_XXXXXXXXXX_XXXXXX_XXXXXXXXXXXXXX_0000000000000000000000000                        
                    when x"9" =>
                        ch_mask_reg <= pim_cmd(59 downto 55);
                        gb_reg      <= pim_cmd(44 downto 39);
                        rs_reg      <= pim_cmd(38 downto 25);
            
                    -- NOTE: The MAC_ABK instruction is made slightly different than the paper by adding OPid, allowing for choosing GEMV vs Vector dot Product in MAC units and adding Gb to decouple pim cols from gbuff address
                    -- MAC_ABK CHmask OPsize RO CO Gb OPid Regid (Global Buffer * PIM Banks -> PIM PU Accumulation Regs)
                    -- e.g. 1010_XXXXX_XXXXXXXXXX_XXXX_XXXXXX_XXXXXX_X_XXXXX_00000000000000000000000
                    when x"A" =>
                        ch_mask_reg <= pim_cmd(59 downto 55);
                        ro_reg      <= pim_cmd(44 downto 41);
                        co_reg      <= pim_cmd(40 downto 35);
                        gb_reg      <= pim_cmd(34 downto 29);
                        opid_reg    <= pim_cmd(28);
                        regid_reg   <= pim_cmd(27 downto 23);                        
            
                    -- EW_MUL CHmask OPsize RO CO (Element-wise Mult in PIM Bank Groups)
                    -- e.g. 1011_XXXXX_XXXXXXXXXX_XXXX_XXXXXX_00000000000000000000000000000000000
                    when x"B" =>
                        ch_mask_reg <= pim_cmd(59 downto 55);
                        ro_reg      <= pim_cmd(44 downto 41);
                        co_reg      <= pim_cmd(40 downto 35);
            
                    -- AF CHmask AFid Regid (Apply activation function to PIM PU Accumulation Regs)
                    -- e.g. 1100_XXXXX_XXX_XXXXX_00000000000000000000000000000000000000000000000            
                    when x"C" =>
                        ch_mask_reg <= pim_cmd(59 downto 55);
                        afid_reg    <= pim_cmd(54 downto 52);
                        regid_reg   <= pim_cmd(51 downto 47);
            
                    when others =>
                        -- NOP                
                
                end case;    
            end if;
            
            -- entering EXEC_WR_GB_READ so enable SBUFF so that data is ready on the state after, e.g. (EXEC_WR_GB_WRITE) (sbuff bram has 1 cycle read delay)
            -- logic applies to all similar instructions where SBUFF reading is needed
            if (next_state = EXEC_WR_SBK_READ or next_state = EXEC_WR_ABK_READ or next_state = EXEC_WR_GB_READ or next_state = EXEC_WR_BIAS_READ) then
                shared_en   <= '1';
                shared_addr <= std_logic_vector(resize(unsigned(rs_reg) * SHARED_BUFF_WORD_BYTES, shared_addr'length));
            end if;

            if (curr_state = EXEC_WR_SBK_WRITE) then
                -- Write shared_dout data to Single Bank. shared_dout should be correct after it was stable during the curr_state = EXEC_WR_SBK_READ cycle.
                pim_bank_en       <= '1';
                pim_bank_wr_en    <= '1';
                pim_bank_bank_sel <= bk_reg;
                pim_bank_addr     <= ro_reg & co_reg;
                pim_bank_wr_data  <= shared_dout;
            end if;
            
            if (curr_state = EXEC_WR_ABK_WRITE) then
                -- Write shared_dout replicated lane i data to bank i. shared_dout should be correct after it was stable during the curr_state = EXEC_WR_ABK_READ cycle.
                pim_bank_en       <= '1';
                pim_bank_wr_en    <= '1';
                pim_bank_wr_all   <= '1';
                pim_bank_addr     <= ro_reg & co_reg;
                pim_bank_wr_data  <= shared_dout;
            end if;
                        
            if (curr_state = EXEC_WR_GB_WRITE) then
                -- Write shared_dout data to GBUF. shared_dout should be correct after it was stable during the curr_state = EXEC_WR_GB_READ cycle.
                gbuf_en      <= '1';
                gbuf_wr_en   <= '1';
                gbuf_addr    <= gb_reg;
                gbuf_wr_data <= shared_dout;                
            end if;
            
            if (curr_state = EXEC_WR_BIAS_WRITE) then
                -- Write shared_dout data to all acc regs. shared_dout should be correct after it was stable during the curr_state = EXEC_WR_BIAS_READ cycle.
                acc_regs_en      <= '1';
                acc_regs_wr_en   <= '1';
                acc_regs_addr    <= regid_reg;
                acc_regs_wr_data <= shared_dout_padded; -- Write 16xFP32 version of SBUF data
            end if;

            -- entering EXEC_RD_MAC_READ so enable acc reg file so that data is ready on the state after, i.e. (EXEC_RD_MAC_CAST_FIRE) (acc reg file has 1 cycle read delay)         
            if (next_state = EXEC_RD_MAC_READ) then
                acc_regs_en   <= '1';
                acc_regs_addr <= regid_reg;
            end if;
         
            -- entering EXEC_AF_READ so enable reg file so that data is ready on the state after, i.e. (EXEC_AF_AF_CAST_FIRE) (acc regfile have 1 cycle read delay)
            if (next_state = EXEC_AF_READ) then
                acc_regs_en   <= '1';
                acc_regs_addr <= regid_reg;
            end if;         
            
            -- Data is now stable from the regfile (acc_reg_rd_data). Fire the caster                        
            if (curr_state = EXEC_RD_MAC_CAST_FIRE or curr_state = EXEC_AF_CAST_FIRE) then
                cast_en_pulse <= '1';
                cast_fp32_data_all <= acc_regs_rd_data;
            end if;
            
            if (curr_state = EXEC_RD_MAC_CAST_WAIT or curr_state = EXEC_AF_CAST_WAIT) then
                if (cast_valid = '1') then
                    -- Cast result MUST be captured right when cast_valid becomes '1' because cast units are free running pipeline and result changes on every clock cycle
                    acc_regs_rd_data_casted <= cast_bf16_data_all;
                end if;
            end if;            
          
            if (curr_state = EXEC_RD_MAC_WRITE) then
                shared_en   <= '1';
                shared_we   <= (others => '1');
                shared_addr <= std_logic_vector(resize(unsigned(rd_reg) * SHARED_BUFF_WORD_BYTES, shared_addr'length));
                shared_din  <= acc_regs_rd_data_casted;
            end if;
            
            if (curr_state = EXEC_AF_AF_FIRE) then
                af_en_pulse    <= '1';
                af_af_sel      <= afid_reg;
                af_input_x_all <= acc_regs_rd_data_casted;                
            end if;
            
            if (curr_state = EXEC_AF_AF_WAIT) then
                if (af_valid = '1') then
                    -- AF result MUST be captured right when af_valid becomes '1' because AF units are free running pipeline and result changes on every clock cycle
                    acc_regs_wr_data <= af_result_all_padded;  -- Write 16xFP32 version of AF units results             
                end if;
            end if;
            
            if (curr_state = EXEC_AF_WRITE) then
                acc_regs_en      <= '1';
                acc_regs_wr_en   <= '1';
                acc_regs_addr    <= regid_reg;
                -- data is captured in wait 
            end if;                 
                                    
            -- entering EXEC_MAC_ABK_READ so enable GBUF, pim banks, and reg file so that data is ready on the state after, i.e. (EXEC_MAC_ABK_MAC_FIRE) (gbuff spram, banks spram, and acc regfile have 1 cycle read delay)
            if (next_state = EXEC_MAC_ABK_READ) then
                gbuf_en   <= '1';
                gbuf_addr <= gb_reg;
                
                pim_bank_en   <= '1';
                pim_bank_addr <= ro_reg & co_reg; -- pim banks are not real 2D, build from ro and co
                
                acc_regs_en   <= '1';
                acc_regs_addr <= regid_reg;
            end if;

            if (curr_state = EXEC_MAC_ABK_MAC_FIRE) then
                mac_en_pulse      <= '1';
                mac_mode          <= opid_reg; -- '0' = GEMV, '1' = vector dot product
                mac_gbuf_data     <= gbuf_rd_data;
                mac_bank_data_all <= pim_bank_rd_data_all;
                mac_acc_init_all  <= acc_regs_rd_data; -- use the 16xFP32 acc reg data because mac unit acc_init is expecting 16xFP32                 
            end if;
            
            if (curr_state = EXEC_MAC_ABK_MAC_WAIT) then
                if (mac_valid = '1') then
                    -- MAC result MUST be captured right when mac_valid becomes '1' because MAC units are free running pipeline and result changes on every clock cycle
                    acc_regs_wr_data <= mac_result_all; -- MAC units results are already 16xFP32                
                end if;
            end if;
            
            if (curr_state = EXEC_MAC_ABK_WRITE) then
                acc_regs_en      <= '1';
                acc_regs_wr_en   <= '1';
                acc_regs_addr    <= regid_reg;
                -- data is captured in wait 
            end if;
            
            -- entering EXEC_EW_MUL_READ so enable pim banks so that data is ready on the state after, i.e. (EXEC_EW_MUL_FIRE) (pim banks/xpm spram has 1 cycle read delay)
            if (next_state = EXEC_EW_MUL_READ) then
                pim_bank_en   <= '1';
                pim_bank_addr <= ro_reg & co_reg; -- pim banks are not real 2D, build from ro and co
            end if;
            
            if (curr_state = EXEC_EW_MUL_FIRE) then
                ew_mul_en_pulse <= '1';
                ew_mul_bank_data_all <= pim_bank_rd_data_all;
            end if;
            
            if (curr_state = EXEC_EW_MUL_WAIT) then
                if (ew_mul_valid = '1') then
                    -- EW MUL result MUST be captured right when ew_mul_valid becomes '1' because EW MUL units are free running pipeline and result changes on every clock cycle
                    ew_mul_result_groups_reg <= ew_mul_result_groups;
                end if;
            end if;
            
            if (curr_state = EXEC_EW_MUL_WRITE) then
                -- Write ew_mul_result_groups_reg corresponding 16 BF16 values data to target bank.
                -- Lower 16 BF16 values to bank 2, next 16 BF16 values to bank 6, etc.
                pim_bank_en       <= '1';
                pim_bank_wr_en    <= '1';
                pim_bank_bank_sel <= std_logic_vector(to_unsigned(ew_mul_write_idx*EW_MUL_BANKS_PER_GROUP+EW_MUL_RESULT_BANK_OFFSET, pim_bank_bank_sel'length));
                pim_bank_addr     <= ro_reg & co_reg;
                pim_bank_wr_data  <= ew_mul_result_groups_reg((ew_mul_write_idx+1)*PIM_BANK_DATA_WIDTH-1 downto ew_mul_write_idx*PIM_BANK_DATA_WIDTH);
            end if;
                        
            -- entering EXEC_RD_SBK_READ so enable pim banks so that data is ready on the state after, i.e. (EXEC_RD_SBK_WRITE) (pim banks/xpm spram has 1 cycle read delay)
            if (next_state = EXEC_RD_SBK_READ) then
                pim_bank_bank_sel <= bk_reg;
                pim_bank_en       <= '1';
                pim_bank_addr     <= ro_reg & co_reg;                
            end if;
            
            if (curr_state = EXEC_RD_SBK_WRITE) then
                shared_en   <= '1';
                shared_we   <= (others => '1');
                shared_addr <= std_logic_vector(resize(unsigned(rd_reg) * SHARED_BUFF_WORD_BYTES, shared_addr'length));
                shared_din  <= pim_bank_rd_data;                
            end if;
            
            -- entering EXEC_COPY_BKGB_READ so enable pim banks so that data is ready on the state after, i.e. (EXEC_COPY_BKGB_WRITE) (pim banks/xpm spram has 1 cycle read delay)
            if (next_state = EXEC_COPY_BKGB_READ) then
                pim_bank_bank_sel <= bk_reg;
                pim_bank_en       <= '1';
                pim_bank_addr     <= ro_reg & co_reg;
            end if;
            
            if (curr_state = EXEC_COPY_BKGB_WRITE) then
                gbuf_en      <= '1';
                gbuf_wr_en   <= '1';
                gbuf_addr    <= gb_reg;
                gbuf_wr_data <= pim_bank_rd_data;
            end if;      
                 
            -- entering EXEC_COPY_GBBK_READ so enable GBUF so that data is ready on the state after, i.e. (EXEC_COPY_GBBK_WRITE) (GBUF/xpm spram has 1 cycle read delay)
            if (next_state = EXEC_COPY_GBBK_READ) then
                gbuf_en   <= '1';
                gbuf_addr <= gb_reg;
            end if;
            
            if (curr_state = EXEC_COPY_GBBK_WRITE) then
                pim_bank_en       <= '1';
                pim_bank_wr_en    <= '1';
                pim_bank_wr_all   <= '0';
                pim_bank_bank_sel <= bk_reg;
                pim_bank_addr     <= ro_reg & co_reg;
                pim_bank_wr_data  <= gbuf_rd_data;
            end if;                    

            if (curr_state = ERROR) then
                -- TODO: Add error logic that propagates to cmd_engine
            end if;
            
            if (curr_state = DONE) then
                pim_done_pulse <= '1';
            end if;
        
        end if;
    end process;    
    
    -- ewmul bank group write counter process (4)
    p_ew_mul_idx_cnt : process(clk, rst_n)
        begin
            if rst_n = '0' then
                ew_mul_write_idx <= 0;
            elsif rising_edge(clk) then
                if curr_state = IDLE then
                    ew_mul_write_idx <= 0;
                elsif curr_state = EXEC_EW_MUL_WAIT and ew_mul_valid = '1' then
                    ew_mul_write_idx <= 0;
                elsif curr_state = EXEC_EW_MUL_WRITE then
                    if ew_mul_write_idx < EW_MUL_BANK_GROUPS - 1 then
                        ew_mul_write_idx <= ew_mul_write_idx + 1;
                    end if;
                end if;
            end if;
        end process;
        
    ------------
    
    -- GBUF            
    u_gbuf : xpm_memory_spram
    generic map (
        ADDR_WIDTH_A => GLOBAL_BUFF_ADDR_WIDTH,              -- DECIMAL
        AUTO_SLEEP_TIME => 0,           -- DECIMAL
        BYTE_WRITE_WIDTH_A => GLOBAL_BUFF_DATA_WIDTH,       -- DECIMAL
        CASCADE_HEIGHT => 0,            -- DECIMAL
        ECC_BIT_RANGE => "7:0",         -- String
        ECC_MODE => "no_ecc",           -- String
        ECC_TYPE => "none",             -- String
        IGNORE_INIT_SYNTH => 0,         -- DECIMAL
        MEMORY_INIT_FILE => "none",     -- String
        MEMORY_INIT_PARAM => "0",       -- String
        MEMORY_OPTIMIZATION => "true",  -- String
        MEMORY_PRIMITIVE => "block",     -- String
        MEMORY_SIZE => (2**GLOBAL_BUFF_ADDR_WIDTH) * GLOBAL_BUFF_DATA_WIDTH, -- DECIMAL 2KB (256 wide, 64 deep)
        MESSAGE_CONTROL => 0,           -- DECIMAL
        RAM_DECOMP => "auto",           -- String
        READ_DATA_WIDTH_A => GLOBAL_BUFF_DATA_WIDTH,        -- DECIMAL
        READ_LATENCY_A => 1,            -- DECIMAL
        READ_RESET_VALUE_A => "0",      -- String
        RST_MODE_A => "SYNC",           -- String
        SIM_ASSERT_CHK => 0,            -- DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        USE_MEM_INIT => 1,              -- DECIMAL
        USE_MEM_INIT_MMI => 0,          -- DECIMAL
        WAKEUP_TIME => "disable_sleep", -- String
        WRITE_DATA_WIDTH_A => GLOBAL_BUFF_DATA_WIDTH,       -- DECIMAL
        WRITE_MODE_A => "read_first",   -- String
        WRITE_PROTECT => 1              -- DECIMAL
    )
    port map (
       douta => gbuf_rd_data,            -- READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
       addra => gbuf_addr,                   -- ADDR_WIDTH_A-bit input: Address for port A write and read operations.
       clka => clk,                     -- 1-bit input: Clock signal for port A.
       dina => gbuf_wr_data,                     -- WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
       ena => gbuf_en, -- 1-bit input: Memory enable signal for port A. Must be high on clock cycles when read or write operations
                                         -- are initiated. Pipelined internally.
    
       injectdbiterra => '0', -- 1-bit input: Controls double bit error injection on input data when ECC enabled (Error injection
                                         -- capability is not available in "decode_only" mode).
    
       injectsbiterra => '0', -- 1-bit input: Controls single bit error injection on input data when ECC enabled (Error injection
                                         -- capability is not available in "decode_only" mode).
    
       regcea => '1',                 -- 1-bit input: Clock Enable for the last register stage on the output data path.
       rsta => rst,                     -- 1-bit input: Reset signal for the final port A output register stage. Synchronously resets output port
                                         -- douta to the value specified by parameter READ_RESET_VALUE_A.
    
       sleep => '0',                   -- 1-bit input: sleep signal to enable the dynamic power saving feature.
       wea(0) => (gbuf_wr_en and gbuf_en)   -- WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector for port A input data port dina. 1
                                         -- bit wide when word-wide writes are used. In byte-wide write configurations, each bit controls the writing
                                         -- one byte of dina to address addra. For example, to synchronously write only bits [15-8] of dina when
                                         -- WRITE_DATA_WIDTH_A is 32, wea would be 4'b0010.
    );
    
    ------------
    
    -- Acc register file
    -- This reg file "concatenates" the 16-bit wide regfile for reach near-bank PU described in the paper into a centralized 512-bit wide regfile (16 banks each acc reg is FP32)
    -- ARCHITECTURAL MAPPING (CENT Paper)
    --
    -- For NUM_BANKS = 16:
    -- Physical Architecture: 1 GDDR6-PIM channel = 16 memory banks.
    -- Each bank has 1 near-bank Processing Unit (PU).
    -- Each PU contains 32 accumulation registers (32-bits wide FP32 each) to hold 
    -- the scalar sum from its 16-MAC reduction tree.
    --
    -- VHDL Implementation: This SPRAM concatenates those 16 physically distributed 
    -- 32-bit register files into a single, centralized 512-bit wide register file.
    -- Reading or writing a 512-bit word at a given Regid here is functionally 
    -- equivalent to accessing the 32-bit register at that Regid across all 16 PUs.
    u_acc_regs : xpm_memory_spram
    generic map (
        ADDR_WIDTH_A => ACC_REGS_ADDR_WIDTH,              -- DECIMAL
        AUTO_SLEEP_TIME => 0,           -- DECIMAL
        BYTE_WRITE_WIDTH_A => ACC_REGS_DATA_WIDTH,       -- DECIMAL
        CASCADE_HEIGHT => 0,            -- DECIMAL
        ECC_BIT_RANGE => "7:0",         -- String
        ECC_MODE => "no_ecc",           -- String
        ECC_TYPE => "none",             -- String
        IGNORE_INIT_SYNTH => 0,         -- DECIMAL
        MEMORY_INIT_FILE => "none",     -- String
        MEMORY_INIT_PARAM => "0",       -- String
        MEMORY_OPTIMIZATION => "true",  -- String
        MEMORY_PRIMITIVE => "block",     -- String
        MEMORY_SIZE => (2**ACC_REGS_ADDR_WIDTH) * ACC_REGS_DATA_WIDTH, -- DECIMAL 2KB (512 wide, 32 deep)
        MESSAGE_CONTROL => 0,           -- DECIMAL
        RAM_DECOMP => "auto",           -- String
        READ_DATA_WIDTH_A => ACC_REGS_DATA_WIDTH,        -- DECIMAL
        READ_LATENCY_A => 1,            -- DECIMAL
        READ_RESET_VALUE_A => "0",      -- String
        RST_MODE_A => "SYNC",           -- String
        SIM_ASSERT_CHK => 0,            -- DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        USE_MEM_INIT => 1,              -- DECIMAL
        USE_MEM_INIT_MMI => 0,          -- DECIMAL
        WAKEUP_TIME => "disable_sleep", -- String
        WRITE_DATA_WIDTH_A => ACC_REGS_DATA_WIDTH,       -- DECIMAL
        WRITE_MODE_A => "read_first",   -- String
        WRITE_PROTECT => 1              -- DECIMAL
    )
    port map (
       douta => acc_regs_rd_data,            -- READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
       addra => acc_regs_addr,                   -- ADDR_WIDTH_A-bit input: Address for port A write and read operations.
       clka => clk,                     -- 1-bit input: Clock signal for port A.
       dina => acc_regs_wr_data,                     -- WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
       ena => acc_regs_en, -- 1-bit input: Memory enable signal for port A. Must be high on clock cycles when read or write operations
                                         -- are initiated. Pipelined internally.
    
       injectdbiterra => '0', -- 1-bit input: Controls double bit error injection on input data when ECC enabled (Error injection
                                         -- capability is not available in "decode_only" mode).
    
       injectsbiterra => '0', -- 1-bit input: Controls single bit error injection on input data when ECC enabled (Error injection
                                         -- capability is not available in "decode_only" mode).
    
       regcea => '1',                 -- 1-bit input: Clock Enable for the last register stage on the output data path.
       rsta => rst,                     -- 1-bit input: Reset signal for the final port A output register stage. Synchronously resets output port
                                         -- douta to the value specified by parameter READ_RESET_VALUE_A.
    
       sleep => '0',                   -- 1-bit input: sleep signal to enable the dynamic power saving feature.
       wea(0) => (acc_regs_wr_en and acc_regs_en) -- WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector for port A input data port dina. 1
                                         -- bit wide when word-wide writes are used. In byte-wide write configurations, each bit controls the writing
                                         -- one byte of dina to address addra. For example, to synchronously write only bits [15-8] of dina when
                                         -- WRITE_DATA_WIDTH_A is 32, wea would be 4'b0010.
    );
    
    ------------
    
    -- PIM banks
    u_pim_banks : pim_banks
    generic map (
        NUM_BANKS  => PIM_BANK_NUM_BANKS,
        LANE_NUMS  => PIM_BANK_LANE_NUMS,
        LANE_WIDTH => PIM_BANK_LANE_WIDTH,
        ADDR_WIDTH => PIM_BANK_ADDR_WIDTH
    )
    port map (
        clk         => clk,
        rst_n       => rst_n,
        bank_sel    => pim_bank_bank_sel,
        en          => pim_bank_en,
        wr_en       => pim_bank_wr_en,
        wr_all      => pim_bank_wr_all,
        addr        => pim_bank_addr,
        wr_data     => pim_bank_wr_data,
        rd_data     => pim_bank_rd_data,
        rd_data_all => pim_bank_rd_data_all
    );    
    
    ------------

    -- MAC units
    u_mac_units : mac_units
    generic map(
        NUM_BANKS         => PIM_BANK_NUM_BANKS,
        LANE_NUMS         => MAC_LANE_NUMS,
        INPUT_LANE_WIDTH  => MAC_INPUT_LANE_WIDTH, 
        RESULT_LANE_WIDTH => MAC_RESULT_LANE_WIDTH
    )
    port map(
        clk           => clk,
        rst_n         => rst_n,
        en_pulse      => mac_en_pulse,
        mode          => mac_mode,
        gbuf_data     => mac_gbuf_data,
        bank_data_all => mac_bank_data_all,
        acc_init_all  => mac_acc_init_all,
        result_all    => mac_result_all,
        valid         => mac_valid
    );

    ------------
    
    -- AF units
    u_af_units: af_units
    generic map(
        NUM_BANKS       => PIM_BANK_NUM_BANKS,
        AC_FCNS_NUM     => 5,
        ROM_ADDR_WIDTH  => 12,
        ROM_DATA_WIDTH  => 32,
        FRACTION_WIDTH  => 6,
        LANE_WIDTH      => MAC_INPUT_LANE_WIDTH
        
    )
    port map( 
        clk         => clk,
        rst_n       => rst_n,
        en_pulse    => af_en_pulse,
        input_x_all => af_input_x_all,
        af_sel      => af_af_sel,
        result_all  => af_result_all,
        valid       => af_valid
     );     

    ------------
    
    -- Padding (FP32 casting) for 16xBF16 signals that are to be written to acc regs
    gen_acc_regs_padding: for i in 0 to PIM_BANK_NUM_BANKS-1 generate
        -- Pad Shared Buffer read data (for WR_BIAS)
        shared_dout_padded(((i+1)*MAC_RESULT_LANE_WIDTH)-1 downto i*MAC_RESULT_LANE_WIDTH) <= 
            shared_dout(((i+1)*MAC_INPUT_LANE_WIDTH)-1 downto i*MAC_INPUT_LANE_WIDTH) & x"0000";
        
        -- Pad AF units results (for AF)
        af_result_all_padded(((i+1)*MAC_RESULT_LANE_WIDTH)-1 downto i*MAC_RESULT_LANE_WIDTH) <= 
            af_result_all(((i+1)*MAC_INPUT_LANE_WIDTH)-1 downto i*MAC_INPUT_LANE_WIDTH) & x"0000";        
    end generate;
    
    ------------

    -- Casting (BF16 casting) from 16xFP32 (acc_reg_rd_data) 
    u_fp32_to_bf16_units: fp32_to_bf16_units
    generic map(
        NUM_BANKS  => PIM_BANK_NUM_BANKS,
        FP32_WIDTH => MAC_RESULT_LANE_WIDTH,
        BF16_WIDTH => MAC_INPUT_LANE_WIDTH  
    )
    port map(
        clk           => clk,
        en_pulse      => cast_en_pulse, 
        fp32_data_all => cast_fp32_data_all,
        bf16_data_all => cast_bf16_data_all,
        valid         => cast_valid
    );
    
    ------------
    
    -- EW_MUL groups
    u_ew_mul_groups : ew_mul_groups
    generic map(
        NUM_BANKS   => PIM_BANK_NUM_BANKS,
        BANK_GROUPS => EW_MUL_BANK_GROUPS,
        LANE_NUMS   => PIM_BANK_LANE_NUMS,
        LANE_WIDTH  => PIM_BANK_LANE_WIDTH
    )
    port map(
        clk           => clk,
        en_pulse      => ew_mul_en_pulse,
        bank_data_all => ew_mul_bank_data_all,
        result_groups => ew_mul_result_groups,
        valid         => ew_mul_valid
    );    
    
end Behavioral;
