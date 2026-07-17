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

-- This is a look up table based activation function
-- Covers range from -8 to 8 with total of 512 segments (16/512 = 1/32 spacing)
-- Input X is "shifted" by adding +8 to make everything positive for the indexing
-- X[0] = -8, Y[0] = f(-8), f is the activation function 
-- For an X input lying in the segment a-b and X_s = X + 8
-- Y = Y[a] + m (X_s - X[a]), m = (Y[b] - Y[a]) / (X[b] - X[a])
-- X[b] - X[a] = 1/32 
-- Rearranging ---> Y = Y[a] + ((X_s - X[a]) * 32) * (Y[b] - Y[a])                                           (1)
-- for all values between -8 and 8, Y[a] and (Y[b] - Y[a]) can be stored in 32-bit wide, 512 deep ROM
-- X_s can be seen as X_s = X[a] + r, 0 <= r <= 1/32. Also, X[a] = a / 32 due to our 1/32 spacing
-- Substitute in (1), Y = Y[a] + ((X[a] + r - X[a]) * 32) * (Y[b] - Y[a]) = Y[a] + (r * 32) * (Y[b] - Y[a])  (2)
-- One thing we can do is first multiply X_s by 32 so that 32 * X_s = 32 * X[a] + 32 * r = a + 32 * r
-- The above means that if the shifted input is multiplied by 32, we get a composition of two desired quantities:
-- First, index a (address for ROM). Second is (r * 32) required for equation (2) and final interpolation result, Y.

-- Hardware (bit slicing):
-- First we can interpret X in Q5.11 fixed point, then we add +8 in the same Q5.11 format 
-- To perform the X_s * 32 needed, we shift decimal point by 5 places to the right i.e. reinterpreting the number as Q10.6
-- For top 10 bits, top bit is an overflow bit and remaining 9 bits will be the index  a for the rom, Y[a], (Y[b] - Y[a])
-- i.e. bit 10 in the Q10.6 (bit 15) is overflow bit (overflow means X was 8.0), if 0, read ROM[bits[14:6]], if 1, read ROM[511]
-- Now we have the index a for the ROM read (top 10 bits) and the (r * 32) value from the "fraction/remainder part (6 bits)" of the Q10.6 value
-- e.g. 0000000111.100000 ---> ROM[7], "fraction" = 0.5 or 32/2^6 = 0.5, which is 0x3F00 in bf16
-- Now we can interpert the (6 bits) back to bf16, and do Y = bf16_add( Y[a], bf16_mult(fraction, Y[b] - Y[a]) )

entity af_unit is
    generic (
        AC_FCNS_NUM     : integer := 5;
        ROM_ADDR_WIDTH  : integer := 12; -- 512 segments for each function clog(512*5) = 12
        ROM_DATA_WIDTH  : integer := 32; -- 16 for Y[a] and 16 for delta Y: (Y[b] - Y[a])
        FRACTION_WIDTH  : integer := 6; -- see above
        LANE_WIDTH      : integer := 16  -- 256/16 = 16-bit / lane
        
    );

    port ( 
        clk         : in std_logic;
        rst_n       : in std_logic;
            
        en_pulse    : in std_logic;
        input_x     : in std_logic_vector(LANE_WIDTH-1 downto 0); -- bf16 input
        af_sel      : in std_logic_vector(2 downto 0); -- 5 activation functions supported (Sigmoid, Tanh, GELU, ReLU, and leaky ReLU)  stay constant until output is valid 
            
        result      : out std_logic_vector(LANE_WIDTH-1 downto 0);
        valid       : out std_logic -- asserted when output data is valid
     );     
end af_unit;

