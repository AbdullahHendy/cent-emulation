library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity af_units is
    generic (
        NUM_BANKS       : integer := 16;
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
        input_x_all : in std_logic_vector(NUM_BANKS*LANE_WIDTH-1 downto 0); -- One BF16 input per bank accumulator register
        af_sel      : in std_logic_vector(2 downto 0); -- 5 activation functions supported (Sigmoid, Tanh, GELU, ReLU, and leaky ReLU)  stay constant until output is valid 
            
        result_all  : out std_logic_vector(NUM_BANKS*LANE_WIDTH-1 downto 0);
        valid       : out std_logic -- asserted when output data is valid
     );     
end af_units;


architecture Behavioral of af_units is

    component af_unit is
        generic (
            AC_FCNS_NUM     : integer := AC_FCNS_NUM;
            ROM_ADDR_WIDTH  : integer := ROM_ADDR_WIDTH; -- 512 segments for each function clog(512*5) = 12
            ROM_DATA_WIDTH  : integer := ROM_DATA_WIDTH; -- 16 for Y[a] and 16 for delta Y: (Y[b] - Y[a])
            FRACTION_WIDTH  : integer := FRACTION_WIDTH; -- see above
            LANE_WIDTH      : integer := LANE_WIDTH  -- 256/16 = 16-bit / lane
            
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
    end component;

    signal valid_arr : std_logic_vector(NUM_BANKS-1 downto 0);

begin

    gen_afs: for i in 0 to NUM_BANKS-1 generate
    begin

        u_af : af_unit
        generic map (
            AC_FCNS_NUM => AC_FCNS_NUM,
            ROM_ADDR_WIDTH  => ROM_ADDR_WIDTH,
            ROM_DATA_WIDTH => ROM_DATA_WIDTH,
            FRACTION_WIDTH => FRACTION_WIDTH,
            LANE_WIDTH => LANE_WIDTH
        )
        port map (
            clk        => clk,
            rst_n      => rst_n,
            en_pulse   => en_pulse,
            
            input_x    => input_x_all(((i+1)*LANE_WIDTH)-1 downto i*LANE_WIDTH),
            -- same af for all banks
            af_sel     => af_sel,
            
            -- Pack the LANE_WIDTH-bit result back into the NUM_BANKS*LANE_WIDTH-bit output vector
            result     => result_all(((i+1)*LANE_WIDTH)-1 downto i*LANE_WIDTH),
            valid      => valid_arr(i)
        );

    end generate;

    -- All af units work in lock step, use any to assert all af valid
    valid <= valid_arr(0); 

end Behavioral;
