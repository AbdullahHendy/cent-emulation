library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity pim_top_tb is
--  Port ( );
end pim_top_tb;

architecture Behavioral of pim_top_tb is

    -- Component Declaration for DUT
    component pim_top
        generic (
            SHARED_BUFF_DATA_WIDTH  : integer := 256;
            SHARED_BUFF_ADDR_WIDTH  : integer := 14; 
            GLOBAL_BUFF_DATA_WIDTH  : integer := 256;
            GLOBAL_BUFF_ADDR_WIDTH  : integer := 6; 
            PIM_CMD_WIDTH           : integer := 64;
            ACC_REG_DATA_WIDTH      : integer := 256; 
            ACC_REG_ADDR_WIDTH      : integer := 5; 
            PIM_BANK_NUM_BANKS      : integer := 16;
            PIM_BANK_DATA_WIDTH     : integer := 256;
            PIM_BANK_ADDR_WIDTH     : integer := 10; 
            MAC_DATA_WIDTH          : integer := 256; 
            MAC_LANE_WIDTH          : integer := 16 
        );
        port ( 
            clk   : in std_logic;
            rst_n : in std_logic;
             
            shared_addr  : out std_logic_vector(SHARED_BUFF_ADDR_WIDTH-1 downto 0);
            shared_din   : out std_logic_vector(SHARED_BUFF_DATA_WIDTH-1 downto 0);
            shared_dout  : in  std_logic_vector(SHARED_BUFF_DATA_WIDTH-1 downto 0);
            shared_en    : out std_logic;
            shared_we    : out std_logic_vector((SHARED_BUFF_DATA_WIDTH/8)-1 downto 0);
            shared_clk   : out std_logic;
            shared_rst   : out std_logic;
             
            pim_cmd_valid  : in std_logic;
            pim_cmd_ready  : out  std_logic;
            pim_cmd        : in  std_logic_vector(PIM_CMD_WIDTH-1 downto 0); 
            pim_done_pulse : out  std_logic
         );
    end component;

    -- Clock period
    constant clk_period : time := 10 ns;

    -- TB Signals
    signal clk_tb   : std_logic := '0';
    signal rst_n_tb : std_logic := '0';

    signal shared_addr_tb  : std_logic_vector(13 downto 0);
    signal shared_din_tb   : std_logic_vector(255 downto 0);
    signal shared_dout_tb  : std_logic_vector(255 downto 0) := (others => '0');
    signal shared_en_tb    : std_logic;
    signal shared_we_tb    : std_logic_vector(31 downto 0);
    signal shared_clk_tb   : std_logic;
    signal shared_rst_tb   : std_logic;

    signal pim_cmd_valid_tb  : std_logic := '0';
    signal pim_cmd_ready_tb  : std_logic;
    signal pim_cmd_tb        : std_logic_vector(63 downto 0) := (others => '0');
    signal pim_done_pulse_tb : std_logic;

begin

    -- Instantiate DUT
    uut: pim_top 
    port map (
        clk   => clk_tb,
        rst_n => rst_n_tb,
        
        shared_addr  => shared_addr_tb,
        shared_din   => shared_din_tb,
        shared_dout  => shared_dout_tb,
        shared_en    => shared_en_tb,
        shared_we    => shared_we_tb,
        shared_clk   => shared_clk_tb,
        shared_rst   => shared_rst_tb,
        
        pim_cmd_valid  => pim_cmd_valid_tb,
        pim_cmd_ready  => pim_cmd_ready_tb,
        pim_cmd        => pim_cmd_tb,
        pim_done_pulse => pim_done_pulse_tb
    );

    -- Clock Process
    clk_process : process
    begin
        clk_tb <= '0';
        wait for clk_period/2;
        clk_tb <= '1';
        wait for clk_period/2;
    end process;

    -- =========================================================================
    -- MOCK SHARED BUFFER (SBUF)
    -- Simulates 1-cycle read latency. Spits out recognizable hex data!
    -- =========================================================================
    p_mock_sbuf : process(clk_tb)
    begin
        if rising_edge(clk_tb) then
            if shared_en_tb = '1' and unsigned(shared_we_tb) = 0 then
                shared_dout_tb <= x"DEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEFDEADBEEF";
            end if;
        end if;
    end process;

    -- stimulus process
    stim_proc: process
    begin
        -- 1. Reset
        rst_n_tb <= '0';
        wait for clk_period * 5;
        rst_n_tb <= '1';
        wait for clk_period * 2;

        -- Wait until PIM is IDLE and ready
        wait until rising_edge(clk_tb) and pim_cmd_ready_tb = '1';
        
        -- 2. Construct the WR_GB (x"9") Command
        -- Target GBUF index (co) = 5
        -- Source SBUF index (rs) = 12
        pim_cmd_tb <= 
            x"9" &           -- [63:60] uop
            "00000" &        -- [59:55] ch_id
            "00000" &        -- [54:50] ch_mask
            "0000" &         -- [49:46] bk
            "0000" &         -- [45:42] ro
            "000101" &       -- [41:36] co (Target GBUF Index 5)
            "000001100" &    -- [35:27] rs (Source SBUF Index 12)
            "000000000" &    -- [26:18] rd
            "00000" &        -- [17:13] regid
            "000" &          -- [12:10] afid
            "0000000000";    -- [9:0]   reserved
            
        -- Fire the command!
        pim_cmd_valid_tb <= '1';
        wait until rising_edge(clk_tb);
        pim_cmd_valid_tb <= '0';

        -- 3. Wait for done
        wait until rising_edge(clk_tb) and pim_done_pulse_tb = '1';
        
        wait for clk_period * 5;
        
        assert false report "Testbench Complete! Check waveform." severity note;
        wait;
    end process;

end Behavioral;
