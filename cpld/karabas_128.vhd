library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity karabas_128 is
	port(
		-- Clock 14 MHz
		CLK14			: in std_logic;

		-- CPU signals
		CLK_CPU	: out std_logic := '1';
		N_RESET	: in std_logic;
		N_INT		: out std_logic := '1';
		N_RD			: in std_logic;
		N_WR			: in std_logic;
		N_IORQ		: in std_logic;
		N_MREQ		: in std_logic;
		N_M1			: in std_logic;
		A	: in std_logic_vector(7 downto 0); -- partial for port decoding
		A14	: in std_logic;
		A15	: in std_logic;
		D : inout std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		
		-- Buffers
		WR_BUF	: out std_logic := '0';
		N_RD_BUF_EN	: out std_logic := '1';
		N_WR_BUF_EN	: out std_logic := '1';
		N_A_GATE_EN	: out std_logic := '1';

		-- Memory signals
		MA		: inout std_logic_vector(13 downto 0) := "ZZZZZZZZZZZZZZ";
		MD		: in std_logic_vector(7 downto 0) := "ZZZZZZZZ";
		N_MRD	: out std_logic := '1';
		N_MWR	: out std_logic := '1';
		RAM_A14 : out std_logic := '0';
		RAM_A15 : out std_logic := '0';
		RAM_A16 : out std_logic := '0';

		-- ROM
		N_ROM_CS	: out std_logic := '1';
		ROM_A14 : out std_logic := '0';
		
		-- Video
		VIDEO_SYNC    : out std_logic := '1';     
		VIDEO_HSYNC    : out std_logic := '1';     
		VIDEO_VSYNC    : out std_logic := '1';     
		VIDEO_R       : out std_logic := '0';
		VIDEO_G       : out std_logic := '0';
		VIDEO_B       : out std_logic := '0';   
		VIDEO_I       : out std_logic := '0';     

		-- Interfaces 
		TAPE_IN 		: in std_logic;
		TAPE_OUT		: out std_logic := '1';				
		SPEAKER	: out std_logic := '1';

		-- AY
		AY_CLK	: out std_logic;
		AY_BC1	: out std_logic;
		AY_BDIR	: out std_logic;

		-- Keyboard
		KB	: in std_logic_vector(4 downto 0) := "ZZZZZ"
	);
end karabas_128;

architecture rtl of karabas_128 is

	signal tick     : std_logic := '0';
	signal invert   : unsigned(4 downto 0) := "00000";

	signal chr_col_cnt : unsigned(2 downto 0) := "000";    -- Character column counter
	signal chr_row_cnt : unsigned(2 downto 0) := "000";    -- Character row counter

	signal hor_cnt  : unsigned(5 downto 0) := "000000"; -- Horizontal counter
	signal ver_cnt  : unsigned(5 downto 0) := "000000"; -- Vertical counter

	signal attr     : std_logic_vector(7 downto 0);
	signal shift    : std_logic_vector(7 downto 0);
    
	signal paper_r  : std_logic;
	signal blank_r  : std_logic;
	signal attr_r   : std_logic_vector(7 downto 0);
	signal shift_r  : std_logic_vector(7 downto 0);

	signal border_attr: std_logic_vector(2 downto 0) := "000";
	signal port_7ffd	: std_logic_vector(5 downto 0);
	signal ay_port	: std_logic := '0';
        
	signal vbus_req		: std_logic := '1';
	signal vbus_ack		: std_logic := '1';
	signal vbus_mode	: std_logic := '1';	
	signal vbus_rdy	: std_logic := '1';
	
	signal vid_rd	: std_logic := '0';
	
	signal paper     : std_logic;
	signal hsync     : std_logic;
	signal vsync1    : std_logic;
	signal vsync2    : std_logic;

	signal rom_a	 : std_logic;
	signal vram_acc		: std_logic;
	
	signal rom_sel	 	: std_logic;
	
	signal n_is_ram     : std_logic := '1';
	signal ram_page	: std_logic_vector(2 downto 0) := "000";

	signal n_is_rom     : std_logic := '1';
	
	signal sound_out : std_logic := '0';
	signal ear : std_logic := '1';
	signal mic : std_logic := '0';
	signal port_access: std_logic := '0';
	
	signal sync_mode: std_logic_vector(1 downto 0) := "01";
		
