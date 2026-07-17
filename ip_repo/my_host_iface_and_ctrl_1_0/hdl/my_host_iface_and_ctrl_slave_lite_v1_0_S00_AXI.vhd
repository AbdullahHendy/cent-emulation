library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity my_host_iface_and_ctrl_slave_lite_v1_0_S00_AXI is
	generic (
		-- Users to add parameters here
        C_DEC_CMD_WIDTH     : integer   := 64; -- decoded command length coming from cmd_engine 
		-- User parameters ends
		-- Do not modify the parameters beyond this line

		-- Width of S_AXI data bus
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		-- Width of S_AXI address bus
		C_S_AXI_ADDR_WIDTH	: integer	:= 6
	);
	port (
		-- Users to add ports here
        -- busy signal, glue to status reg
        busy : in std_logic;
        -- done signal, glue to status reg
        done_pulse : in std_logic;
        -- error code, glue to status reg
        err_pulse : in std_logic_vector(1 downto 0);
        -- curr pc, glue to curr_pc reg (Debug)
        curr_pc : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        -- curr decoded cmd at curr pc, glue to curr_dec_cmd reg
        curr_dec_cmd : in std_logic_vector(C_DEC_CMD_WIDTH-1 downto 0);
        -- perf for perf counters, glue to perf reg (Debug/Perf)
        perf : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        -- pnm request from cmd_engine/downstream, glue to status reg
        pnm_req_pulse  : in std_logic;
        
        -- enable for downstream, decoded from ctl reg
        en : out std_logic; 
        -- soft_reset PULSE for downstream, decoded from reset reg
        soft_rst_pulse : out std_logic;
        -- interrupt for host (done or error)
        host_irq_out : out std_logic;
        -- interrupt for pnm
        pnm_irq_out  : out std_logic;
        -- base addr for cmd to start executing from, from cmd_base reg
        cmd_base : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        -- command count to execute, from cmd_base reg
        cmd_len : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        -- start/fire/doorbell PULSE from door_bell reg
        doorbell_pulse : out std_logic;
        -- pnm done PULSE from pnm_done reg
        pnm_done_pulse : out std_logic;
		-- User ports ends
		-- Do not modify the ports beyond this line

		-- Global Clock Signal
		S_AXI_ACLK	: in std_logic;
		-- Global Reset Signal. This Signal is Active LOW
		S_AXI_ARESETN	: in std_logic;
		-- Write address (issued by master, acceped by Slave)
		S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		-- Write channel Protection type. This signal indicates the
    		-- privilege and security level of the transaction, and whether
    		-- the transaction is a data access or an instruction access.
		S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
		-- Write address valid. This signal indicates that the master signaling
    		-- valid write address and control information.
		S_AXI_AWVALID	: in std_logic;
		-- Write address ready. This signal indicates that the slave is ready
    		-- to accept an address and associated control signals.
		S_AXI_AWREADY	: out std_logic;
		-- Write data (issued by master, acceped by Slave) 
		S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		-- Write strobes. This signal indicates which byte lanes hold
    		-- valid data. There is one write strobe bit for each eight
    		-- bits of the write data bus.    
		S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
		-- Write valid. This signal indicates that valid write
    		-- data and strobes are available.
		S_AXI_WVALID	: in std_logic;
		-- Write ready. This signal indicates that the slave
    		-- can accept the write data.
		S_AXI_WREADY	: out std_logic;
		-- Write response. This signal indicates the status
    		-- of the write transaction.
		S_AXI_BRESP	: out std_logic_vector(1 downto 0);
		-- Write response valid. This signal indicates that the channel
    		-- is signaling a valid write response.
		S_AXI_BVALID	: out std_logic;
		-- Response ready. This signal indicates that the master
    		-- can accept a write response.
		S_AXI_BREADY	: in std_logic;
		-- Read address (issued by master, acceped by Slave)
		S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		-- Protection type. This signal indicates the privilege
    		-- and security level of the transaction, and whether the
    		-- transaction is a data access or an instruction access.
		S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
		-- Read address valid. This signal indicates that the channel
    		-- is signaling valid read address and control information.
		S_AXI_ARVALID	: in std_logic;
		-- Read address ready. This signal indicates that the slave is
    		-- ready to accept an address and associated control signals.
		S_AXI_ARREADY	: out std_logic;
		-- Read data (issued by slave)
		S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		-- Read response. This signal indicates the status of the
    		-- read transfer.
		S_AXI_RRESP	: out std_logic_vector(1 downto 0);
		-- Read valid. This signal indicates that the channel is
    		-- signaling the required read data.
		S_AXI_RVALID	: out std_logic;
		-- Read ready. This signal indicates that the master can
    		-- accept the read data and response information.
		S_AXI_RREADY	: in std_logic
	);
