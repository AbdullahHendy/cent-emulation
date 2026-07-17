library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity af_unit_tb is
--  Port ( );
end af_unit_tb;

architecture Behavioral of af_unit_tb is

    -- Component Declaration for the Device Under Test (DUT)
    component af_unit
        generic (
            AC_FCNS_NUM     : integer := 5;
            ROM_ADDR_WIDTH  : integer := 12;
            ROM_DATA_WIDTH  : integer := 32;
            FRACTION_WIDTH  : integer := 6;
            LANE_WIDTH      : integer := 16            
        );
        port ( 
            clk         : in std_logic;
            rst_n       : in std_logic;
            en_pulse    : in std_logic;
            input_x     : in std_logic_vector(LANE_WIDTH-1 downto 0);
            af_sel      : in std_logic_vector(2 downto 0);
            result      : out std_logic_vector(LANE_WIDTH-1 downto 0);
            valid       : out std_logic 

        );     
    end component;
    
    -- Clock period definitions
    constant clk_period : time := 10 ns;

    constant LANE_WIDTH_TB : integer := 16;

    -- Testbench Signals
    signal clk_tb         : std_logic := '0';
    signal rst_n_tb       : std_logic := '0';
    signal en_pulse_tb    : std_logic := '0';
    signal input_x_tb     : std_logic_vector(LANE_WIDTH_TB-1 downto 0) := (others => '0');
    signal af_sel_tb    : std_logic_vector(2 downto 0) := (others => '0');
    signal result_tb      : std_logic_vector(LANE_WIDTH_TB-1 downto 0);
    signal valid_tb       : std_logic;    
    
begin

    -- Instantiate the DUT
    uut: af_unit 
    port map (
        clk         => clk_tb,
        rst_n       => rst_n_tb,
        en_pulse    => en_pulse_tb,
        input_x     => input_x_tb,
        af_sel      => af_sel_tb,
        result      => result_tb,
        valid       => valid_tb
    );

    -- Clock Generation Process
    clk_process : process
    begin
        clk_tb <= '0';
        wait for clk_period/2;
        clk_tb <= '1';
        wait for clk_period/2;
    end process;

    -- Stimulus Process
    stim_proc: process
    begin
    
        -- Initialize and Reset
        rst_n_tb <= '0';
        wait for clk_period * 5;
        rst_n_tb <= '1';
        wait for clk_period * 2;
        
        -------------------------------------------------------------
        -- TEST CASE 1: Sigmoid(-0.18)
        -- -0.18 in bf16 = 0xBE38
        -- Expected Result = 0.4551211 (bf16: 0x3EE9)
        ------------------------------------------------------------- 
         
        input_x_tb <= x"BE38";  
        af_sel_tb  <= "000";    -- Select Sigmoid
        wait for clk_period;
        -- Fire the enable pulse for exactly one clock cycle
        en_pulse_tb <= '1';
        wait for clk_period;
        en_pulse_tb <= '0';    
    
        wait until rising_edge(clk_tb) and valid_tb = '1';

        -- Self-checking assertion
        assert result_tb = x"3EE9" report "Test 1 Sigmoid Failed! Expected 0x3EE9" severity error;
        
        wait for clk_period * 3;    
    
        -------------------------------------------------------------
        -- TEST CASE 2: ReLU(4.0)
        -- 4.0 in bf16 = 0x4080
        -- Expected Result = 4.0 (bf16: 0x4080)
        ------------------------------------------------------------- 
         
        input_x_tb <= x"4080";  
        af_sel_tb  <= "011";    -- Select ReLU
        wait for clk_period;
        -- Fire the enable pulse for exactly one clock cycle
        en_pulse_tb <= '1';
        wait for clk_period;
        en_pulse_tb <= '0';    
    
        wait until rising_edge(clk_tb) and valid_tb = '1';

        -- Self-checking assertion
        assert result_tb = x"4080" report "Test 2 ReLU Failed! Expected 0x4080" severity error;
        
        wait for clk_period * 3;      
    
        -------------------------------------------------------------
        -- TEST CASE 2: Tanh(-0.9)
        -- -0.9 in bf16 = 0xBF66
        -- Expected Result = -0.7162979 (bf16: 0xBF37)
        ------------------------------------------------------------- 
         
        input_x_tb <= x"BF66";  
        af_sel_tb  <= "001";    -- Select Tanh
        wait for clk_period;
        -- Fire the enable pulse for exactly one clock cycle
        en_pulse_tb <= '1';
        wait for clk_period;
        en_pulse_tb <= '0';    
    
        wait until rising_edge(clk_tb) and valid_tb = '1';

        -- Self-checking assertion
        assert result_tb = x"BF37" report "Test 3 Tanh Failed! Expected 0xBF37" severity error;
        
        wait for clk_period * 3;        
        
    
    end process;

end Behavioral;
