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

entity pim_banks is
    generic (
        NUM_BANKS   : integer := 16;
        LANE_NUMS   : integer := 16;
        LANE_WIDTH  : integer := 16;
        ADDR_WIDTH  : integer := 10 -- 32KB (256 wide, 1024 deep): 1024 locations
    );

    port ( 
        clk   : in std_logic;
        rst_n : in std_logic;
            
        bank_sel    : in  std_logic_vector(3 downto 0); --log2(16), 16 banks
        en          : in  std_logic;            
        wr_en       : in  std_logic;
        wr_all      : in  std_logic; -- Writes bank i with LANE_NUMS replicas of lane i of wr_data, ignore bank_sel
            
        addr        : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        wr_data     : in  std_logic_vector((LANE_NUMS*LANE_WIDTH)-1 downto 0);
            
        rd_data     : out std_logic_vector((LANE_NUMS*LANE_WIDTH)-1 downto 0); -- Output of selected bank
        rd_data_all : out std_logic_vector((NUM_BANKS*LANE_NUMS*LANE_WIDTH)-1 downto 0) -- Output of all banks for MAC
     ); 
           
end pim_banks;

architecture Behavioral of pim_banks is
    
    constant DATA_WIDTH     : positive := LANE_NUMS * LANE_WIDTH;
    
    -- rst
    signal rst : std_logic;
    
    -- type for holding read/write data for all banks for rd_data_all/wr_all
    type bank_all_array_t is array (0 to NUM_BANKS-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    signal bank_dout : bank_all_array_t;
    signal bank_din  : bank_all_array_t;
    
    -- write enable bits for bank sel
    signal bank_we : std_logic_vector(NUM_BANKS-1 downto 0);
    
    -- Replicate BF16 value to form a vector of DATA_WIDTH ready for the DATA_WIDTH granularity
    function repeat_lane (
        lane : std_logic_vector(LANE_WIDTH-1 downto 0)
    ) return std_logic_vector is
        variable repeated_data : std_logic_vector(DATA_WIDTH-1 downto 0);
    begin
        for j in 0 to LANE_NUMS-1 loop
            repeated_data((j+1)*LANE_WIDTH-1 downto j*LANE_WIDTH) := lane;
        end loop;
        return repeated_data;
    end function;

begin

    -- rst
    rst <= not rst_n;

    -- Generate NUM_BANKS XPM Memories
    gen_banks: for i in 0 to NUM_BANKS-1 generate
    begin
        
        -- Bank data in: if wr_all, bank i receives LANE_NUMS replicas of wr_data lane i, else its just wr_data
        bank_din(i) <= repeat_lane(wr_data((i+1)*LANE_WIDTH-1 downto i*LANE_WIDTH)) when wr_all = '1' else wr_data;        
        
        -- Bank write enable: select if wr_all is high, OR if this specific bank is selected
        bank_we(i) <= '1' when (wr_en = '1') and (en = '1') and (wr_all = '1' or to_integer(unsigned(bank_sel)) = i) else '0';
        
        gen_bram_banks: if i < 4 generate
            u_bram_bank : xpm_memory_spram
            generic map (
                ADDR_WIDTH_A => ADDR_WIDTH,              -- DECIMAL
                AUTO_SLEEP_TIME => 0,           -- DECIMAL
                BYTE_WRITE_WIDTH_A => DATA_WIDTH,       -- DECIMAL
                CASCADE_HEIGHT => 0,            -- DECIMAL
                ECC_BIT_RANGE => "7:0",         -- String
                ECC_MODE => "no_ecc",           -- String
                ECC_TYPE => "none",             -- String
                IGNORE_INIT_SYNTH => 0,         -- DECIMAL
                MEMORY_INIT_FILE => "none",     -- String
                MEMORY_INIT_PARAM => "0",       -- String
                MEMORY_OPTIMIZATION => "true",  -- String
                MEMORY_PRIMITIVE => "block",     -- String
                MEMORY_SIZE => (2**ADDR_WIDTH) * DATA_WIDTH, -- DECIMAL 32KB (256 wide, 1024 deep)
                MESSAGE_CONTROL => 0,           -- DECIMAL
                RAM_DECOMP => "auto",           -- String
                READ_DATA_WIDTH_A => DATA_WIDTH,        -- DECIMAL
                READ_LATENCY_A => 1,            -- DECIMAL
                READ_RESET_VALUE_A => "0",      -- String
                RST_MODE_A => "SYNC",           -- String
                SIM_ASSERT_CHK => 0,            -- DECIMAL; 0=disable simulation messages, 1=enable simulation messages
                USE_MEM_INIT => 1,              -- DECIMAL
                USE_MEM_INIT_MMI => 0,          -- DECIMAL
                WAKEUP_TIME => "disable_sleep", -- String
                WRITE_DATA_WIDTH_A => DATA_WIDTH,       -- DECIMAL
                WRITE_MODE_A => "read_first",   -- String
                WRITE_PROTECT => 1              -- DECIMAL
            )
            port map (
               douta => bank_dout(i),            -- READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
               addra => addr,                   -- ADDR_WIDTH_A-bit input: Address for port A write and read operations.
               clka => clk,                     -- 1-bit input: Clock signal for port A.
               dina => bank_din(i),                     -- WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
               ena => en, -- 1-bit input: Memory enable signal for port A. Must be high on clock cycles when read or write operations
                                                 -- are initiated. Pipelined internally.
            
               injectdbiterra => '0', -- 1-bit input: Controls double bit error injection on input data when ECC enabled (Error injection
                                                 -- capability is not available in "decode_only" mode).
            
               injectsbiterra => '0', -- 1-bit input: Controls single bit error injection on input data when ECC enabled (Error injection
                                                 -- capability is not available in "decode_only" mode).
            
               regcea => '1',                 -- 1-bit input: Clock Enable for the last register stage on the output data path.
               rsta => rst,                     -- 1-bit input: Reset signal for the final port A output register stage. Synchronously resets output port
                                                 -- douta to the value specified by parameter READ_RESET_VALUE_A.
            
               sleep => '0',                   -- 1-bit input: sleep signal to enable the dynamic power saving feature.
               wea(0) => bank_we(i)                 -- WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector for port A input data port dina. 1
                                                 -- bit wide when word-wide writes are used. In byte-wide write configurations, each bit controls the writing
                                                 -- one byte of dina to address addra. For example, to synchronously write only bits [15-8] of dina when
                                                 -- WRITE_DATA_WIDTH_A is 32, wea would be 4'b0010.
            );            
        end generate;
           
        gen_ultra_banks: if i >= 4 generate
            u_ultra_bank : xpm_memory_spram
            generic map (
                ADDR_WIDTH_A => ADDR_WIDTH,              -- DECIMAL
                AUTO_SLEEP_TIME => 0,           -- DECIMAL
                BYTE_WRITE_WIDTH_A => DATA_WIDTH,       -- DECIMAL
                CASCADE_HEIGHT => 0,            -- DECIMAL
                ECC_BIT_RANGE => "7:0",         -- String
                ECC_MODE => "no_ecc",           -- String
                ECC_TYPE => "none",             -- String
                IGNORE_INIT_SYNTH => 0,         -- DECIMAL
                MEMORY_INIT_FILE => "none",     -- String
                MEMORY_INIT_PARAM => "0",       -- String
                MEMORY_OPTIMIZATION => "true",  -- String
                MEMORY_PRIMITIVE => "ultra",     -- String
                MEMORY_SIZE => (2**ADDR_WIDTH) * DATA_WIDTH, -- DECIMAL 32KB (256 wide, 1024 deep)
                MESSAGE_CONTROL => 0,           -- DECIMAL
                RAM_DECOMP => "auto",           -- String
                READ_DATA_WIDTH_A => DATA_WIDTH,        -- DECIMAL
                READ_LATENCY_A => 1,            -- DECIMAL
                READ_RESET_VALUE_A => "0",      -- String
                RST_MODE_A => "SYNC",           -- String
                SIM_ASSERT_CHK => 0,            -- DECIMAL; 0=disable simulation messages, 1=enable simulation messages
                USE_MEM_INIT => 1,              -- DECIMAL
                USE_MEM_INIT_MMI => 0,          -- DECIMAL
                WAKEUP_TIME => "disable_sleep", -- String
                WRITE_DATA_WIDTH_A => DATA_WIDTH,       -- DECIMAL
                WRITE_MODE_A => "read_first",   -- String
                WRITE_PROTECT => 1              -- DECIMAL
            )
            port map (
               douta => bank_dout(i),            -- READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
               addra => addr,                   -- ADDR_WIDTH_A-bit input: Address for port A write and read operations.
               clka => clk,                     -- 1-bit input: Clock signal for port A.
               dina => bank_din(i),                     -- WRITE_DATA_WIDTH_A-bit input: Data input for port A write operations.
               ena => en, -- 1-bit input: Memory enable signal for port A. Must be high on clock cycles when read or write operations
                                                 -- are initiated. Pipelined internally.
            
               injectdbiterra => '0', -- 1-bit input: Controls double bit error injection on input data when ECC enabled (Error injection
                                                 -- capability is not available in "decode_only" mode).
            
               injectsbiterra => '0', -- 1-bit input: Controls single bit error injection on input data when ECC enabled (Error injection
                                                 -- capability is not available in "decode_only" mode).
            
               regcea => '1',                 -- 1-bit input: Clock Enable for the last register stage on the output data path.
               rsta => rst,                     -- 1-bit input: Reset signal for the final port A output register stage. Synchronously resets output port
                                                 -- douta to the value specified by parameter READ_RESET_VALUE_A.
            
               sleep => '0',                   -- 1-bit input: sleep signal to enable the dynamic power saving feature.
               wea(0) => bank_we(i)                 -- WRITE_DATA_WIDTH_A/BYTE_WRITE_WIDTH_A-bit input: Write enable vector for port A input data port dina. 1
                                                 -- bit wide when word-wide writes are used. In byte-wide write configurations, each bit controls the writing
                                                 -- one byte of dina to address addra. For example, to synchronously write only bits [15-8] of dina when
                                                 -- WRITE_DATA_WIDTH_A is 32, wea would be 4'b0010.
            );            
        end generate;           
            
        rd_data_all(((i+1)*DATA_WIDTH)-1 downto i*DATA_WIDTH) <= bank_dout(i);    
            
    end generate;
    
    rd_data <= bank_dout(to_integer(unsigned(bank_sel)));
    
end Behavioral;
