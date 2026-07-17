library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

-- o = b + w . x
-- o is output, one 32-bit value (FP32)
-- b is input bias (accumulator initial value, one 32-bit value)
-- w is a "vector" of 16 16-bit values 
    -- (in CENT, is row i of a matrix stored in bank k, in case of GEMV and a vector stored in bank k in case of Vector dot product)
-- x is a "vector" of 16 16-bit values 
    -- (in CENT, is a vector stored in GBUF in case of GEMV and a vector stored in bank k+1 in case of Vector dot product)

entity mac_unit is
    generic (
        LANE_NUMS         : integer := 16;  -- 16 lanes of 16-bit values, making up the 256 bit inputs
        INPUT_LANE_WIDTH  : integer := 16;  -- 256/16 = 16-bit / lane
        RESULT_LANE_WIDTH : integer := 32   -- result is 32-bit FP32
    );

    port ( 
        clk         : in std_logic;
        rst_n       : in std_logic;
            
        en_pulse    : in std_logic;
        input_a     : in std_logic_vector((LANE_NUMS*INPUT_LANE_WIDTH)-1 downto 0);    
        input_b     : in std_logic_vector((LANE_NUMS*INPUT_LANE_WIDTH)-1 downto 0);    
        acc_init    : in std_logic_vector(RESULT_LANE_WIDTH-1 downto 0); -- one 16 bit value 
            
        result      : out std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
        valid       : out std_logic -- asserted when output data is valid
     );     
end mac_unit;

architecture Behavioral of mac_unit is
    
    -- one product stage and four reduction stages to reduce 16 values
    -- S0: LSB zero-pad input BF16 to convert to FP32 (0 latency)
    -- S1: multiply
    -- S2: reduction stage 1
    -- S3: reduction stage 2
    -- S4: reduction stage 3
    -- S5: reduction stage 4
    -- S6: add bias/acc_init
    
    -- Delays below match Xilinx FloatingPoint IP config
    -- TOTAL DELAY of MAC UNIT: (1 * MULT_LATENCY) + (4 * ADD_LATENCY) + (1 * ADD_LATENCY)
    constant MULT_LATENCY : integer := 8;
    constant ADD_LATENCY  : integer := 11;
    
    -- Total latency of the multiplier + 4 sequential reduction adders BEFORE the S6 stage of adding bias/acc
    -- i.e. latency from en_pulse to s5_tree(0) valid (s5_valids(0))
    constant PRE_ACC_LATENCY : integer := (1 * MULT_LATENCY) + (4 * ADD_LATENCY);
    
    constant PROD_STAGE_VALS  : integer := LANE_NUMS;            -- 16 vals * 16 vals = 16 vals
    constant REDC_STAGE1_VALS : integer := LANE_NUMS / 2;        -- result of stage 1 reduction
    constant REDC_STAGE2_VALS : integer := REDC_STAGE1_VALS / 2; -- result of stage 2 reduction
    constant REDC_STAGE3_VALS : integer := REDC_STAGE2_VALS / 2; -- result of stage 3 reduction
    constant REDC_STAGE4_VALS : integer := REDC_STAGE3_VALS / 2; -- result of stage 4 reduction
    
    type prod_arr       is array (0 to PROD_STAGE_VALS-1)  of std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
    type red_stage1_arr is array (0 to REDC_STAGE1_VALS-1) of std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
    type red_stage2_arr is array (0 to REDC_STAGE2_VALS-1) of std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
    type red_stage3_arr is array (0 to REDC_STAGE3_VALS-1) of std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
    type red_stage4_arr is array (0 to REDC_STAGE4_VALS-1) of std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
    
    -- data lines
    signal s1_prods   : prod_arr;
    signal s2_tree    : red_stage1_arr;
    signal s3_tree    : red_stage2_arr;
    signal s4_tree    : red_stage3_arr;
    signal s5_tree    : red_stage4_arr;
    
    -- valid lines
    signal s1_valids : std_logic_vector(PROD_STAGE_VALS-1  downto 0);
    signal s2_valids : std_logic_vector(REDC_STAGE1_VALS-1 downto 0);
    signal s3_valids : std_logic_vector(REDC_STAGE2_VALS-1 downto 0);
    signal s4_valids : std_logic_vector(REDC_STAGE3_VALS-1 downto 0);
    signal s5_valids : std_logic_vector(REDC_STAGE4_VALS-1 downto 0);
    
    -- Delay Line (shift reg) for initial_acc
    type acc_delay is array (0 to PRE_ACC_LATENCY-1) of std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
    signal acc_delay_reg : acc_delay;  
    
    component fp32_mult is
      port (
        aclk                 : in std_logic;
        s_axis_a_tvalid      : in std_logic;
        s_axis_a_tdata       : in std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
        s_axis_b_tvalid      : in std_logic;
        s_axis_b_tdata       : in std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
        m_axis_result_tvalid : out std_logic;
        m_axis_result_tdata  : out std_logic_vector(RESULT_LANE_WIDTH-1 downto 0)
      );
    end component;

    component fp32_add is
      port (
        aclk                 : in std_logic;
        s_axis_a_tvalid      : in std_logic;
        s_axis_a_tdata       : in std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
        s_axis_b_tvalid      : in std_logic;
        s_axis_b_tdata       : in std_logic_vector(RESULT_LANE_WIDTH-1 downto 0);
        m_axis_result_tvalid : out std_logic;
        m_axis_result_tdata  : out std_logic_vector(RESULT_LANE_WIDTH-1 downto 0)
      );
    end component;
    
