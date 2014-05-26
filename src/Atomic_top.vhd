--------------------------------------------------------------------------------
-- Copyright (c) 2009 Alan Daly.  All rights reserved.
--------------------------------------------------------------------------------
--   ____  ____ 
--  /   /\/   / 
-- /___/  \  /    
-- \   \   \/    
--  \   \         
--  /   /         Filename  : Atomic_top.vhf
-- /___/   /\     Timestamp : 02/03/2013 06:17:50
-- \   \  /  \ 
--  \___\/\___\ 
--
--Design Name: Atomic_top
--Device: spartan3A
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity Atomic_top is
    port (clk_25M00 : in    std_logic;
          ps2_clk   : in    std_logic;
          ps2_data  : in    std_logic;
          ERSTn     : in    std_logic;
          red       : out   std_logic_vector (2 downto 0);
          green     : out   std_logic_vector (2 downto 0);
          blue      : out   std_logic_vector (2 downto 0);
          vsync     : out   std_logic;
          hsync     : out   std_logic;
          CE1       : out   std_logic;
          RAMWRn    : out   std_logic;
          RAMOEn    : out   std_logic;
          RamA      : out   std_logic_vector (15 downto 0);
          RamD      : inout std_logic_vector (15 downto 0);
          audiol    : out   std_logic;
          audioR    : out   std_logic;
          SDMISO    : in    std_logic;
          SDSS      : out   std_logic;
          SDCLK     : out   std_logic;
          SDMOSI    : out   std_logic);
end Atomic_top;

architecture behavioral of Atomic_top is

    component dcm1
        port (
            CLKIN_IN  : in  std_logic;
            CLK0_OUT  : out std_logic;
            CLK0_OUT1 : out std_logic;
            CLK2X_OUT : out std_logic
        ); 
    end component;

    component dcm2
        port (
            CLKIN_IN  : in  std_logic;
            CLK0_OUT  : out std_logic;
            CLK0_OUT1 : out std_logic;
            CLK2X_OUT : out std_logic
        ); 
    end component;

    component dcm3
        port (CLKIN_IN  : in  std_logic;
              CLK0_OUT  : out std_logic;
              CLK0_OUT1 : out std_logic;
              CLK2X_OUT : out std_logic
         ); 
    end component;
    
    component Atomic_core
        generic  (
            CImplSID      : boolean;
            CImplSDDOS    : boolean;
            CImplAtomMMC  : boolean
        );
        port (
            clk_12M58 : in  std_logic;
            clk_16M00 : in  std_logic;
            clk_32M00 : in  std_logic;
            ps2_clk   : in  std_logic;
            ps2_data  : in  std_logic;
            ERSTn     : in  std_logic;
            SDMISO    : in  std_logic;    
            red       : out std_logic_vector(2 downto 0);
            green     : out std_logic_vector(2 downto 0);
            blue      : out std_logic_vector(2 downto 0);
            vsync     : out std_logic;
            hsync     : out std_logic;
            RamCE     : out std_logic;
            RomCE     : out std_logic;
            ExternWE  : out std_logic;
            ExternA   : out std_logic_vector (16 downto 0);
            ExternDin : out std_logic_vector (7 downto 0);
            ExternDout: in  std_logic_vector (7 downto 0);
            audiol    : out std_logic;
            audioR    : out std_logic;
            SDSS      : out std_logic;
            SDCLK     : out std_logic;
            SDMOSI    : out std_logic;
            RxD       : in  std_logic;
            TxD       : out  std_logic
        );
	end component;
    
    signal clk_12M58 : std_logic;
    signal clk_16M00 : std_logic;
    signal clk_32M00 : std_logic;

    signal RamCE        : std_logic;
    signal ExternA      : std_logic_vector (16 downto 0);
    signal ExternWE     : std_logic;
    signal ExternDin    : std_logic_vector (7 downto 0);
    signal ExternDout   : std_logic_vector (7 downto 0);

begin

    inst_dcm1 : dcm1 port map(
        CLKIN_IN  => clk_25M00,
        CLK0_OUT  => clk_12M58,
        CLK0_OUT1 => open,
        CLK2X_OUT => open);

    inst_dcm2 : dcm2 port map(
        CLKIN_IN  => clk_25M00,
        CLK0_OUT  => clk_16M00,
        CLK0_OUT1 => open,
        CLK2X_OUT => open);

    inst_dcm3 : dcm3 port map (
        CLKIN_IN  => clk_16M00,
        CLK0_OUT  => clk_32M00,
        CLK0_OUT1 => open,
        CLK2X_OUT => open);
    
	inst_Atomic_core : Atomic_core
    generic map (
        CImplSID => true,
        CImplSDDOS => true,
        CImplAtomMMC => false
    )
    port map(
		clk_12M58 => clk_12M58,
		clk_16M00 => clk_16M00,
		clk_32M00 => clk_32M00,
		ps2_clk => ps2_clk,
		ps2_data => ps2_data,
		ERSTn => ERSTn,
		red => red,
		green => green,
		blue => blue,
		vsync => vsync,
		hsync => hsync,
		ExternWE => ExternWE,
		RAMCE => RAMCE,
		ExternA => ExternA,
		ExternDin => ExternDin,
		ExternDout => ExternDout,
		audiol => audiol,
		audioR => audioR,
		SDMISO => SDMISO,
		SDSS => SDSS,
		SDCLK => SDCLK,
		SDMOSI => SDMOSI,
        RxD => '0',
        TxD => open        
	);
 
    CE1        <= not RAMCE;
    RAMWRn     <= not ExternWE;
    RAMOEn     <= not RAMCE;
    RamD       <= ExternDin & ExternDin when ExternWE = '1' else "ZZZZZZZZZZZZZZZZ";
    ExternDout <= RamD(7 downto 0);
    RamA       <= '0' & ExternA(14 downto 0);
        
end behavioral;


