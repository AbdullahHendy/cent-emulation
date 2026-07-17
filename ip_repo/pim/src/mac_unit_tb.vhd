library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity mac_unit_tb is
--  Port ( );
end mac_unit_tb;

architecture Behavioral of mac_unit_tb is

    -- Component Declaration for the Device Under Test (DUT)
    component mac_unit
        generic (
            DATA_WIDTH : integer := 256;
            LANE_NUMS  : integer := 16;
            LANE_WIDTH : integer := 16
        );
        port ( 
            clk         : in std_logic;
            rst_n       : in std_logic;
            en_pulse    : in std_logic;
            input_a     : in std_logic_vector(DATA_WIDTH-1 downto 0);    
            input_b     : in std_logic_vector(DATA_WIDTH-1 downto 0);    
            acc_init    : in std_logic_vector(LANE_WIDTH-1 downto 0);
            result      : out std_logic_vector(LANE_WIDTH-1 downto 0);
            valid       : out std_logic
        );     
    end component;
    
    constant DATA_WIDTH_TB : integer := 256;
    constant LANE_WIDTH_TB : integer := 16;
    
    -- Clock period definitions
    constant clk_period : time := 10 ns;

    -- Testbench Signals
    signal clk         : std_logic := '0';
    signal rst_n       : std_logic := '0';
    signal en_pulse    : std_logic := '0';
    signal input_a     : std_logic_vector(DATA_WIDTH_TB-1 downto 0) := (others => '0');
    signal input_b     : std_logic_vector(DATA_WIDTH_TB-1 downto 0) := (others => '0');
    signal acc_init    : std_logic_vector(LANE_WIDTH_TB-1 downto 0) := (others => '0');
    signal result      : std_logic_vector(LANE_WIDTH_TB-1 downto 0);
    signal valid       : std_logic;

begin

    -- Instantiate the DUT
    uut: mac_unit 
    port map (
        clk         => clk,
        rst_n       => rst_n,
        en_pulse    => en_pulse,
        input_a     => input_a,
        input_b     => input_b,
        acc_init    => acc_init,
        result      => result,
        valid       => valid
    );

    -- Clock Generation Process
    clk_process : process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    -- Stimulus Process
    stim_proc: process
    begin
        -- 1. Initialize and Reset
        rst_n <= '0';
        wait for clk_period * 5;
        
        -- Release reset
        rst_n <= '1';
        wait for clk_period * 2;
        
        -- ===================================================================
        -- TEST 1: Basic Positive Accumulation BF16
        -- Vector A: All 1s (0x3F80 per lane)
        -- Vector B: All 2s (0x4000 per lane)
        -- Acc Init: 5 (0x40A0)
        -- Math: 16 lanes * (1 * 2) = 32.   32 + 5 = 37 (0x4214)
        -- ===================================================================
        input_a  <= x"3F80_3F80_3F80_3F80_3F80_3F80_3F80_3F80_3F80_3F80_3F80_3F80_3F80_3F80_3F80_3F80";
        input_b  <= x"4000_4000_4000_4000_4000_4000_4000_4000_4000_4000_4000_4000_4000_4000_4000_4000";
        acc_init <= x"40A0"; -- 5 in bf16
        
        -- Fire the pipeline (PULSE)
        en_pulse <= '1';
        wait for clk_period;
        en_pulse <= '0';
        
        -- Wait for the valid signal to ripple through the pipeline
        wait until rising_edge(clk) and valid = '1';

        -- Self-checking assertion
        assert result = x"4214" report "Test 1 Failed! Expected 0x4214 (37)" severity error;
        
        wait for clk_period * 3;

        -- ===================================================================
        -- TEST 2: Negative Math BF16
        -- Vector A: Lane 0 is -1 (0xBF80), Lane 15 is -4 (0xC080) all others 0
        -- Vector B: Lane 0 is 5  (0x40A0), Lane 15 is 2  (0x4000) all others 0
        -- Acc Init: 10 (0x4120)
        -- Math: (-1 * 5) + (-4 * 2) + 0... = -13.    -13 + 10 = -3 (0xC040)
        -- ===================================================================
        input_a  <= x"C080_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_BF80";
        input_b  <= x"4000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_40A0";
        acc_init <= x"4120"; -- 10 in bf16
        
        en_pulse <= '1';
        wait for clk_period;
        en_pulse <= '0';
        
        wait until rising_edge(clk) and valid = '1';
        
        assert result = x"C040" report "Test 2 Failed! Expected 0xC040 (-3)" severity error;
        
        -- End of simulation
        wait for clk_period * 5;
        
        -- Vivado simulation stop command
        assert false report "Simulation Finished Successfully!" severity note;
        wait;
    end process;

end Behavioral;
