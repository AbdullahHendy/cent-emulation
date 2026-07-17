library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

-- Element-wise multiplication across all 4 bank groups in one PIM channel.
-- Fixed mapping used here:
--   Group 0 : Bank  0 * Bank  1 -> result for Bank  2
--   Group 1 : Bank  4 * Bank  5 -> result for Bank  6
--   Group 2 : Bank  8 * Bank  9 -> result for Bank 10
--   Group 3 : Bank 12 * Bank 13 -> result for Bank 14
--
-- The result_groups computes/contains the 4 destination bank words.

entity ew_mul_groups is
    generic (
        NUM_BANKS   : integer := 16;
        BANK_GROUPS : integer := 4; -- 4 bank gorups, 4 each
        lANE_NUMS   : integer := 16;  
        LANE_WIDTH  : integer := 16  -- 256/16 = 16-bit / lane
    );
    port (
        clk           : in  std_logic;
        
        en_pulse      : in  std_logic;
        
        bank_data_all : in  std_logic_vector((NUM_BANKS*lANE_NUMS*LANE_WIDTH)-1 downto 0); -- From all PIM banks
        
        result_groups : out std_logic_vector((BANK_GROUPS*lANE_NUMS*LANE_WIDTH)-1 downto 0);
        valid         : out std_logic
    );
end ew_mul_groups;

architecture Behavioral of ew_mul_groups is

    constant BANKS_PER_GROUP  : integer := NUM_BANKS / BANK_GROUPS;
    constant BANKS_DATA_WIDTH : integer := lANE_NUMS*LANE_WIDTH;

    component ew_mul_group is
        generic (
            LANE_NUMS  : integer := lANE_NUMS;  -- 16 lanes of 16-bit values, making up the 256 bit inputs
            LANE_WIDTH : integer := LANE_WIDTH  -- 256/16 = 16-bit / lane
        );
    
        port ( 
            clk         : in std_logic;
                
            en_pulse    : in std_logic;
            input_a     : in std_logic_vector(BANKS_DATA_WIDTH-1 downto 0);    
            input_b     : in std_logic_vector(BANKS_DATA_WIDTH-1 downto 0); 
                        
            result      : out std_logic_vector(BANKS_DATA_WIDTH-1 downto 0);
            valid       : out std_logic
         );     
    end component;
    signal valid_arr  : std_logic_vector(BANK_GROUPS-1 downto 0);

begin

    -- Group 0: Bank 0 * Bank 1 -> Bank 2
    -- Group 1: Bank 4 * Bank 5 -> Bank 6
    -- Group 2: Bank 8 * Bank 9 -> Bank 10
    -- Group 3: Bank 12 * Bank 13 -> Bank 14
    -- for bg in 0 to 3: (bank gorup)
    --          Group bg: Bank bg*BANKS_PER_GROUP * bg*BANKS_PER_GROUP+1 -> bg*BANKS_PER_GROUP+2
    -- NOTE: result_groups is just BANK_GROUPS locations to store BANK_GROUPS results that will be used by top module to write to banks

    gen_mul_groups : for g in 0 to BANK_GROUPS-1 generate
        constant BASE_BANK : integer := g * BANKS_PER_GROUP;
    begin

        u_ew_mul_group : ew_mul_group
        generic map (
            LANE_NUMS  => LANE_NUMS,
            LANE_WIDTH => LANE_WIDTH
        )
        port map (
            clk      => clk,
            en_pulse => en_pulse,

            input_a  => bank_data_all((BASE_BANK+1)*BANKS_DATA_WIDTH-1 downto BASE_BANK*BANKS_DATA_WIDTH),

            input_b  => bank_data_all((BASE_BANK+2)*BANKS_DATA_WIDTH-1 downto (BASE_BANK+1)*BANKS_DATA_WIDTH),

            result   => result_groups((g+1)*BANKS_DATA_WIDTH-1 downto g*BANKS_DATA_WIDTH),

            valid    => valid_arr(g)
        );

    end generate;
    
    -- All ew_mul_group units in lock step, use any to assert all af valid
    valid <= valid_arr(0);

end Behavioral;