begin

    p_acc_delay : process(clk)
    begin
        if rising_edge(clk) then
            if rst_n = '0' then
                acc_delay_reg <= (others => (others => '0'));
            else
                acc_delay_reg(0) <= acc_init;
                for i in 1 to PRE_ACC_LATENCY-1 loop
                    acc_delay_reg(i) <= acc_delay_reg(i-1);
                end loop;
            end if;
        end if;
    end process;
        
    -- S1: Multiply
    gen_mults: for i in 0 to PROD_STAGE_VALS-1 generate
        u_mult : fp32_mult port map (
            aclk                 => clk,
            s_axis_a_tvalid      => en_pulse, 
            s_axis_a_tdata       => input_a(INPUT_LANE_WIDTH*(i+1)-1 downto INPUT_LANE_WIDTH*i) & x"0000", -- convert input to fp32
            s_axis_b_tvalid      => en_pulse,
            s_axis_b_tdata       => input_b(INPUT_LANE_WIDTH*(i+1)-1 downto INPUT_LANE_WIDTH*i) & x"0000", -- convert input to fp32
            m_axis_result_tvalid => s1_valids(i), 
            m_axis_result_tdata  => s1_prods(i)
        );        
    end generate;
        
    -- S2: Reduction stage 1 from 16 to 8
    gen_redc1: for i in 0 to REDC_STAGE1_VALS-1 generate
        u_add : fp32_add port map (
            aclk                 => clk,
            s_axis_a_tvalid      => s1_valids(2*i), 
            s_axis_a_tdata       => s1_prods(2*i),
            s_axis_b_tvalid      => s1_valids(2*i+1),
            s_axis_b_tdata       => s1_prods(2*i+1),
            m_axis_result_tvalid => s2_valids(i), 
            m_axis_result_tdata  => s2_tree(i)
        );        
    end generate;        
        
    -- S3: Reduction stage 2 from 8 to 4
    gen_redc2: for i in 0 to REDC_STAGE2_VALS-1 generate
        u_add : fp32_add port map (
            aclk                 => clk,
            s_axis_a_tvalid      => s2_valids(2*i), 
            s_axis_a_tdata       => s2_tree(2*i),
            s_axis_b_tvalid      => s2_valids(2*i+1),
            s_axis_b_tdata       => s2_tree(2*i+1),
            m_axis_result_tvalid => s3_valids(i), 
            m_axis_result_tdata  => s3_tree(i)
        );        
    end generate;          
        
    -- S4: Reduction stage 3 from 4 to 2
    gen_redc3: for i in 0 to REDC_STAGE3_VALS-1 generate
        u_add : fp32_add port map (
            aclk                 => clk,
            s_axis_a_tvalid      => s3_valids(2*i), 
            s_axis_a_tdata       => s3_tree(2*i),
            s_axis_b_tvalid      => s3_valids(2*i+1),
            s_axis_b_tdata       => s3_tree(2*i+1),
            m_axis_result_tvalid => s4_valids(i), 
            m_axis_result_tdata  => s4_tree(i)
        );        
    end generate;          
        
    -- S5: Reduction stage 4 from 2 to 1
    gen_redc4: for i in 0 to REDC_STAGE4_VALS-1 generate
        u_add : fp32_add port map (
            aclk                 => clk,
            s_axis_a_tvalid      => s4_valids(2*i), 
            s_axis_a_tdata       => s4_tree(2*i),
            s_axis_b_tvalid      => s4_valids(2*i+1),
            s_axis_b_tdata       => s4_tree(2*i+1),
            m_axis_result_tvalid => s5_valids(i), 
            m_axis_result_tdata  => s5_tree(i)
        );        
    end generate;         
        
    -- S6: Add bias/acc_init
    u_add : fp32_add port map (
        aclk                 => clk,
        s_axis_a_tvalid      => s5_valids(0), 
        s_axis_a_tdata       => s5_tree(0),
        s_axis_b_tvalid      => s5_valids(0),
        s_axis_b_tdata       => acc_delay_reg(PRE_ACC_LATENCY-1), -- acc_delay_reg(PRE_ACC_LATENCY-1) should be = initial_acc at this stage
        m_axis_result_tvalid => valid, 
        m_axis_result_tdata  => result
    );
    
end Behavioral;