end my_host_iface_and_ctrl_slave_lite_v1_0_S00_AXI;

architecture arch_imp of my_host_iface_and_ctrl_slave_lite_v1_0_S00_AXI is

	-- AXI4LITE signals
	signal axi_awaddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_awready	: std_logic;
	signal axi_wready	: std_logic;
	signal axi_bresp	: std_logic_vector(1 downto 0);
	signal axi_bvalid	: std_logic;
	signal axi_araddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_arready	: std_logic;
	signal axi_rresp	: std_logic_vector(1 downto 0);
	signal axi_rvalid	: std_logic;

	-- Example-specific design signals
	-- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	-- ADDR_LSB is used for addressing 32/64 bit registers/memories
	-- ADDR_LSB = 2 for 32 bits (n downto 2)
	-- ADDR_LSB = 3 for 64 bits (n downto 3)
	constant ADDR_LSB  : integer := (C_S_AXI_DATA_WIDTH/32)+ 1;
	constant OPT_MEM_ADDR_BITS : integer := 3;
	------------------------------------------------
	---- Signals for user logic register space example
	--------------------------------------------------
	---- Number of Slave Registers 16
	signal slv_reg0	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg1	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg2	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg3	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg4	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg5	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg6	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg7	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg8	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg9	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg10	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg11	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg12	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg13	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg14	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg15	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal byte_index	: integer;

	 signal mem_logic  : std_logic_vector(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);

	 --State machine local parameters
	constant Idle : std_logic_vector(1 downto 0) := "00";
	constant Raddr: std_logic_vector(1 downto 0) := "10";
	constant Rdata: std_logic_vector(1 downto 0) := "11";
	constant Waddr: std_logic_vector(1 downto 0) := "10";
	constant Wdata: std_logic_vector(1 downto 0) := "11";
	 --State machine variables
	signal state_read : std_logic_vector(1 downto 0);
	signal state_write: std_logic_vector(1 downto 0);
	
	-- Signals for mapping of slv_regX to more meaningful names 
	signal ver_id_reg	        :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- In place of slv_reg0 (RW)
	signal status_reg	        :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- slv_reg1 RW, Write '1' to clear status bit
	signal perf_reg	            :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- In place of slv_reg2 (RO)
	signal curr_pc_reg    	    :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- In place of slv_reg3 (RO)
	signal ctrl_reg	            :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- slv_reg4 RW
	signal cmd_base_reg	        :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- slv_reg5 RW
	signal cmd_len_reg	        :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- slv_reg6 RW
	signal doorbell        	    :std_logic;                                       -- In place of slv_reg7 (WO), ANY write fires doorbell_pulse
	signal soft_rst	            :std_logic;                                       -- In place of slv_reg8 (WO), ANY write fires soft_rst_pulse
	signal curr_dec_cmd_top_reg :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- In place of slv_reg9 (RO)
	signal curr_dec_cmd_bot_reg :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- In place of slv_reg10 (RO)
	signal pnm_done             :std_logic;                                       -- In place of slv_reg11 (WO), ANY write fires doorbell_pulse
	signal reserved1	        :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- slv_reg12
	signal reserved2	        :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- slv_reg13
	signal reserved3	        :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- slv_reg14
	signal reserved4	        :std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0); -- slv_reg15
	
	-- Signals to capture pulse inputs
	signal done_sticky : std_logic;
    signal err_sticky  : std_logic_vector(1 downto 0);
    signal pnm_req_sticky : std_logic;
    
    -- Signal for irq_enable in ctrl_reg: bit 1
    signal irq_en : std_logic;
	
