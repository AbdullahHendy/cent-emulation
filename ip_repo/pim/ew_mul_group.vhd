library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

-- Intended for use with Element wise multiplication for a single bank group (4 banks)
-- For example input_a (Bank 0) * input_b (Bank 1) = result (Bank 2)

entity ew_mul_group is
    generic (
        LANE_NUMS         : integer := 16;  -- 16 lanes of 16-bit values, making up the 256 bit inputs
        LANE_WIDTH        : integer := 16  -- 256/16 = 16-bit / lane
    );

    port ( 
        clk         : in std_logic;
            
        en_pulse    : in std_logic;
        input_a     : in std_logic_vector((LANE_NUMS*LANE_WIDTH)-1 downto 0);    
        input_b     : in std_logic_vector((LANE_NUMS*LANE_WIDTH)-1 downto 0); 
                    
        result      : out std_logic_vector((LANE_NUMS*LANE_WIDTH)-1 downto 0);
        valid       : out std_logic -- asserted when output data is valid
     );     
end ew_mul_group;

architecture Behavioral of ew_mul_group is

    -- bf16 mult for each bf16 element in the input
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
    signal valid_arr  : std_logic_vector(LANE_NUMS-1 downto 0);

begin

    gen_mults: for i in 0 to LANE_NUMS-1 generate
        u_bf16_mult : bf16_mult port map (
            aclk                 => clk,
            s_axis_a_tvalid      => en_pulse, 
            s_axis_a_tdata       => input_a(LANE_WIDTH*(i+1)-1 downto LANE_WIDTH*i),
            s_axis_b_tvalid      => en_pulse,
            s_axis_b_tdata       => input_b(LANE_WIDTH*(i+1)-1 downto LANE_WIDTH*i),
            m_axis_result_tvalid => valid_arr(i), 
            m_axis_result_tdata  => result(LANE_WIDTH*(i+1)-1 downto LANE_WIDTH*i)
        );        
    end generate;
    
    -- All bf16_mult units work in lock step, use any lane to assert valid
    valid <= valid_arr(0);
    
end Behavioral;
