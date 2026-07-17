library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity cmd_engine_top_tb is
end cmd_engine_top_tb;

architecture Behavioral of cmd_engine_top_tb is

    component cmd_engine_top
        generic (
            INSTR_BUFF_DATA_WIDTH  : integer := 64;
            INSTR_BUFF_ADDR_WIDTH  : integer := 14;
            PIM_CMD_WIDTH          : integer := 64;
            OTHER_DATA_WIDTH       : integer := 32
        );
        port ( 
           clk : in std_logic;
           rst_n : in std_logic;
           
           -- Interface with iface_ctrl block
           en : in std_logic;
           soft_rst_pulse  : in std_logic;
           irq_en : in std_logic;
           cmd_base : in std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
           cmd_len : in std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
           doorbell_pulse : in std_logic;
           
           busy : out std_logic;
           done_pulse : out std_logic;
           err_pulse : out std_logic_vector(1 downto 0);
           curr_cmd : out std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
           perf : out std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
           
           
           -- BRAM interface (Instruction Buffer)
           instr_addr  : out std_logic_vector(INSTR_BUFF_ADDR_WIDTH-1 downto 0);
           instr_din   : out std_logic_vector(INSTR_BUFF_DATA_WIDTH-1 downto 0);
           instr_dout  : in  std_logic_vector(INSTR_BUFF_DATA_WIDTH-1 downto 0);
           instr_en    : out std_logic;
           instr_we    : out std_logic_vector((INSTR_BUFF_DATA_WIDTH/8)-1 downto 0);
           instr_clk   : out std_logic;
           instr_rst   : out std_logic;
           
           -- PIM interface (PIM block)
           pim_cmd_valid  : out std_logic;
           pim_cmd_ready  : in  std_logic;
           pim_cmd        : out  std_logic_vector(PIM_CMD_WIDTH-1 downto 0); -- all possible fields decoded from instr buff packed, some are meaningless for some instrs
           pim_done_pulse : in  std_logic            
            
        );
    end component;
    constant INSTR_BUFF_DATA_WIDTH  : integer := 64;
    constant INSTR_BUFF_ADDR_WIDTH  : integer := 14;
    constant PIM_CMD_WIDTH          : integer := 64;
    constant OTHER_DATA_WIDTH       : integer := 32;    
    
    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    
    signal en : std_logic := '0';
    signal soft_rst_pulse : std_logic := '0';
    signal irq_en : std_logic := '0';
    signal cmd_base : std_logic_vector(OTHER_DATA_WIDTH-1 downto 0) := (others => '0');
    signal cmd_len : std_logic_vector(OTHER_DATA_WIDTH-1 downto 0) := (others => '0');
    signal doorbell_pulse : std_logic := '0';
    
    signal busy : std_logic;
    signal done_pulse : std_logic;
    signal err_pulse : std_logic_vector(1 downto 0);
    signal curr_cmd : std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
    signal perf : std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
    
    signal instr_addr : std_logic_vector(INSTR_BUFF_ADDR_WIDTH-1 downto 0);
    signal instr_dout : std_logic_vector(INSTR_BUFF_DATA_WIDTH-1 downto 0) := (others => '0');
    signal instr_en   : std_logic;
    signal instr_clk  : std_logic;
    signal instr_rst  : std_logic;
    
    signal pim_cmd_valid  : std_logic := '0';
    signal pim_cmd_ready  : std_logic := '0';
    signal pim_cmd        : std_logic_vector(PIM_CMD_WIDTH-1 downto 0); -- all possible fields decoded from instr buff packed, some are meaningless for some instrs
    signal pim_done_pulse : std_logic := '0';     
    
    -- Clock Period
    constant CLK_PERIOD : time := 10 ns;