begin
	-- I/O Connections assignments

	S_AXI_AWREADY	<= axi_awready;
	S_AXI_WREADY	<= axi_wready;
	S_AXI_BRESP	<= axi_bresp;
	S_AXI_BVALID	<= axi_bvalid;
	S_AXI_ARREADY	<= axi_arready;
	S_AXI_RRESP	<= axi_rresp;
	S_AXI_RVALID	<= axi_rvalid;
	    mem_logic     <= S_AXI_AWADDR(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB) when (S_AXI_AWVALID = '1') else axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);

	-- Implement Write state machine
	-- Outstanding write transactions are not supported by the slave i.e., master should assert bready to receive response on or before it starts sending the new transaction
	 process (S_AXI_ACLK)                                       
	   begin                                       
	     if rising_edge(S_AXI_ACLK) then                                       
	        if S_AXI_ARESETN = '0' then                                       
	          --asserting initial values to all 0's during reset                                       
	          axi_awready <= '0';                                       
	          axi_wready <= '0';                                       
	          axi_bvalid <= '0';                                       
	          axi_bresp <= (others => '0');                                       
	          state_write <= Idle;                                       
	        else                                       
	          case (state_write) is                                       
	             when Idle =>		--Initial state inidicating reset is done and ready to receive read/write transactions                                       
	               if (S_AXI_ARESETN = '1') then                                       
	                 axi_awready <= '1';                                       
	                 axi_wready <= '1';                                       
	                 state_write <= Waddr;                                       
	               else state_write <= state_write;                                       
	               end if;                                       
	             when Waddr =>		--At this state, slave is ready to receive address along with corresponding control signals and first data packet. Response valid is also handled at this state                                       
	               if (S_AXI_AWVALID = '1' and axi_awready = '1') then                                       
	                 axi_awaddr <= S_AXI_AWADDR;                                       
	                 if (S_AXI_WVALID = '1') then                                       
	                   axi_awready <= '1';                                       
	                   state_write <= Waddr;                                       
	                   axi_bvalid <= '1';                                       
	                 else                                       
	                   axi_awready <= '0';                                       
	                   state_write <= Wdata;                                       
	                   if (S_AXI_BREADY = '1' and axi_bvalid = '1') then                                       
	                     axi_bvalid <= '0';                                       
	                   end if;                                       
	                 end if;                                       
	               else                                        
	                 state_write <= state_write;                                       
	                 if (S_AXI_BREADY = '1' and axi_bvalid = '1') then                                       
	                   axi_bvalid <= '0';                                       
	                 end if;                                       
	               end if;                                       
	             when Wdata =>		--At this state, slave is ready to receive the data packets until the number of transfers is equal to burst length                                       
	               if (S_AXI_WVALID = '1') then                                       
	                 state_write <= Waddr;                                       
	                 axi_bvalid <= '1';                                       
	                 axi_awready <= '1';                                       
	               else                                       
	                 state_write <= state_write;                                       
	                 if (S_AXI_BREADY ='1' and axi_bvalid = '1') then                                       
	                   axi_bvalid <= '0';                                       
	                 end if;                                       
	               end if;                                       
	             when others =>      --reserved                                       
	               axi_awready <= '0';                                       
	               axi_wready <= '0';                                       
	               axi_bvalid <= '0';                                       
	           end case;                                       
	        end if;                                       
	      end if;                                                
	 end process;                                       
	-- Implement memory mapped register select and write logic generation
	-- The write data is accepted and written to memory mapped registers when
	-- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	-- select byte enables of slave registers while writing.
	-- These registers are cleared when reset (active low) is applied.
	-- Slave register write enable is asserted when valid address and data are available
	-- and the slave is ready to accept the write address and write data.
	

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      slv_reg0 <= (others => '0');
	      slv_reg1 <= (others => '0');
	      slv_reg2 <= (others => '0');
	      slv_reg3 <= (others => '0');
	      slv_reg4 <= (others => '0');
	      slv_reg5 <= (others => '0');
	      slv_reg6 <= (others => '0');
	      slv_reg7 <= (others => '0');
	      slv_reg8 <= (others => '0');
	      slv_reg9 <= (others => '0');
	      slv_reg10 <= (others => '0');
	      slv_reg11 <= (others => '0');
	      slv_reg12 <= (others => '0');
	      slv_reg13 <= (others => '0');
	      slv_reg14 <= (others => '0');
	      slv_reg15 <= (others => '0');
	      doorbell <= '0';
	      soft_rst <= '0';
	      pnm_done <= '0';
	    else
	      doorbell <= '0'; -- always 0 except when written to b"0111"
	      soft_rst <= '0'; -- always 0 except when written to b"1000"
	      pnm_done <= '0'; -- always 0 except when written to b"1011"
            if (S_AXI_WVALID = '1' and axi_wready = '1' and 
                S_AXI_AWVALID = '1' and axi_awready = '1') then            
	          case (mem_logic) is
	          when b"0000" =>
	          -- RO