architecture Behavioral of af_unit is
    -- signals to clamp values >= 8 to 8 and values <= -8 to -8
    signal exp_val      : unsigned(7 downto 0); -- bf16 exponent is 8 bits
    signal clamped_bf16 : std_logic_vector(LANE_WIDTH-1 downto 0);
    
    -- input bf16 to Q5.11
    component bf16_to_fixed511 is
      port (
        aclk                 : in std_logic;
        s_axis_a_tvalid      : in std_logic;
        s_axis_a_tdata       : in std_logic_vector(LANE_WIDTH-1 downto 0);
        m_axis_result_tvalid : out std_logic;
        m_axis_result_tdata  : out std_logic_vector(LANE_WIDTH-1 downto 0)
      );
    end component;
    signal input_x_fixed511       : std_logic_vector(LANE_WIDTH-1 downto 0);
    signal input_x_fixed511_valid : std_logic;
    
    -- shift input by +8 
    signal input_x_fixed511_shifted : std_logic_vector(LANE_WIDTH-1 downto 0);
    
    -- ROM
    constant CAST_LATENCY : integer := 5; -- from or to bf16 ip blocks
    constant ROM_LATENCY  : integer := 1;
    constant MULT_LATENCY : integer := 8;
    constant ADD_LATENCY  : integer := 8;
    
    -- Total latency needed to read correct rom output in the mult stage of the final interpolation calculation 
    -- mult stage waits for u_fixed_to_bf16 (5 cycles) and rom (1 cycle). both start at the same time (fraction_bf16_valid). So, need delay of 4
    constant ROM_TO_INTER_MULT_LATENCY : integer := CAST_LATENCY - ROM_LATENCY;    
    -- Delay line for delta Y: (Y[b] - Y[a]) to match fraction cast (5 cycles - 1 ROM cycle = 4 delay cycles)
    type deltay_delay_type is array (0 to ROM_TO_INTER_MULT_LATENCY-1) of std_logic_vector(LANE_WIDTH-1 downto 0);
    signal deltay_delay : deltay_delay_type;
    
    -- Total latency needed to read correct rom output in the add stage of the final interpolation calculation 
    -- add stage waits for u_bf16_mult (8 cycles), which waits for u_fixed_to_bf16 (5 cycles) and rom (1 cycle). rom and u_fixed_to_bf16 start at the same time. So, need delay of 12
    constant ROM_TO_INTER_ADD_LATENCY : integer := CAST_LATENCY + MULT_LATENCY - ROM_LATENCY;
    -- Delay for Y_base to match fraction cast AND multiplier (4 slope delays + 3 mult delays = 7 delay cycles)
    type y_base_delay_type is array (0 to ROM_TO_INTER_ADD_LATENCY-1) of std_logic_vector(LANE_WIDTH-1 downto 0);
    signal y_base_delay : y_base_delay_type;    
    
    signal rom_rst  : std_logic;
    signal rom_addr : std_logic_vector(ROM_ADDR_WIDTH-1 downto 0);
    signal rom_data : std_logic_vector(ROM_DATA_WIDTH-1 downto 0);
    
    -- fraction Q0.6 to bf16
    component fixed06_to_bf16 is
      port (
        aclk                 : in std_logic;
        s_axis_a_tvalid      : in std_logic;
        s_axis_a_tdata       : in std_logic_vector(FRACTION_WIDTH+2-1 downto 0); -- +2, 1 for the sign bit, 1 for AXI padding (multiples of 8), always positive in our case
        m_axis_result_tvalid : out std_logic;
        m_axis_result_tdata  : out std_logic_vector(LANE_WIDTH-1 downto 0)
      );
    end component;
    signal fraction_fixed06_padded : std_logic_vector(FRACTION_WIDTH+2-1 downto 0);
    signal fraction_bf16           : std_logic_vector(LANE_WIDTH-1 downto 0);
    signal fraction_bf16_valid     : std_logic;
    
    -- bf16 mult for final interpolation Y = Y[a] + ((X_shifted - X[a]) * 32) * (Y[b] - Y[a])
    component bf16_mult is
      port (
        aclk                 : in std_logic;
        s_axis_a_tvalid      : in std_logic;
        s_axis_a_tdata       : in std_logic_vector(LANE_WIDTH-1 downto 0);
        s_axis_b_tvalid      : in std_logic;
        s_axis_b_tdata       : in std_logic_vector(LANE_WIDTH-1 downto 0);
        m_axis_result_tvalid : out std_logic;
        m_axis_result_tdata  : out std_logic_vector(LANE_WIDTH-1 downto 0)
      );
    end component;
    signal inter_prod       : std_logic_vector(LANE_WIDTH-1 downto 0);
    signal inter_prod_valid : std_logic;
    
    -- bf16 add for final interpolation Y = Y[a] + ((X_shifted - X[a]) * 32) * (Y[b] - Y[a])
    component bf16_add is
      port (
        aclk                 : in std_logic;
        s_axis_a_tvalid      : in std_logic;
        s_axis_a_tdata       : in std_logic_vector(LANE_WIDTH-1 downto 0);
        s_axis_b_tvalid      : in std_logic;
        s_axis_b_tdata       : in std_logic_vector(LANE_WIDTH-1 downto 0);
        m_axis_result_tvalid : out std_logic;
        m_axis_result_tdata  : out std_logic_vector(LANE_WIDTH-1 downto 0)
      );
    end component;  