begin
	rom_a <= '0' when A15 = '0' and A14 = '0' else '1';
	
	n_is_rom <= '0' when N_MREQ = '0' and rom_a = '0' else '1';
	n_is_ram <= '0' when N_MREQ = '0' and rom_a = '1' else '1';

	rom_sel <= port_7ffd(4);

	ram_page <=	"000" when A15 = '0' and A14 = '0' else
				"101" when A15 = '0' and A14 = '1' else
				"010" when A15 = '1' and A14 = '0' else
				port_7ffd(2 downto 0);

	N_ROM_CS <= n_is_rom;

	ROM_A14 <= '1' when rom_sel = '1' else '0';

	RAM_A14 <= ram_page(0) when vbus_mode = '0' else '1';
	RAM_A15 <= ram_page(1) when vbus_mode = '0' else port_7ffd(3);
	RAM_A16 <= ram_page(2) when vbus_mode = '0' else '1';

	vbus_req <= '0' when ( N_MREQ = '0' or N_IORQ = '0' ) and ( N_WR = '0' or N_RD = '0' ) else '1';
	vbus_rdy <= '0' when tick = '0' or chr_col_cnt(0) = '0' else '1';
	N_A_GATE_EN <= vbus_mode;
	
	N_RD_BUF_EN <= '0' when n_is_ram = '0' and N_RD = '0' else '1';	
	N_WR_BUF_EN <= '0' when vbus_mode = '0' and ((n_is_ram = '0' or (N_IORQ = '0' and N_M1 = '1')) and N_WR = '0') else '1';
	
	N_MRD <= '0' when (vbus_mode = '1' and vbus_rdy = '0') or (vbus_mode = '0' and N_RD = '0' and N_MREQ = '0') else '1';  
	N_MWR <= '0' when vbus_mode = '0' and n_is_ram = '0' and N_WR = '0' and chr_col_cnt(0) = '0' else '1';

	paper <= '0' when hor_cnt(5) = '0' and ver_cnt(5) = '0' and ( ver_cnt(4) = '0' or ver_cnt(3) = '0' ) else '1';      

	hsync <= '0' when hor_cnt(5 downto 2) = "1010" else '1';
	vsync1 <= '0' when hor_cnt(5 downto 1) = "00110" or hor_cnt(5 downto 1) = "10100" else '1';
	vsync2 <= '1' when hor_cnt(5 downto 2) = "0010" or hor_cnt(5 downto 2) = "1001" else '0';
	
	SPEAKER <= sound_out;
	TAPE_OUT <= mic;
	ear <= TAPE_IN;

	AY_CLK	<= chr_col_cnt(1);
	ay_port	<= '0' when N_WR = '1' and N_RD = '1' else
					'1' when vbus_mode = '0' and MA(1 downto 0) = "01" else
					'0' when vbus_mode = '0' else
					ay_port;
	AY_BC1	<= '1' when ay_port = '1' and N_M1 = '1' and N_IORQ = '0' and A14 = '1' and A15 = '1' else '0';
	AY_BDIR	<= '1' when ay_port = '1' and N_M1 = '1' and N_IORQ = '0' and A15 = '1' and N_WR = '0' else '0';

	WR_BUF <= '1' when vbus_mode = '0' and chr_col_cnt(0) = '0' else '0';
		
	-- Z80 clock 3.5 MHz
	process( CLK14 )
	begin
	-- rising edge of CLK14
		if CLK14'event and CLK14 = '1' then
			if tick = '1' then
				if chr_col_cnt(0) = '0' then 
					CLK_CPU <= '0';
				else
					CLK_CPU <= '1';
				end if;
			end if;
		end if;     
	end process;

	-- sync, counters
	process( CLK14 )
	begin
		if CLK14'event and CLK14 = '1' then
        
			if tick = '1' then
            
				if chr_col_cnt = 7 then
                
					if hor_cnt = 55 then
						hor_cnt <= (others => '0');
					else
						hor_cnt <= hor_cnt + 1;
					end if;
                    
					if hor_cnt = 39 then                    
						if chr_row_cnt = 7 then
							if (sync_mode = "00" and ver_cnt = 38) or (sync_mode = "01" and ver_cnt = 39) then
								ver_cnt <= (others => '0');
								invert <= invert + 1;
							else
								ver_cnt <= ver_cnt + 1;
							end if;                         
						end if;                     
						chr_row_cnt <= chr_row_cnt + 1;
					end if;
				end if;

				-- h/v sync

				VIDEO_HSYNC <= hsync;
                
				if chr_col_cnt = 7 then						  
					if ver_cnt /= 31 then
						VIDEO_VSYNC <= '1';
						VIDEO_SYNC <= hsync;
					elsif chr_row_cnt = 3 or chr_row_cnt = 4 or ( chr_row_cnt = 5 and ( hor_cnt >= 40 or hor_cnt < 12 ) ) then
						VIDEO_VSYNC <= '0';
						VIDEO_SYNC <= vsync2;
					else
						VIDEO_VSYNC <= '1';
						VIDEO_SYNC <= vsync1;
					end if;
                    
				end if;
            
            	-- int
				if (sync_mode = "00") then
					if chr_col_cnt = 0 then
						if ver_cnt = 31 and chr_row_cnt = 0 and hor_cnt(5 downto 3) = "000" then
							N_INT <= '0';
						else
							N_INT <= '1';
						end if;
					end if;
				elsif (sync_mode = "01") then
	    			if chr_col_cnt = 6 and hor_cnt(2 downto 0) = "111" then
	                    if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 3) = "100" then
	                        N_INT <= '0';
	                    else
	                        N_INT <= '1';
	                    end if;
					end if;
				end if;

				chr_col_cnt <= chr_col_cnt + 1;
			end if;
			tick <= not tick;
		end if;
	end process;

	-- video mem
	process( CLK14 )
	begin
		if CLK14'event and CLK14 = '1' then 
			if chr_col_cnt(0) = '1' and tick = '0' then
			
				if vbus_mode = '1' then
					if vid_rd = '0' then
						shift <= MD;
					else
						attr  <= MD;
					end if;
				end if;				
				
				if vbus_req = '0' and vbus_ack = '1' then
					vbus_mode <= '0';
				else
					vbus_mode <= '1';
					vid_rd <= not vid_rd;
				end if;	
				vbus_ack <= vbus_req;
			end if;
		end if;
	end process;
    
	MA <= ( others => 'Z' ) when vbus_mode = '0' else
											std_logic_vector( "0" & ver_cnt(4 downto 3) & chr_row_cnt & ver_cnt(2 downto 0) & hor_cnt(4 downto 0) ) when vid_rd = '0' else
											std_logic_vector( "0110" & ver_cnt(4 downto 0) & hor_cnt(4 downto 0) );

	-- r/g/b											
	process( CLK14 )
	begin
		if CLK14'event and CLK14 = '1' then
			if tick = '1' then
				if paper_r = '0' then           
					if( shift_r(7) xor ( attr_r(7) and invert(4) ) ) = '1' then
						VIDEO_B <= attr_r(0);
						VIDEO_R <= attr_r(1);
						VIDEO_G <= attr_r(2);
					else
						VIDEO_B <= attr_r(3);
						VIDEO_R <= attr_r(4);
						VIDEO_G <= attr_r(5);
						end if;
				else
					if blank_r = '0' then
						VIDEO_B <= 'Z';
						VIDEO_R <= 'Z';
						VIDEO_G <= 'Z';
						else
						VIDEO_B <= border_attr(0);
						VIDEO_R <= border_attr(1);
						VIDEO_G <= border_attr(2);
					end if;
				end if;
			end if;             

		end if;
	end process;

	-- brightness
	process( CLK14 )
	begin
		if CLK14'event and CLK14 = '1' then
			if tick = '1' then
				if paper_r = '0' and attr_r(6) = '1' then
					VIDEO_I <= '1';
				else
					VIDEO_I <= '0';
				end if;
			end if;			

		end if;
	end process;

	-- paper, blank
	process( CLK14 )
	begin
		if CLK14'event and CLK14 = '1' then
			if tick = '1' then
				if chr_col_cnt = 7 then
					attr_r <= attr;
					shift_r <= shift;

					if (sync_mode = "00" and (hor_cnt(5 downto 2) = 10 or hor_cnt(5 downto 2) = 11 or ver_cnt = 31)) then
						blank_r <= '0';
					elsif (sync_mode = "01" and ((hor_cnt(5 downto 0) > 38 and hor_cnt(5 downto 0) < 48) or ver_cnt(5 downto 1) = 15)) then
					--if hor_cnt(5 downto 3) = 5 or ver_cnt(5 downto 1) = 15 then
						blank_r <= '0';
					else 
						blank_r <= '1';
					end if;
                    
					paper_r <= paper;
				else
					shift_r(7 downto 1) <= shift_r(6 downto 0);
					shift_r(0) <= '0';
				end if;

			end if;
		end if;
	end process;

	-- ports, write by CPU
	process( CLK14 )
	begin
		if CLK14'event and CLK14 = '1' then

			if N_RESET = '0' then
				port_7ffd <= "000000";
				sound_out <= '0';
				mic <= '0';
			elsif tick = '1' and chr_col_cnt(0) = '0' and vbus_mode = '0' and N_IORQ = '0' and N_M1 = '1' then

				-- port 7ffd, read				
				if N_WR = '0' and MA(1) = '0' and A15 = '0' and port_7ffd(5) = '0' then
					port_7ffd <= MD(5 downto 0);
				end if;

				-- port #FE, write by CPU (read speaker, mic and border attr)
				if N_WR = '0' and MA(7 downto 0) = "11111110" then
					border_attr <= MD(2 downto 0); -- border attr
					mic <= MD(3); -- MIC
					sound_out <= MD(4); -- BEEPER
				end if;
				
			end if;             
		end if;
	end process;
	
	-- ports, read by CPU
	port_access <= '1' when N_IORQ = '0' and N_RD = '0' and N_M1 = '1' else '0';
		D(7 downto 0) <= '1' & ear & '1' & KB(4 downto 0) when port_access = '1' and A(7 downto 0) = "11111110" else -- #FE
		attr_r when port_access = '1' and A(7 downto 0) = "11111111" else -- #FF
		"ZZZZZZZZ";

end;
