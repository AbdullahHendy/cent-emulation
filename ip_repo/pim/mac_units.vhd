library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity mac_units is
    generic (
        NUM_BANKS         : integer := 16;
        LANE_NUMS         : integer := 16;  
        INPUT_LANE_WIDTH  : integer := 16;  -- 256/16 = 16-bit / lane
        RESULT_LANE_WIDTH : integer := 32   -- result is 32-bit FP32
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
end mac_units;

architecture Behavioral of mac_units is
    
    constant MAC_UNIT_INPUT_DATA_WIDTH : integer := LANE_NUMS * INPUT_LANE_WIDTH;
    
    component mac_unit
        generic (
            LANE_NUMS         : integer := LANE_NUMS;
            INPUT_LANE_WIDTH  : integer := INPUT_LANE_WIDTH;
            RESULT_LANE_WIDTH : integer := RESULT_LANE_WIDTH           
            
        );
        port (
            clk        : in  std_logic;
            rst_n      : in  std_logic;
            en_pulse   : in  std_logic;
            input_a    : in  std_logic_vector(MAC_UNIT_INPUT_DATA_WIDTH-1 downto 0);
            input_b    : in  std_logic_vector(MAC_UNIT_INPUT_DATA_WIDTH-1 downto 0);
            acc_init   : in  std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
            result     : out std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
            valid      : out std_logic
        );
    end component;

    signal valid_arr : std_logic_vector(NUM_BANKS-1 downto 0);

begin

    gen_macs: for i in 0 to NUM_BANKS-1 generate
        signal selected_input_b : std_logic_vector(MAC_UNIT_INPUT_DATA_WIDTH-1 downto 0);
        signal unit_en          : std_logic;
    begin
        -- Choose inputb based on mode GEMV=0, Vector Dot Product=1
        -- If mode = '0', broadcast the Global Buffer data to all units.
        -- If mode = '1', use the neighboring bank's data. 
        -- Bank 0 uses Bank 1's data. Bank 2 uses Bank 3's data, etc.
        selected_input_b <= gbuf_data when mode = '0' else
                            bank_data_all(((i+2)*MAC_UNIT_INPUT_DATA_WIDTH)-1 downto (i+1)*MAC_UNIT_INPUT_DATA_WIDTH) when (i mod 2 = 0) else
                            (others => '0');
                            
        unit_en <= '0' when (mode = '1' and (i mod 2 = 1)) else en_pulse; -- no enable for odd numbered mac units when mode = 1
        
        u_mac : mac_unit
        generic map (
            LANE_NUMS         => LANE_NUMS,
            INPUT_LANE_WIDTH  => INPUT_LANE_WIDTH,
            RESULT_LANE_WIDTH => RESULT_LANE_WIDTH
        )
        port map (
            clk        => clk,
            rst_n      => rst_n,
            en_pulse   => unit_en,
            
            -- input_a is always this unit's local bank i data
            input_a    => bank_data_all(((i+1)*MAC_UNIT_INPUT_DATA_WIDTH)-1 downto i*MAC_UNIT_INPUT_DATA_WIDTH),
            
            -- input_b is either gbuff vector or bank i+1 data
            input_b    => selected_input_b,
            
            -- Slice the NUM_BANKS*RESULT_LANE_WIDTH-bit accumulator data down to the 32-bit FP32 scalar 
            acc_init   => acc_init_all(((i+1)*RESULT_LANE_WIDTH)-1 downto i*RESULT_LANE_WIDTH),
            
            -- Pack the 32-bit result back into the NUM_BANKS*RESULT_LANE_WIDTH-bit output vector
            result     => result_all(((i+1)*RESULT_LANE_WIDTH)-1 downto i*RESULT_LANE_WIDTH),
            valid      => valid_arr(i)
        );
    end generate;

    -- All mac units work in lock step, mac 0 is always active in both modes, use it to assert all mac valid
    valid <= valid_arr(0);     
            
end Behavioral;