begin
    rom_rst <= not rst_n;

    -- 1. Clamp
    exp_val <= unsigned(input_x(14 downto 7));
    
    -- Combinational Clamping process
    process(input_x, exp_val)
    begin
        if exp_val >= 130 then
            if input_x(15) = '0' then
                -- number >= 8
                clamped_bf16 <= x"4100";  -- Hardcode to +8.0
            else
                -- number <= -8
                clamped_bf16 <= x"C100";  -- Hardcode to -8.0
            end if;
        else
            -- Number in -7.99 and +7.99
            clamped_bf16 <= input_x;
        end if;
    end process;
    
    -- 2. convert bf16 input to signed fixed Q5.11
    u_bf16_to_fixed: bf16_to_fixed511 port map (
            aclk                 => clk,
            s_axis_a_tvalid      => en_pulse, 
            s_axis_a_tdata       => clamped_bf16,
            m_axis_result_tvalid => input_x_fixed511_valid, 
            m_axis_result_tdata  => input_x_fixed511
        );

    -- 3. shift by +8 to make it positive [0:16] instead of [-8:8]
    input_x_fixed511_shifted <= std_logic_vector(signed(input_x_fixed511) + to_signed(8 * 2**11, 16));
    
    -- 4. read ROM for Y[a] [31:16] ---- and (Y[b] - Y[a]) [15:0] and do delay lines
    process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                deltay_delay <= (others => (others => '0'));   
                y_base_delay <= (others => (others => '0'));   
            else 
                -- Shift the delta Y pipeline
                deltay_delay(0) <= rom_data(15 downto 0);
                for i in 1 to ROM_TO_INTER_MULT_LATENCY-1 loop
                    deltay_delay(i) <= deltay_delay(i-1);
                end loop;
    
                -- Shift the Y_base pipeline
                y_base_delay(0) <= rom_data(31 downto 16);
                for i in 1 to ROM_TO_INTER_ADD_LATENCY-1 loop
                    y_base_delay(i) <= y_base_delay(i-1);
                end loop;
            end if;
        end if;
    end process;    
    
    rom_addr <= af_sel & (8 downto 0 => '1') when input_x_fixed511_shifted(15) = '1'
        else af_sel & input_x_fixed511_shifted(14 downto 6);
    
    u_af_fncs_rom: xpm_memory_sprom
    generic map (
        ADDR_WIDTH_A => ROM_ADDR_WIDTH, --DECIMAL clog2(MEMORY_SIZE/READ_DATA_WIDTH_A).
        AUTO_SLEEP_TIME => 0,                   -- DECIMAL
        CASCADE_HEIGHT => 0,             -- DECIMAL
        ECC_BIT_RANGE => "7:0",          -- String
        ECC_MODE => "no_ecc",            -- String
        ECC_TYPE => "none",              -- String
        IGNORE_INIT_SYNTH => 0,          -- DECIMAL
        MEMORY_INIT_FILE => "all_af_fcns_rom.mem",      -- String
        MEMORY_INIT_PARAM => "",        -- String
        MEMORY_OPTIMIZATION => "true",   -- String
        MEMORY_PRIMITIVE => "auto",      -- String
        MEMORY_SIZE => (2**ROM_ADDR_WIDTH) * ROM_DATA_WIDTH, -- DECIMAL 16KB (32 wide, 512 deep: 2KB per function) 5 used sections, 3 zeros at the end
        MESSAGE_CONTROL => 0,            -- DECIMAL
        RAM_DECOMP => "auto",            -- String
        READ_DATA_WIDTH_A => ROM_DATA_WIDTH,          -- DECIMAL
        READ_LATENCY_A => ROM_LATENCY,              -- DECIMAL
        READ_RESET_VALUE_A => "0",       -- String
        RST_MODE_A => "SYNC",            -- String
        SIM_ASSERT_CHK => 0,             -- DECIMAL; 0=disable simulation messages, 1=enable simulation messages
        USE_MEM_INIT => 1,               -- DECIMAL
        USE_MEM_INIT_MMI => 0,           -- DECIMAL
        WAKEUP_TIME => "disable_sleep"  -- String
        )
        port map (
          addra => rom_addr,           -- ADDR_WIDTH_A-bit input: Address for port A read operations.
          clka => clk,                -- 1-bit input: Clock signal for port A. Also clocks port B when parameter CLOCKING_MODE is "common_clock".
                                      -- parameter CLOCKING_MODE is "common_clock".
        
          douta => rom_data,      -- READ_DATA_WIDTH_A-bit output: Data output for port A read operations.
          ena => input_x_fixed511_valid,          -- 1-bit input: Memory enable signal for port A.
        
          injectdbiterra => '0',      -- 1-bit input: Controls double bit error injection on input data when ECC enabled (Error injection
                                      -- capability is not available in "decode_only" mode).
        
          injectsbiterra => '0',      -- 1-bit input: Controls single bit error injection on input data when ECC enabled (Error injection
                                      -- capability is not available in "decode_only" mode).
        
          regcea => '1',              -- 1-bit input: Clock Enable for the last register stage on the output data path.
          rsta => rom_rst,             -- 1-bit input: Reset signal for the final port A output register stage. Synchronously resets output port
                                      -- doutb to the value specified by parameter READ_RESET_VALUE_B.
        
          sleep => '0'               -- 1-bit input: sleep signal to enable the dynamic power saving feature.
        );
    
    -- 5. convert fixed Q0.6 (remainder fraction) to bf16 this has latency of 5 and will hide the read latency of the ROM
    fraction_fixed06_padded <= "00" & input_x_fixed511_shifted(5 downto 0); -- 0 for positive and 0 for axi padding, fraction/remainder is always positive 
    u_fixed_to_bf16: fixed06_to_bf16 port map (
            aclk                 => clk,
            s_axis_a_tvalid      => input_x_fixed511_valid, 
            s_axis_a_tdata       => fraction_fixed06_padded,
            m_axis_result_tvalid => fraction_bf16_valid, 
            m_axis_result_tdata  => fraction_bf16
        );
    -- 6. calculate final interpolation part 1 (mult)
    u_bf16_mult : bf16_mult port map (
        aclk                 => clk,
        s_axis_a_tvalid      => fraction_bf16_valid, 
        s_axis_a_tdata       => fraction_bf16,
        s_axis_b_tvalid      => fraction_bf16_valid,
        s_axis_b_tdata       => deltay_delay(ROM_TO_INTER_MULT_LATENCY-1),
        m_axis_result_tvalid => inter_prod_valid, 
        m_axis_result_tdata  => inter_prod
    );
    
    -- 7. calculate final interpolation part 2 (add)
    u_bf16_add : bf16_add port map (
        aclk                 => clk,
        s_axis_a_tvalid      => inter_prod_valid, 
        s_axis_a_tdata       => y_base_delay(ROM_TO_INTER_ADD_LATENCY-1),
        s_axis_b_tvalid      => inter_prod_valid,
        s_axis_b_tdata       => inter_prod,
        m_axis_result_tvalid => valid, 
        m_axis_result_tdata  => result
    );       
    

end Behavioral;
