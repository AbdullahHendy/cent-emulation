library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity cmd_engine_top is
    generic (
        -- instr buff is 16KB byte addressable
        INSTR_BUFF_DATA_WIDTH  : integer := 64; -- instruction length
        INSTR_BUFF_ADDR_WIDTH  : integer := 14;
        DEC_INSTR_WIDTH        : integer := 64;
        OTHER_DATA_WIDTH       : integer := 32
    );
    
    port ( 
        clk : in std_logic;
        rst_n : in std_logic;
         
        -- Interface with iface_ctrl block
        en : in std_logic;
        soft_rst_pulse  : in std_logic;
        cmd_base : in std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
        cmd_len : in std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
        doorbell_pulse : in std_logic;
           
        busy : out std_logic;
        done_pulse : out std_logic;
        err_pulse : out std_logic_vector(1 downto 0);
        curr_pc : out std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
        perf : out std_logic_vector(OTHER_DATA_WIDTH-1 downto 0);
           
        -- BRAM interface (Instruction Buffer)
        instr_addr  : out std_logic_vector(INSTR_BUFF_ADDR_WIDTH-1 downto 0);
        instr_din   : out std_logic_vector(INSTR_BUFF_DATA_WIDTH-1 downto 0);
        instr_dout  : in  std_logic_vector(INSTR_BUFF_DATA_WIDTH-1 downto 0);
        instr_en    : out std_logic;
        instr_we    : out std_logic_vector((INSTR_BUFF_DATA_WIDTH/8)-1 downto 0);
        instr_clk   : out std_logic;
        instr_rst   : out std_logic;
        
        -- Single Instruction Buffer command for PIM and PNM use
        -- Original instruction with its OPsize field cleared to 0s and its burst-varying address fields updated, if opsize applicable
        dec_cmd        : out  std_logic_vector(DEC_INSTR_WIDTH-1 downto 0);
           
        -- PIM interface (PIM block handshake)
        pim_cmd_valid  : out std_logic;
        pim_cmd_ready  : in  std_logic;
        pim_done_pulse : in  std_logic;
        
        -- PNM interface (ARM R5 Core handshake)
        pnm_req_pulse  : out std_logic;
        pnm_done_pulse : in  std_logic
     );
end cmd_engine_top;

architecture Behavioral of cmd_engine_top is

    -- States def
    type state_t is (
        IDLE,
        FETCH,
        DECODE,
        EXEC_PIM_FIRE,
        EXEC_PIM_WAIT,
        EXEC_PNM_FIRE,
        EXEC_PNM_WAIT,
        DONE,
        ERROR
    );
    
    signal curr_state : state_t := IDLE;
    signal next_state : state_t := IDLE;
    
    constant INSTR_BUFF_WORD_BYTES : integer := INSTR_BUFF_DATA_WIDTH / 8; -- stride when dealing with instr buff
    
    signal pc       : integer := 0;
    
    signal curr_instr_addr : unsigned(INSTR_BUFF_ADDR_WIDTH-1 downto 0); -- current instruction buff addr increments by INSTR_BUFF_WORD_BYTES based on pc
    
    -- Original instruction (pim/pnm) with its 1. OPsize field cleared to 0s and its burst-varying address fields updated, if opsize applicable
    signal dec_cmd_reg : std_logic_vector(DEC_INSTR_WIDTH-1 downto 0);
    
    -- clock cycle count. Counts the cycles from the start of a program (doorbell_pulse to done_pulse or ERROR)
    signal cycle_counter : unsigned(OTHER_DATA_WIDTH-1 downto 0) := (others => '0');
    
    -- OPsize related signals
    -- Decoded OPsize field, NOT PACKED into the dec_cmd output
    -- OPsize supports bursts of 1-512 operations.
    -- Store OPsize-1 because burst_idx starts from 0 and is compared against the final burst index.  
    signal burst_len_m1 : unsigned(9 downto 0); -- pre-calculate burst_len - 1 since it's needed for checking if a burst is finished
    signal burst_idx    : unsigned(9 downto 0); -- 0-511
  