begin

    uut: cmd_engine_top 
    port map (
        clk => clk,
        rst_n => rst_n,
        en => en,
        soft_rst_pulse => soft_rst_pulse,
        irq_en => irq_en,
        cmd_base => cmd_base,
        cmd_len => cmd_len,
        doorbell_pulse => doorbell_pulse,
        busy => busy,
        done_pulse => done_pulse,
        err_pulse => err_pulse,
        curr_cmd => curr_cmd,
        perf => perf,
        
        -- Map Instruction BRAM
        instr_addr => instr_addr,
        instr_din => open,
        instr_dout => instr_dout,
        instr_en => instr_en,
        instr_we => open,
        instr_clk => instr_clk,
        instr_rst => instr_rst,
        
        pim_cmd_valid => pim_cmd_valid,
        pim_cmd_ready => pim_cmd_ready,
        pim_cmd => pim_cmd,
        pim_done_pulse => pim_done_pulse
    );

    clk_process : process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;
    
    -- sim reading instr form instr_buff
    p_bram_model : process(clk)
    begin
        if rising_edge(clk) then
            if instr_en = '1' then            
                case to_integer(unsigned(instr_addr)) is
                    -- Address 0: The instruction 0x9F84506000000000 dummy example for 
                    -- WR_GB CHmask OPsize CO Rs (Shared Buffer -> Global Buffer)
                    -- 1001_11111_00011_000101_000001100_00000000000000000000000000000000000                    
                    when 0 => 
                        instr_dout <= x"9F8C506000000000";
                        
                    -- Address 8: The instruction 0x1000000000000000 (NOP)
                    when 8 => 
                        instr_dout <= x"1000000000000000";
                        
                    -- Address 16: The instruction 0x1000000000000000 (NOP)
                    when 16 => 
                        instr_dout <= x"1000000000000000";
                        
                    -- Address 24: The instruction 0x7F80400000000000 dummy example for
                    -- WR_BIAS CHmask Rs (Shared Buffer -> PIM PU Accumulation Regs)
                    -- 0111_11111_000000001_0000000000000000000000000000000000000000000000                        
                    when 24 =>
                        instr_dout <= x"7F80400000000000";
                    
                    -- Address 32: the instruction 0xAF84850800000000 dummy example for
                    -- MAC_ABK CHmask OPsize RO CO Regid (Global Buffer * PIM Banks -> PIM PU Accumulation Regs)
                    -- 1010_11111_00001_0010_000101_00001_00000000000000000000000000000000000                    
                    when 32 =>
                        instr_dout <= x"AF84850800000000";
                    
                    -- Default: 0
                    when others => 
                        instr_dout <= (others => '0');
                end case;
            end if;
        end if;
    end process;

    stim_proc: process
    begin		
        -- Reset
        rst_n <= '0';
        wait for CLK_PERIOD * 10;
        rst_n <= '1';
        wait for CLK_PERIOD * 5;
                
        -- Set Enable
        en <= '1';
        -- Set Cmd Base to 0 
        cmd_base <= (others => '0');
        -- Set Cmd Len to 5 (Run 5 instruction)
        cmd_len <= std_logic_vector(to_unsigned(5, 32));
        -- Set pim ready
        pim_cmd_ready <= '1';
        
        wait for CLK_PERIOD;

        -- Fire the Doorbell for 1 cycle (sim what iface_ctrl does)
        doorbell_pulse <= '1';
        wait for CLK_PERIOD;
        doorbell_pulse <= '0';
        
        -- wait for a bit then set done
        -- Instr 1 OPsize = 3
        -- Instr 2 NOP
        -- Instr 3 NOP
        -- Instr 4 OPsize = 1
        -- Instr 5 OPsize = 1
        
        -- 1
        wait for 6 * CLK_PERIOD;
        -- check
        assert pim_cmd = x"907C005060000000"
            report "ERROR: pim_cmd does not match expected value 907C005060000000"
            severity error; 
        -- done            
        pim_done_pulse <= '1';
        wait for CLK_PERIOD;
        pim_done_pulse <= '0';
       
        -- 2
        wait for 6 * CLK_PERIOD;
        -- check
        assert pim_cmd = x"907C006068000000" -- add 1 to base co and rs
            report "ERROR: pim_cmd does not match expected value 907C006068000000"
            severity error;
        -- done          
        pim_done_pulse <= '1';
        wait for CLK_PERIOD;
        pim_done_pulse <= '0';
      
        -- 3
        wait for 6 * CLK_PERIOD;
        -- check
        assert pim_cmd = x"907C007070000000" -- add 2 to base co and rs
            report "ERROR: pim_cmd does not match expected value 907C007070000000"
            severity error;
        -- done        
        pim_done_pulse <= '1';
        wait for CLK_PERIOD;
        pim_done_pulse <= '0';     
        
        -- NOP 1
        wait for 2 * CLK_PERIOD;

        -- NOP 2
        wait for 2 * CLK_PERIOD;
                  
        -- Instr  4
        wait for 6 * CLK_PERIOD;
        -- check
        assert pim_cmd = x"707C000008000000"
            report "ERROR: pim_cmd does not match expected value 707C000008000000"
            severity error;
        -- done        
        pim_done_pulse <= '1';
        wait for CLK_PERIOD;
        pim_done_pulse <= '0';            
                 
        -- Instr  5
        wait for 6 * CLK_PERIOD;
        -- check
        assert pim_cmd = x"A07C085000002000"
            report "ERROR: pim_cmd does not match expected value A07C085000002000"
            severity error;
        -- done        
        pim_done_pulse <= '1';
        wait for CLK_PERIOD;
        pim_done_pulse <= '0';                      
                    
                    
        report "Simulation Finished";
        wait;
    end process;

end Behavioral;