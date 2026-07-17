library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity fp32_to_bf16_units is
    generic (
        NUM_BANKS  : integer := 16;
        FP32_WIDTH : integer := 32; -- 32-bit input lane
        BF16_WIDTH : integer := 16  -- 16-bit output lane
    );
    port (
        clk           : in  std_logic;
        
        en_pulse      : in  std_logic; 
        fp32_data_all : in  std_logic_vector((NUM_BANKS * FP32_WIDTH)-1 downto 0); -- 512-bit from Regfile
        
        bf16_data_all : out std_logic_vector((NUM_BANKS * BF16_WIDTH)-1 downto 0); -- 256-bit to AF/SBUFF
        valid         : out std_logic  -- Pulse when cast is complete
    );
end fp32_to_bf16_units;

architecture Behavioral of fp32_to_bf16_units is

    component fp32_to_bf16 is
      port (
        aclk                 : in std_logic;
        s_axis_a_tvalid      : in std_logic;
        s_axis_a_tdata       : in std_logic_vector(FP32_WIDTH-1 downto 0);
        m_axis_result_tvalid : out std_logic;
        m_axis_result_tdata  : out std_logic_vector(BF16_WIDTH-1 downto 0)
      );
    end component;

    signal valid_arr : std_logic_vector(NUM_BANKS-1 downto 0);

begin

    gen_casters: for i in 0 to NUM_BANKS-1 generate
    begin
        u_cast : fp32_to_bf16 port map (
            aclk                 => clk,
            s_axis_a_tvalid      => en_pulse,
            
            -- Slice the 512-bit FP32 vector into a 32-bit scalar
            s_axis_a_tdata       => fp32_data_all(((i+1)*FP32_WIDTH)-1 downto i*FP32_WIDTH),
            
            m_axis_result_tvalid => valid_arr(i),
            
            -- Pack the casted 16-bit BF16 scalar into the 256-bit output vector
            m_axis_result_tdata  => bf16_data_all(((i+1)*BF16_WIDTH)-1 downto i*BF16_WIDTH)
        );
    end generate;

    -- All cast units work in lock step, use lane 0 to assert valid out
    valid <= valid_arr(0);      
            
end Behavioral;