begin
    -- combinational pass-through for buffers clk and resets
    instr_rst     <= not rst_n;
    instr_clk     <= clk;
    
    dec_cmd       <= dec_cmd_reg;
    pim_cmd_valid <= '1' when (curr_state = EXEC_PIM_FIRE) else '0';   
    
    perf <= std_logic_vector(cycle_counter);
                   
    -- curr state process (1)
    p_curr_state_reg : process(clk, rst_n)
    begin
        if rst_n = '0' then
            curr_state <= IDLE;
        elsif rising_edge(clk) then
            if soft_rst_pulse = '1' then
                curr_state <= IDLE;
            else 
                curr_state <= next_state;
            end if;
        end if;
    end process;

    -- next state process (2)
    p_next_state: process(curr_state, en, soft_rst_pulse, cmd_base, cmd_len, doorbell_pulse, instr_dout, pc, pim_done_pulse, pim_cmd_ready, pnm_done_pulse, burst_idx, burst_len_m1)
    begin
        next_state <= curr_state;
        case curr_state is
            when IDLE =>
                if (en = '1' and doorbell_pulse = '1') then
                    next_state <= FETCH;
                end if;
            
            when FETCH =>
                -- from instr buff
                if (pc < to_integer(unsigned(cmd_len))) then -- TODO: probably add more complex logic here for error later?
                    next_state <= DECODE;
                else
                    next_state <= DONE;
                end if;
                
            when DECODE =>
                -- when curr_state is in decode, output from instr buff is ready (considered the 1 cycle read delay, see process below)
                case instr_dout(63 downto 60) is
                    -- no op
                    when x"1" => 
                        next_state <= FETCH;
                    -- OPsize Instructions (PIM)
                    when x"2" | x"3" | x"5" | x"6" | x"9" | x"A" | x"B" => 
                        if (unsigned(instr_dout(54 downto 45)) = 0) then -- OPsize cannot be 0
                            next_state <= ERROR;
                        else
                            next_state <= EXEC_PIM_FIRE;
                        end if;
                    -- no OPsize Instructions (PIM)
                    when x"4" | x"7" | x"8" | x"C" =>    
                        next_state <= EXEC_PIM_FIRE;
                    -- OPsize Instructions (PNM)
                    when x"D" =>
                        if (unsigned(instr_dout(59 downto 50)) = 0) then -- OPsize cannot be 0
                            next_state <= ERROR;
                        else
                            next_state <= EXEC_PNM_FIRE;
                        end if;                        
                        
                    when others =>
                        next_state <= ERROR;
                end case; 
                
            when EXEC_PIM_FIRE =>
                if (pim_cmd_ready = '1') then
                    next_state <= EXEC_PIM_WAIT;
                else
                    next_state <= EXEC_PIM_FIRE;
                end if;
            
            when EXEC_PIM_WAIT =>
                if (pim_done_pulse = '1') then
                    if (burst_idx < burst_len_m1) then
                        next_state <= EXEC_PIM_FIRE;
                    else
                        next_state <= FETCH;
                    end if;
                end if;
           
            when EXEC_PNM_FIRE =>
                next_state <= EXEC_PNM_WAIT;
                
            when EXEC_PNM_WAIT =>
                if (pnm_done_pulse = '1') then
                    if (burst_idx < burst_len_m1) then
                        next_state <= EXEC_PNM_FIRE;
                    else
                        next_state <= FETCH;
                    end if;
                end if;
         
           
            when DONE => 
                next_state <= IDLE;
            
            when ERROR =>
                next_state <= IDLE;
            
            when others => 
                next_state <= ERROR;
        
        end case;
    
    end process;
    
    -- outputs process (3)
    p_output : process(clk, rst_n)
    begin
        if rst_n = '0' then
            -- status
            busy <= '0';
            done_pulse <= '0';
            err_pulse  <= (others => '0');
            curr_pc    <= (others => '0');
            
            -- instruction buffer
            instr_addr <= (others => '0');
            instr_din  <= (others => '0');
            instr_en   <= '0';
            instr_we   <= (others => '0');
            
            -- decoded cmd
            dec_cmd_reg <= (others => '0');
            
            -- pnm
            pnm_req_pulse <= '0';
            
            -- OPsize signals
            burst_len_m1 <= (others => '0');
            burst_idx    <= (others => '0');
            
        elsif rising_edge(clk) then
            -- Intercept with soft reset
            if soft_rst_pulse = '1' then
                -- status
                busy <= '0';
                done_pulse <= '0';
                err_pulse  <= (others => '0');
                curr_pc   <= (others => '0');
                
                -- instruction buffer
                instr_addr <= (others => '0');
                instr_din  <= (others => '0');
                instr_en   <= '0';
                instr_we   <= (others => '0');
                
                -- decoded cmd
                dec_cmd_reg <= (others => '0');
                
                -- pnm
                pnm_req_pulse <= '0';
                            
                -- OPsize signals
                burst_len_m1 <= (others => '0');
                burst_idx    <= (others => '0');

            else 
                -- pulse signals always zeroed by default 
                done_pulse <= '0';
                err_pulse  <= (others => '0');
                instr_en   <= '0'; -- only enable instr buff when needed
                pnm_req_pulse <= '0';
                
                curr_pc <= std_logic_vector(to_unsigned(pc, curr_pc'length));
                
                -- idle, reset outputs
                if (curr_state = IDLE) then
                    -- status             
                    busy <= '0';
                    done_pulse <= '0';
                    err_pulse  <= (others => '0');
                    curr_pc   <= (others => '0');
                    
                    -- instruction buffer
                    instr_addr <= (others => '0');
                    instr_din  <= (others => '0');
                    instr_en   <= '0';
                    instr_we   <= (others => '0');
                    
                    -- decoded cmd
                    dec_cmd_reg <= (others => '0');
                    
                    -- OPsize signals
                    burst_len_m1 <= (others => '0');
                    burst_idx    <= (others => '0');
                end if;
                            
                -- entering FETCH so prepare outputs to read instr buff (bram has 1 cycle read delay)
                if (next_state = FETCH) then
                    instr_en <= '1';
                    -- busy
                    busy <= '1';
                                    
                    -- fetch new instr
                    if (curr_state = EXEC_PIM_WAIT or curr_state = EXEC_PNM_WAIT or curr_state = DECODE) then
                            -- Process 4 is about to increment PC and curr_instr_addr so fetch NEXT address (PC+1)/(curr_instr_addr+INSTR_BUFF_WORD_BYTES) since pc/curr_instr_addr still has old val now.
                            instr_addr <= std_logic_vector(curr_instr_addr + INSTR_BUFF_WORD_BYTES);
                    else -- curr_state is IDLE, pc is stable at 0
                            instr_addr <= std_logic_vector(resize(unsigned(cmd_base), instr_addr'length));
                    end if;                
                end if;   
                
                -- Entering PNM, signal request, PNM deals with SBUF itself
                if (next_state = EXEC_PNM_FIRE) then
                    pnm_req_pulse <= '1';
                end if;                             
                
                if (curr_state = DECODE) then                               
                    case instr_dout(63 downto 60) is
                        -- no op (for completeness)
                        when x"1" => 
                            dec_cmd_reg <= (others => '0');
                            
                            burst_len_m1 <= (others => '0');
                            burst_idx    <= (others => '0');
                        
                        -- WR_SBK CHid OPsize BK RO CO Rs (Shared Buffer -> PIM Banks)
                        -- e.g. 0010_XXXXX_XXXXXXXXXX_XXXX_XXXX_XXXXXX_XXXXXXXXXXXXXX_00000000000000000
                        when x"2" =>
                            -- OPsize related
                            -- From paper, OPsize advances in cols only "OPsize ... targeting subsequent Shared Buffer slots and DRAM column addresses"
                            burst_len_m1 <= unsigned(instr_dout(54 downto 45)) - 1; -- precalculate subtraction
                            burst_idx    <= (others => '0'); -- reset burst idx                                                   
                            
                            dec_cmd_reg <= instr_dout;
                            dec_cmd_reg(54 downto 45) <= (others => '0');
                                                
                        -- RD_SBK CHid OPsize BK RO CO Rd (PIM Banks -> Shared Buffer)
                        -- e.g. 0011_XXXXX_XXXXXXXXXX_XXXX_XXXX_XXXXXX_XXXXXXXXXXXXXX_00000000000000000
                        when x"3" =>
                            -- OPsize related
                            -- From paper, OPsize advances in cols only "OPsize ... targeting subsequent Shared Buffer slots and DRAM column addresses"
                            burst_len_m1 <= unsigned(instr_dout(54 downto 45)) - 1; -- precalculate subtraction
                            burst_idx    <= (others => '0'); -- reset burst idx                                                                        

                            dec_cmd_reg <= instr_dout;
                            dec_cmd_reg(54 downto 45) <= (others => '0');
                                                    
                        -- NOTE: The WR_ABK instruction is made slightly different than the paper by removing the Regid field in the paper, seems unrelated to the instruction description
                        -- WR_ABK CHid RO CO Rs (Shared Buffer -> All 16 PIM Banks)
                        -- e.g. 0100_XXXXX_XXXX_XXXXXX_XXXXXXXXXXXXXX_0000000000000000000000000000000                    
                        when x"4" =>
                            -- OPsize related
                            -- NO OPsize parameter, burst_len is 1 so burst_len_m1 is 0 
                            burst_len_m1 <= (others => '0');
                            burst_idx    <= (others => '0'); -- reset burst idx
                            
                            dec_cmd_reg <= instr_dout;

                        -- NOTE: The COPY_BKGB instruction is made slightly different than the paper by adding a BK field to select which bank is data copied from and Gb to select gbuff address instead of sharing CO between pim banks and gbuff
                        -- COPY_BKGB CHmask OPsize BK RO CO Gb (PIM Banks -> Global Buffer)
                        -- e.g. 0101_XXXXX_XXXXXXXXXX_XXXX_XXXX_XXXXXX_XXXXXX_0000000000000000000000000
                        when x"5" =>
                            -- OPsize related
                            burst_len_m1 <= unsigned(instr_dout(54 downto 45)) - 1; -- precalculate subtraction
                            burst_idx    <= (others => '0'); -- reset burst idx                               
                            
                            dec_cmd_reg <= instr_dout;
                            dec_cmd_reg(54 downto 45) <= (others => '0');
                                
                        -- NOTE: The COPY_GBBK instruction is made slightly different than the paper by adding a BK field to select which bank is data copied to and Gb to select gbuff address instead of sharing CO between pim banks and gbuff
                        -- COPY_GBBK CHmask OPsize BK RO CO Gb (Global Buffer -> PIM Banks)
                        -- e.g. 0110_XXXXX_XXXXXXXXXX_XXXX_XXXX_XXXXXX_XXXXXX_0000000000000000000000000
                        when x"6" =>
                            -- OPsize related
                            burst_len_m1 <= unsigned(instr_dout(54 downto 45)) - 1; -- precalculate subtraction                        
                            burst_idx    <= (others => '0'); -- reset burst idx                               
                              
                            dec_cmd_reg <= instr_dout;
                            dec_cmd_reg(54 downto 45) <= (others => '0');
                        
                        -- NOTE: The WR_BIAS instruction is made slightly different than the paper by adding Regid, allowing for more control over PU reg file initialization.
                        -- WR_BIAS CHmask Rs Regid (Shared Buffer -> PIM PU Accumulation Regs)
                        -- e.g. 0111_XXXXX_XXXXXXXXXXXXXX_XXXXX_000000000000000000000000000000000000
                        when x"7" => 
                            -- OPsize related
                            -- NO OPsize parameter, burst_len is 1 so burst_len_m1 is 0 
                            burst_len_m1 <= (others => '0');
                            burst_idx    <= (others => '0'); -- reset burst idx     
                             
                            dec_cmd_reg <= instr_dout;
                                                     
                        -- RD_MAC CHmask Rd Regid (PIM PU Accumulation Regs -> Shared Buffer)
                        -- e.g. 1000_XXXXX_XXXXXXXXXXXXXX_XXXXX_000000000000000000000000000000000000
                        when x"8" =>
                            -- OPsize related
                            -- NO OPsize parameter, burst_len is 1 so burst_len_m1 is 0 
                            burst_len_m1 <= (others => '0');
                            burst_idx    <= (others => '0');                                
     
                            dec_cmd_reg <= instr_dout;
    
                        -- NOTE: The WR_GB instruction is made slightly different than the paper by changing CO to Gb, CO selects col in pim banks and is decoupled from gbuff, added Gb for gbuff address
                        -- WR_GB CHmask OPsize Gb Rs (Shared Buffer -> Global Buffer)
                        -- e.g. 1001_XXXXX_XXXXXXXXXX_XXXXXX_XXXXXXXXXXXXXX_0000000000000000000000000
                        when x"9" =>
                            -- OPsize related
                            burst_len_m1 <= unsigned(instr_dout(54 downto 45)) - 1; -- precalculate subtraction                        
                            burst_idx    <= (others => '0'); -- reset burst idx                                           
                            
                            dec_cmd_reg <= instr_dout;
                            dec_cmd_reg(54 downto 45) <= (others => '0');
                            
                        -- NOTE: The MAC_ABK instruction is made slightly different than the paper by adding OPid, allowing for choosing GEMV vs Vector dot Product in MAC units and adding Gb to decouple pim cols from gbuff address
                        -- MAC_ABK CHmask OPsize RO CO Gb OPid Regid (Global Buffer * PIM Banks -> PIM PU Accumulation Regs)
                        -- e.g. 1010_XXXXX_XXXXXXXXXX_XXXX_XXXXXX_XXXXXX_X_XXXXX_00000000000000000000000
                        when x"A" =>
                            -- OPsize related
                            burst_len_m1 <= unsigned(instr_dout(54 downto 45)) - 1; -- precalculate subtraction                        
                            burst_idx    <= (others => '0'); -- reset burst idx                       
                        
                            dec_cmd_reg <= instr_dout;
                            dec_cmd_reg(54 downto 45) <= (others => '0');
                        
                        -- EW_MUL CHmask OPsize RO CO (Element-wise Mult in PIM Bank Groups)
                        -- e.g. 1011_XXXXX_XXXXXXXXXX_XXXX_XXXXXX_00000000000000000000000000000000000
                        when x"B" => 
                            -- OPsize related
                            burst_len_m1 <= unsigned(instr_dout(54 downto 45)) - 1; -- precalculate subtraction                        
                            burst_idx    <= (others => '0'); -- reset burst idx       
                            
                            dec_cmd_reg <= instr_dout;
                            dec_cmd_reg(54 downto 45) <= (others => '0');
                        
                        -- AF CHmask AFid Regid (Apply activation function to PIM PU Accumulation Regs)
                        -- e.g. 1100_XXXXX_XXX_XXXXX_00000000000000000000000000000000000000000000000                    
                        when x"C" =>
                            -- OPsize related
                            -- NO OPsize parameter, burst_len is 1 so burst_len_m1 is 0 
                            burst_len_m1 <= (others => '0');
                            burst_idx    <= (others => '0');
                            
                            dec_cmd_reg <= instr_dout;
                        
                        -- NOTE: The PNM instruction is slightly different from the paper since we use funcid for different PNM functions instead of dedicated instructions
                        -- This is because they all have common "shape" of PNM_INSTR Opsize rd rs in the paper                        
                        -- PNM OPsize Funcid Rd Rs (PNM functions from/to SBUF)
                        -- e.g. 1101_XXXXXXXXXX_XXXXX_XXXXXXXXXXXXXX_XXXXXXXXXXXXXX_00000000000000000
                        when x"D" =>
                            -- OPsize related
                            burst_len_m1 <= unsigned(instr_dout(59 downto 50)) - 1; -- precalculate subtraction                        
                            burst_idx    <= (others => '0'); -- reset burst idx       
                            
                            dec_cmd_reg <= instr_dout;
                            dec_cmd_reg(59 downto 50) <= (others => '0');
                                                    
                        when others =>
                            dec_cmd_reg <= (others => '0');
                            
                            burst_len_m1 <= (others => '0');
                            burst_idx    <= (others => '0');
                    end case;                 
                end if;
                
                if (curr_state = EXEC_PIM_WAIT) then
                    -- Burst Updates
                    if (pim_done_pulse='1' and burst_idx < burst_len_m1) then
                        -- update idx
                        burst_idx <= burst_idx + 1;
                        
                        -- update dec_cmd_reg based on which intr
                        case dec_cmd_reg(63 downto 60) is --uop
                            -- WR_SBK (x"2")
                            when x"2"=>
                                -- only update co and rs
                                dec_cmd_reg(36 downto 31) <= std_logic_vector(unsigned(dec_cmd_reg(36 downto 31)) + 1); -- co
                                dec_cmd_reg(30 downto 17) <= std_logic_vector(unsigned(dec_cmd_reg(30 downto 17)) + 1); -- rs
                                
                            -- RD_SBK (x"3") Burst Updates
                            when x"3" =>
                                -- only update co and rd
                                dec_cmd_reg(36 downto 31) <= std_logic_vector(unsigned(dec_cmd_reg(36 downto 31)) + 1); -- co
                                dec_cmd_reg(30 downto 17) <= std_logic_vector(unsigned(dec_cmd_reg(30 downto 17)) + 1); -- rd 
                                
                            -- COPY_BKGB (x"5"), COPY_GBBK (x"6")
                            when x"5" | x"6" =>
                                -- only update co
                                dec_cmd_reg(36 downto 31) <= std_logic_vector(unsigned(dec_cmd_reg(36 downto 31)) + 1); -- co
                                dec_cmd_reg(30 downto 25) <= std_logic_vector(unsigned(dec_cmd_reg(30 downto 25)) + 1); -- gb
                            
                            -- WR_GB (x"9")
                            when x"9" =>
                                dec_cmd_reg(44 downto 39) <= std_logic_vector(unsigned(dec_cmd_reg(44 downto 39)) + 1); -- gb
                                dec_cmd_reg(38 downto 25) <= std_logic_vector(unsigned(dec_cmd_reg(38 downto 25)) + 1); -- rs
                            
                            -- MAC_ABK (x"A")
                            when x"A" =>
                                dec_cmd_reg(40 downto 35) <= std_logic_vector(unsigned(dec_cmd_reg(40 downto 35)) + 1); -- co
                                dec_cmd_reg(34 downto 29) <= std_logic_vector(unsigned(dec_cmd_reg(34 downto 29)) + 1); -- gb
                            
                            -- EW_MUL (x"B")
                            when x"B" =>
                                dec_cmd_reg(40 downto 35) <= std_logic_vector(unsigned(dec_cmd_reg(40 downto 35)) + 1); -- co
                            
                            when others =>
                                -- NOP
                        end case;
                    end if;
                end if;
                
                if (curr_state = EXEC_PNM_WAIT) then 
                    if (pnm_done_pulse = '1' and burst_idx < burst_len_m1) then
                        
                        burst_idx <= burst_idx + 1; -- Increment burst counter

                        -- update dec_cmd_reg based on which intr
                        case dec_cmd_reg(63 downto 60) is --uop
                            -- PNM (x"D") Burst Updates
                            when x"D" =>
                                -- only update rs and rd
                                dec_cmd_reg(30 downto 17) <= std_logic_vector(unsigned(dec_cmd_reg(30 downto 17)) + 1); -- rs
                                dec_cmd_reg(44 downto 31) <= std_logic_vector(unsigned(dec_cmd_reg(44 downto 31)) + 1); -- rd 
                                
                            when others =>
                                -- NOP
                        end case;
                    end if;
                end if;                
                
                if (curr_state = ERROR) then
                    err_pulse <= b"01";
                end if;
                
                if (curr_state = DONE) then
                    done_pulse <= '1';
                    busy <= '0';
                end if;
            end if;
        end if;
    end process;
    
    -- pc process
    p_pc_ctrl : process(clk, rst_n)
    begin
        if rst_n = '0' then
            pc <= 0;
            curr_instr_addr <= (others => '0');
        elsif rising_edge(clk) then
            
            if soft_rst_pulse = '1' then
                pc <= 0;
                curr_instr_addr <= resize(unsigned(cmd_base), INSTR_BUFF_ADDR_WIDTH); -- when pc is 0, curr_instr_addr is just cmd_base            
            elsif curr_state = IDLE then
                pc <= 0;
                curr_instr_addr <= resize(unsigned(cmd_base), INSTR_BUFF_ADDR_WIDTH); -- when pc is 0, curr_instr_addr is just cmd_base
            elsif (next_state = FETCH) then
                if (curr_state = DECODE or curr_state = EXEC_PIM_WAIT or curr_state = EXEC_PNM_WAIT) then -- DECODE -> FETCH is for NOP handling
                    pc <= pc + 1;
                    curr_instr_addr <= curr_instr_addr + INSTR_BUFF_WORD_BYTES;                     
                end if;
            end if;
            
        end if;
    end process;    
    
    -- Performance counter process
    p_perf_cnt : process(clk, rst_n, doorbell_pulse)
    begin
        if rst_n = '0' then
            cycle_counter <= (others => '0');
        elsif rising_edge(clk) then
            if soft_rst_pulse = '1' then
                cycle_counter <= (others => '0');
                
            elsif curr_state = IDLE then
                -- Clear the counter only when a new program is triggered to allow value to be read from host
                if (en = '1' and doorbell_pulse = '1') then
                    cycle_counter <= (others => '0');
                end if;
                
            elsif (pc < to_integer(unsigned(cmd_len))) and (curr_state /= ERROR) then
                -- Increment every clock cycle until prgoram is done or error happens
                cycle_counter <= cycle_counter + 1;
            end if;
        end if;
    end process;    
    
end Behavioral;