--	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
--	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
--	                -- Respective byte enables are asserted as per write strobes                   
--	                -- slave registor 0
--	                slv_reg0(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
--	              end if;
--	            end loop;
	          when b"0001" =>
	          -- Write '1' to clear bits, see process in user logic for implementation logic
	            
--	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
--	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
--	                -- Respective byte enables are asserted as per write strobes                   
--	                -- slave registor 1
--	                slv_reg1(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
--	              end if;
--	            end loop;
	          when b"0010" =>
	          -- RO
--	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
--	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
--	                -- Respective byte enables are asserted as per write strobes                   
--	                -- slave registor 2
--	                slv_reg2(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
--	              end if;
--	            end loop;
	          when b"0011" =>
	          -- RO
--	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
--	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
--	                -- Respective byte enables are asserted as per write strobes                   
--	                -- slave registor 3
--	                slv_reg3(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
--	              end if;
--	            end loop;
	          when b"0100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 4
	                slv_reg4(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 5
	                slv_reg5(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 6
	                slv_reg6(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0111" =>
	            -- WO
--	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
--	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
--	                -- Respective byte enables are asserted as per write strobes                   
--	                -- slave registor 7
--	                slv_reg7(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
--	              end if;
--	            end loop;
                
                -- Pulse
                doorbell <= '1';
	          when b"1000" =>
	          -- WO
--	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
--	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
--	                -- Respective byte enables are asserted as per write strobes                   
--	                -- slave registor 8
--	                slv_reg8(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
--	              end if;
--	            end loop;
                
                -- Pulse
                soft_rst <= '1';
	          when b"1001" =>
	          -- RO
--	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
--	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
--	                -- Respective byte enables are asserted as per write strobes                   
--	                -- slave registor 9
--	                slv_reg9(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
--	              end if;
--	            end loop;
	          when b"1010" =>
	          -- RO
--	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
--	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
--	                -- Respective byte enables are asserted as per write strobes                   
--	                -- slave registor 10
--	                slv_reg10(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
--	              end if;
--	            end loop;
	          when b"1011" =>
	          -- WO
--	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
--	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
--	                -- Respective byte enables are asserted as per write strobes                   
--	                -- slave registor 11
--	                slv_reg11(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
--	              end if;
--	            end loop;

                -- Pulse
                pnm_done <= '1';
	          when b"1100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 12
	                slv_reg12(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"1101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 13
	                slv_reg13(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"1110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 14
	                slv_reg14(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"1111" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 15
	                slv_reg15(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when others =>
	            slv_reg0 <= slv_reg0;
	            slv_reg1 <= slv_reg1;
	            slv_reg2 <= slv_reg2;
	            slv_reg3 <= slv_reg3;
	            slv_reg4 <= slv_reg4;
	            slv_reg5 <= slv_reg5;
	            slv_reg6 <= slv_reg6;
	            slv_reg7 <= slv_reg7;
	            slv_reg8 <= slv_reg8;
	            slv_reg9 <= slv_reg9;
	            slv_reg10 <= slv_reg10;
	            slv_reg11 <= slv_reg11;
	            slv_reg12 <= slv_reg12;
	            slv_reg13 <= slv_reg13;
	            slv_reg14 <= slv_reg14;
	            slv_reg15 <= slv_reg15;
	        end case;
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement read state machine
	 process (S_AXI_ACLK)                                          
	   begin                                          
	     if rising_edge(S_AXI_ACLK) then                                           
	        if S_AXI_ARESETN = '0' then                                          
	          --asserting initial values to all 0's during reset                                          
	          axi_arready <= '0';                                          
	          axi_rvalid <= '0';                                          
	          axi_rresp <= (others => '0');                                          
	          state_read <= Idle;                                          
	        else                                          
	          case (state_read) is                                          
	            when Idle =>		--Initial state inidicating reset is done and ready to receive read/write transactions                                          
	                if (S_AXI_ARESETN = '1') then                                          
	                  axi_arready <= '1';                                          
	                  state_read <= Raddr;                                          
	                else state_read <= state_read;                                          
	                end if;                                          
	            when Raddr =>		--At this state, slave is ready to receive address along with corresponding control signals                                          
	                if (S_AXI_ARVALID = '1' and axi_arready = '1') then                                          
	                  state_read <= Rdata;                                          
	                  axi_rvalid <= '1';                                          
	                  axi_arready <= '0';                                          
	                  axi_araddr <= S_AXI_ARADDR;                                          
	                else                                          
	                  state_read <= state_read;                                          
	                end if;                                          
	            when Rdata =>		--At this state, slave is ready to send the data packets until the number of transfers is equal to burst length                                          
	                if (axi_rvalid = '1' and S_AXI_RREADY = '1') then                                          
	                  axi_rvalid <= '0';                                          
	                  axi_arready <= '1';                                          
	                  state_read <= Raddr;                                          
	                else                                          
	                  state_read <= state_read;                                          
	                end if;                                          
	            when others =>      --reserved                                          
	                axi_arready <= '0';                                          
	                axi_rvalid <= '0';                                          
	           end case;                                          
	         end if;                                          
	       end if;                                                   
	  end process;                                          
	-- Implement memory mapped register select and read logic generation
	 S_AXI_RDATA <= ver_id_reg when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "0000" ) else 
	 status_reg                when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "0001" ) else 
	 perf_reg                  when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "0010" ) else 
	 curr_pc_reg               when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "0011" ) else 
	 slv_reg4                  when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "0100" ) else 
	 slv_reg5                  when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "0101" ) else 
	 slv_reg6                  when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "0110" ) else 
	 slv_reg7                  when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "0111" ) else 
	 slv_reg8                  when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "1000" ) else 
	 curr_dec_cmd_bot_reg      when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "1001" ) else 
	 curr_dec_cmd_top_reg      when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "1010" ) else 
	 slv_reg11                 when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "1011" ) else 
	 slv_reg12                 when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "1100" ) else 
	 slv_reg13                 when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "1101" ) else 
	 slv_reg14                 when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "1110" ) else 
	 slv_reg15                 when (axi_araddr(ADDR_LSB+OPT_MEM_ADDR_BITS downto ADDR_LSB) = "1111" ) else 
	 (others => '0');

	-- Add user logic here

    -- Implement latching inputs done and err process
	 process (S_AXI_ACLK)                                          
	   begin                                          
	     if rising_edge(S_AXI_ACLK) then                                           
	        if S_AXI_ARESETN = '0' then                                          
              done_sticky <= '0';
              err_sticky  <= (others => '0');
              pnm_req_sticky <= '0';                         
	        else
	        
	           -- Capture software write to 0x4 to clear bits on write of '1'
               if (S_AXI_WVALID = '1' and axi_wready = '1' and S_AXI_AWVALID = '1' and axi_awready = '1') then
                   if (mem_logic = b"0001") then
                        -- Check Byte 0 strobe for Done(0), Busy(1), Err(2-3)
                       if ( S_AXI_WSTRB(0) = '1' ) then
                           if ( S_AXI_WDATA(0) = '1' ) then
                               done_sticky <= '0';
                           end if;
                           
                           if ( S_AXI_WDATA(2) = '1' ) then
                               err_sticky(0) <= '0';
                           end if;
                           
                           if ( S_AXI_WDATA(3) = '1' ) then
                               err_sticky(1) <= '0';
                           end if;	     
                           
                           if ( S_AXI_WDATA(4) = '1' ) then
                               pnm_req_sticky <= '0';
                           end if;	                                     
                        end if;                   
                   end if;
               end if;
	           
	           -- Capture sticky bit
	           if (done_pulse = '1') then
	               done_sticky <= '1';
	           end if;
	           if (err_pulse(0) = '1') then
	               err_sticky(0) <= '1';
	           end if;
	           if (err_pulse(1) = '1') then
	               err_sticky(1) <= '1';
	           end if;	
	           if (pnm_req_pulse = '1') then
	               pnm_req_sticky <= '1';
	           end if;
	                                             
	        end if;                                          
	     end if;                                                   
	  end process;   
    

	-- RO regs
	ver_id_reg <= x"07152026";
	
	status_reg <= (31 downto 5 => '0') & pnm_req_sticky & err_sticky & busy & done_sticky;
	
	perf_reg <= perf;
	
	curr_pc_reg <= curr_pc;
	
	curr_dec_cmd_top_reg <= curr_dec_cmd(63 downto 32);
	curr_dec_cmd_bot_reg <= curr_dec_cmd(31 downto 0);
	
	-- RW regs
	ctrl_reg <= slv_reg4;
	en <= ctrl_reg(0);
	irq_en <= ctrl_reg(1);
	
	cmd_base_reg <= slv_reg5;
	cmd_base <= cmd_base_reg;
	
	cmd_len_reg <= slv_reg6;
	cmd_len <= cmd_len_reg;
	
    doorbell_pulse <= doorbell;
    
    soft_rst_pulse <= soft_rst;
    
    pnm_done_pulse <= pnm_done;
    
    -- interrupts (level not edge), will be cleared when sticky bits are cleared in the status reg
    host_irq_out <= '1' when (irq_en = '1' and (done_sticky = '1' or err_sticky /= "00")) else '0';
    pnm_irq_out  <= '1' when (irq_en = '1' and pnm_req_sticky = '1') else '0';
    
	-- User logic ends

end arch_imp;
