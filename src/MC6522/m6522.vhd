library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity M6522 is
    port (

        I_RS    : in  std_logic_vector(3 downto 0);
        I_DATA  : in  std_logic_vector(7 downto 0);
        O_DATA  : out std_logic_vector(7 downto 0);
        I_RW_L  : in  std_logic;
        I_CS1   : in  std_logic;
        I_CS2_L : in  std_logic;
        O_IRQ_L : out std_logic;        -- note, not open drain
        I_CA1   : in  std_logic;
        I_CA2   : in  std_logic;
        O_CA2   : out std_logic;
        I_PA    : in  std_logic_vector(7 downto 0);
        O_PA    : out std_logic_vector(7 downto 0);
        I_CB1   : in  std_logic;
        O_CB1   : out std_logic;
        I_CB2   : in  std_logic;
        O_CB2   : out std_logic;
        I_PB    : in  std_logic_vector(7 downto 0);
        O_PB    : out std_logic_vector(7 downto 0);
        I_P2_H  : in  std_logic_vector(1 downto 0);
        RESET_L : in  std_logic;
        ENA_4   : in  std_logic;
        CLK     : in  std_logic
        );
end;

architecture RTL of M6522 is

    signal phase             : std_logic_vector(1 downto 0);
    signal p2_h_t1           : std_logic;
    signal cs                : std_logic;
    signal r_ddra            : std_logic_vector(7 downto 0);
    signal r_ora             : std_logic_vector(7 downto 0);
    signal r_ira             : std_logic_vector(7 downto 0);
    signal r_ddrb            : std_logic_vector(7 downto 0);
    signal r_orb             : std_logic_vector(7 downto 0);
    signal r_irb             : std_logic_vector(7 downto 0);
    signal r_t1l_l           : std_logic_vector(7 downto 0);
    signal r_t1l_h           : std_logic_vector(7 downto 0);
    signal r_t2l_l           : std_logic_vector(7 downto 0);
    signal r_t2l_h           : std_logic_vector(7 downto 0);  -- not in real chip
    signal r_sr              : std_logic_vector(7 downto 0);
    signal r_acr             : std_logic_vector(7 downto 0);
    signal r_pcr             : std_logic_vector(7 downto 0);
    signal r_ifr             : std_logic_vector(7 downto 0);
    signal r_ier             : std_logic_vector(6 downto 0);
    signal sr_write_ena      : boolean;
    signal sr_read_ena       : boolean;
    signal ifr_write_ena     : boolean;
    signal ier_write_ena     : boolean;
    signal clear_irq         : std_logic_vector(7 downto 0);
    signal load_data         : std_logic_vector(7 downto 0);
    -- timer 1
    signal t1c               : std_logic_vector(15 downto 0);
    signal t1c_active        : boolean;
    signal t1c_done          : boolean;
    signal t1_w_reset_int    : boolean;
    signal t1_r_reset_int    : boolean;
    signal t1_load_counter   : boolean;
    signal t1_reload_counter : boolean;
    signal t1_toggle         : std_logic;
    signal t1_irq            : std_logic := '0';
    -- timer 2
    signal t2div16           : std_logic_vector(3 downto 0);
    signal t2c               : std_logic_vector(15 downto 0);
    -- signal t2c            : std_logic_vector(15 downto 0);
    signal t2c_active        : boolean;
    signal t2c_done          : boolean;
    signal t2_pb6            : std_logic;
    signal t2_pb6_t1         : std_logic;
    signal t2_w_reset_int    : boolean;
    signal t2_r_reset_int    : boolean;
    signal t2_load_counter   : boolean;
    signal t2_reload_counter : boolean;
    signal t2_irq            : std_logic := '0';
    signal t2_sr_ena         : boolean;
    -- shift reg
    signal sr_cnt            : std_logic_vector(3 downto 0);
    signal sr_cb1_oe_l       : std_logic;
    signal sr_cb1_out        : std_logic;
    signal sr_drive_cb2      : std_logic;
    signal sr_strobe         : std_logic;
    signal sr_strobe_t1      : std_logic;
    signal sr_strobe_falling : boolean;
    signal sr_strobe_rising  : boolean;
    signal sr_irq            : std_logic;
    signal sr_out            : std_logic;
    signal sr_off_delay      : std_logic;
    -- io
    signal w_orb_hs          : std_logic;
    signal w_ora_hs          : std_logic;
    signal r_irb_hs          : std_logic;
    signal r_ira_hs          : std_logic;
    signal ca_hs_sr          : std_logic;
    signal ca_hs_pulse       : std_logic;
    signal cb_hs_sr          : std_logic;
    signal cb_hs_pulse       : std_logic;
    signal cb1_in_mux        : std_logic;
    signal ca1_ip_reg        : std_logic;
    signal cb1_ip_reg        : std_logic;
    signal ca1_int           : boolean;
    signal cb1_int           : boolean;
    signal ca1_irq           : std_logic;
    signal cb1_irq           : std_logic;
    signal ca2_ip_reg        : std_logic;
    signal cb2_ip_reg        : std_logic;
    signal ca2_int           : boolean;
    signal cb2_int           : boolean;
    signal ca2_irq           : std_logic;
    signal cb2_irq           : std_logic;
    signal final_irq         : std_logic;
begin
    p_phase : process
    begin
        wait until rising_edge(CLK);
        phase <= I_P2_H;
    end process;

    p_cs : process(I_CS1, I_CS2_L, I_P2_H)
    begin
        cs <= '0';
        if (I_CS1 = '1') and (I_CS2_L = '0') then
            cs <= '1';
        end if;
    end process;

    p_write_reg_reset : process(RESET_L, CLK)
    begin
        if (RESET_L = '0') then
            r_ora  <= x"00"; r_orb <= x"00";
            r_ddra <= x"00"; r_ddrb <= x"00";
            r_acr  <= x"00"; r_pcr <= x"00";

            w_orb_hs <= '0';
            w_ora_hs <= '0';
        elsif rising_edge(CLK) then
            w_orb_hs <= '0';
            w_ora_hs <= '0';
            if (cs = '1') and (I_RW_L = '0') then
                case I_RS is
                    when x"0" => r_orb  <= I_DATA; w_orb_hs <= '1';
                    when x"1" => r_ora  <= I_DATA; w_ora_hs <= '1';
                    when x"2" => r_ddrb <= I_DATA;
                    when x"3" => r_ddra <= I_DATA;

                    when x"B" => r_acr <= I_DATA;
                    when x"C" => r_pcr <= I_DATA;
                    when x"F" => r_ora <= I_DATA;

                    when others => null;
                end case;
            end if;

            if (r_acr(7) = '1') and (t1_toggle = '1') then
                r_orb(7) <= not r_orb(7);
            end if;
        end if;
    end process;

    p_write_reg : process
    begin

        ------------------------------

        if (RESET_L = '0') then

            r_t2l_l <= x"ff";
            r_t2l_h <= x"ff";
        elsif rising_edge(CLK) then
            t1_w_reset_int  <= false;
            t1_load_counter <= false;

            t2_w_reset_int  <= false;
            t2_load_counter <= false;

            load_data     <= x"00";
            sr_write_ena  <= false;
            ifr_write_ena <= false;
            ier_write_ena <= false;

            if (cs = '1') and (I_RW_L = '0') then
                load_data <= I_DATA;
                case I_RS is
                    when x"4" => r_t1l_l <= I_DATA;
                    when x"5" => r_t1l_h <= I_DATA; t1_w_reset_int <= true;
                                 t1_load_counter <= true;

                    when x"6" => r_t1l_l <= I_DATA;
                    when x"7" => r_t1l_h <= I_DATA; t1_w_reset_int <= true;

                    when x"8" => r_t2l_l <= I_DATA;
                    when x"9" => r_t2l_h <= I_DATA; t2_w_reset_int <= true;
                                 t2_load_counter <= true;

                    when x"A" => sr_write_ena  <= true;
                    when x"D" => ifr_write_ena <= true;
                    when x"E" => ier_write_ena <= true;

                    when others => null;
                end case;
            end if;
        end if;
    end process;


    p_read : process
    begin
        wait until rising_edge(CLK);

        t1_r_reset_int <= false;
        t2_r_reset_int <= false;
        sr_read_ena    <= false;
        r_irb_hs       <= '0';
        r_ira_hs       <= '0';

        if (cs = '1') and (I_RW_L = '1') then
            case I_RS is
                when x"0"   => O_DATA <= (r_irb and not r_ddrb) or (r_orb and r_ddrb); r_irb_hs <= '1';
                when x"1"   => O_DATA <= r_ira; r_ira_hs <= '1';
                when x"2"   => O_DATA <= r_ddrb;
                when x"3"   => O_DATA <= r_ddra;
                when x"4"   => O_DATA <= t1c(7 downto 0); t1_r_reset_int <= true;
                when x"5"   => O_DATA <= t1c(15 downto 8);
                when x"6"   => O_DATA <= r_t1l_l;
                when x"7"   => O_DATA <= r_t1l_h;
                when x"8"   => O_DATA <= t2c(7 downto 0); t2_r_reset_int <= true;
                when x"9"   => O_DATA <= t2c(15 downto 8);
                when x"A"   => O_DATA <= r_sr; sr_read_ena <= true;
                when x"B"   => O_DATA <= r_acr;
                when x"C"   => O_DATA <= r_pcr;
                when x"D"   => O_DATA <= r_ifr;
                when x"E"   => O_DATA <= ('0' & r_ier);
                when x"F"   => O_DATA <= r_ira;
                when others => null;
            end case;
        end if;

    end process;



    p_ca1_cb1_sel : process(sr_cb1_oe_l, sr_cb1_out, I_CB1)
    begin
        if (sr_cb1_oe_l = '1') then
            cb1_in_mux <= I_CB1;
        else
            cb1_in_mux <= sr_cb1_out;
        end if;
    end process;

    p_ca1_cb1_int : process(r_pcr, ca1_ip_reg, I_CA1, cb1_ip_reg, cb1_in_mux)
    begin
        if (r_pcr(0) = '0') then        -- ca1 control
            -- negative edge
            ca1_int <= (ca1_ip_reg = '1') and (I_CA1 = '0');
        else
            -- positive edge
            ca1_int <= (ca1_ip_reg = '0') and (I_CA1 = '1');
        end if;

        if (r_pcr(4) = '0') then        -- cb1 control
            -- negative edge
            cb1_int <= (cb1_ip_reg = '1') and (cb1_in_mux = '0');
        else
            -- positive edge
            cb1_int <= (cb1_ip_reg = '0') and (cb1_in_mux = '1');
        end if;
    end process;

    p_ca2_cb2_int : process(r_pcr, ca2_ip_reg, I_CA2, cb2_ip_reg, I_CB2)
    begin
        ca2_int <= false;
        if (r_pcr(3) = '0') then        -- ca2 input
            if (r_pcr(2) = '0') then    -- ca2 edge
                -- negative edge
                ca2_int <= (ca2_ip_reg = '1') and (I_CA2 = '0');
            else
                -- positive edge
                ca2_int <= (ca2_ip_reg = '0') and (I_CA2 = '1');
            end if;
        end if;

        cb2_int <= false;
        if (r_pcr(7) = '0') then        -- cb2 input
            if (r_pcr(6) = '0') then    -- cb2 edge
                -- negative edge
                cb2_int <= (cb2_ip_reg = '1') and (I_CB2 = '0');
            else
                -- positive edge
                cb2_int <= (cb2_ip_reg = '0') and (I_CB2 = '1');
            end if;
        end if;
    end process;

    p_ca2_cb2 : process(RESET_L, CLK)
    begin
        if (RESET_L = '0') then
            O_CA2 <= '0';
            O_CB2 <= '0';

            ca_hs_sr    <= '0';
            ca_hs_pulse <= '0';
            cb_hs_sr    <= '0';
            cb_hs_pulse <= '0';
        elsif rising_edge(CLK) then
            if (ENA_4 = '1') then
                -- ca
                if (phase = "00") and ((w_ora_hs = '1') or (r_ira_hs = '1')) then
                    ca_hs_sr <= '1';
                elsif ca1_int then
                    ca_hs_sr <= '0';
                end if;

                if (phase = "00") then
                    ca_hs_pulse <= w_ora_hs or r_ira_hs;
                end if;

                case r_pcr(3 downto 1) is
                    when "000"  => O_CA2 <= '0';                -- input
                    when "001"  => O_CA2 <= '0';                -- input
                    when "010"  => O_CA2 <= '0';                -- input
                    when "011"  => O_CA2 <= '0';                -- input
                    when "100"  => O_CA2 <= not (ca_hs_sr);     -- handshake
                    when "101"  => O_CA2 <= not (ca_hs_pulse);  -- pulse
                    when "110"  => O_CA2 <= '0';                -- low
                    when "111"  => O_CA2 <= '1';                -- high
                    when others => null;
                end case;

                -- cb
                if (phase = "00") and (w_orb_hs = '1') then
                    cb_hs_sr <= '1';
                elsif cb1_int then
                    cb_hs_sr <= '0';
                end if;

                if (phase = "00") then
                    cb_hs_pulse <= w_orb_hs;
                end if;

                if (sr_drive_cb2 = '1') then  -- serial output
                    O_CB2 <= sr_out;
                else
                    case r_pcr(7 downto 5) is
                        when "000"  => O_CB2 <= '0';             -- input
                        when "001"  => O_CB2 <= '0';             -- input
                        when "010"  => O_CB2 <= '0';             -- input
                        when "011"  => O_CB2 <= '0';             -- input
                        when "100"  => O_CB2 <= not (cb_hs_sr);  -- handshake
                        when "101"  => O_CB2 <= not (cb_hs_pulse);  -- pulse
                        when "110"  => O_CB2 <= '0';             -- low
                        when "111"  => O_CB2 <= '1';             -- high
                        when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;
    O_CB1 <= sr_cb1_out;

    p_ca_cb_irq : process(RESET_L, CLK)
    begin
        if (RESET_L = '0') then
            ca1_irq <= '0';
            ca2_irq <= '0';
            cb1_irq <= '0';
            cb2_irq <= '0';
        elsif rising_edge(CLK) then
            if (ENA_4 = '1') then
                -- not pretty
                if ca1_int then
                    ca1_irq <= '1';
                elsif (r_ira_hs = '1') or (w_ora_hs = '1') or (clear_irq(1) = '1') then
                    ca1_irq <= '0';
                end if;

                if ca2_int then
                    ca2_irq <= '1';
                else
                    if (((r_ira_hs = '1') or (w_ora_hs = '1')) and (r_pcr(1) = '0')) or
                        (clear_irq(0) = '1') then
                        ca2_irq <= '0';
                    end if;
                end if;

                if cb1_int then
                    cb1_irq <= '1';
                elsif (r_irb_hs = '1') or (w_orb_hs = '1') or (clear_irq(4) = '1') then
                    cb1_irq <= '0';
                end if;

                if cb2_int then
                    cb2_irq <= '1';
                else
                    if (((r_irb_hs = '1') or (w_orb_hs = '1')) and (r_pcr(5) = '0')) or
                        (clear_irq(3) = '1') then
                        cb2_irq <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;

    p_input_reg : process(RESET_L, CLK)
    begin
        if (RESET_L = '0') then
            ca1_ip_reg <= '0';
            cb1_ip_reg <= '0';

            ca2_ip_reg <= '0';
            cb2_ip_reg <= '0';

            r_ira <= x"00";
            r_irb <= x"00";

        elsif rising_edge(CLK) then
            if (ENA_4 = '1') then
                -- we have a fast clock, so we can have input registers
                ca1_ip_reg <= I_CA1;
                cb1_ip_reg <= cb1_in_mux;

                ca2_ip_reg <= I_CA2;
                cb2_ip_reg <= I_CB2;

                if (r_acr(0) = '0') then
                    r_ira <= I_PA;
                else                    -- enable latching
                    if ca1_int then
                        r_ira <= I_PA;
                    end if;
                end if;

                if (r_acr(1) = '0') then
                    r_irb <= I_PB;
                else                    -- enable latching
                    if cb1_int then
                        r_irb <= I_PB;
                    end if;
                end if;
            end if;
        end if;
    end process;


    p_buffers : process(r_ddra, r_ora, r_ddrb, r_acr, r_orb)
    begin
        -- data direction reg (ddr) 0 = input, 1 = output
        O_PA             <= r_ora;
        O_PB(7 downto 0) <= r_orb(7 downto 0);

    end process;
    --
    -- Timer 1
    --
    p_timer1_done : process(t1c, phase, r_acr)
        variable done : boolean;
    begin
        done              := (t1c = x"0000");
        t1c_done          <= done and (phase = "11");
        t1_reload_counter <= done and (r_acr(6) = '1');
    end process;

    p_timer1 : process
    begin
        wait until rising_edge(CLK);

        if t1_load_counter and phase = "11" then
            t1c(7 downto 0)  <= not r_t1l_l;
            t1c(15 downto 8) <= not r_t1l_h;
        else
            
            if (ENA_4 = '1') then
                if (phase = "11") then
                    t1c <= t1c + "1";
                end if;
            end if;
        end if;

        if t1_load_counter or t1_reload_counter then
            t1c_active <= true;
        elsif t1c_done then
            t1c_active <= false;
        end if;

        if RESET_L = '0' then
            t1c_active <= false;
        end if;

        t1_toggle <= '0';

        if t1c_active and t1c_done then
            t1_toggle <= '1';
            t1_irq    <= '1';
        elsif RESET_L = '0' or t1_w_reset_int or t1_r_reset_int or (clear_irq(6) = '1') then
            t1_irq <= '0';
        end if;
        
    end process;
    --
    -- Timer2
    --
    p_timer2_pb6_input : process
    begin
        wait until rising_edge(CLK);
        if (ENA_4 = '1') then
            if (phase = "01") then
                t2_pb6    <= I_PB(6);
                t2_pb6_t1 <= t2_pb6;
            end if;
        end if;
    end process;

    p_timer2_done : process(t2c, phase)
        variable done : boolean;
    begin
        done              := (t2c = x"0000");
        t2c_done          <= done and (phase = "11");
        t2_reload_counter <= done;
    end process;

    p_timer2 : process
        variable ena : boolean;
    begin
        wait until rising_edge(CLK);
        if (r_acr(5) = '0') then
            ena := true;
        else
            ena := (t2_pb6_t1 = '1') and (t2_pb6 = '0');
        end if;

        if t2_load_counter and (phase = "11") then
            t2c(7 downto 0)  <= not r_t2l_l;
            t2c(15 downto 8) <= not r_t2l_h;
        else
            if (ENA_4 = '1') then
                if (phase = "11") and ena then
                    t2c <= t2c + 1;
                end if;
            end if;
        end if;

        t2_sr_ena <= (t2c(7 downto 0) = x"00") and (phase = "11");

        if t2_load_counter then
            t2c_active <= true;
        elsif t2c_done then
            t2c_active <= false;
        end if;

        if RESET_L = '0' then
            t2c_active <= false;
        end if;

        if t2c_active and t2c_done then
            t2_irq <= '1';
        elsif RESET_L = '0' or t2_w_reset_int or t2_r_reset_int or (clear_irq(5) = '1') then
            t2_irq <= '0';
        end if;
    end process;
    --
    -- Shift Register
    --
    p_sr : process(RESET_L, CLK)
        variable dir_out      : std_logic;
        variable ena          : std_logic;
        variable cb1_op       : std_logic;
        variable cb1_ip       : std_logic;
        variable use_t2       : std_logic;
        variable free_run     : std_logic;
        variable sr_count_ena : boolean;
    begin
        if (RESET_L = '0') then
            r_sr         <= x"00";
            sr_drive_cb2 <= '0';
            sr_cb1_oe_l  <= '1';
            sr_cb1_out   <= '0';
            sr_strobe    <= '1';
            sr_cnt       <= "0000";
            sr_irq       <= '0';
            sr_out       <= '1';
            sr_off_delay <= '0';
        elsif rising_edge(CLK) then
            if (ENA_4 = '1') then
                -- decode mode
                dir_out  := r_acr(4);   -- output on cb2
                cb1_op   := '0';
                cb1_ip   := '0';
                use_t2   := '0';
                free_run := '0';

                case r_acr(4 downto 2) is
                    when "000"  => ena := '0'; cb1_ip := '1';
                    when "001"  => ena := '1'; cb1_op := '1'; use_t2 := '1';
                    when "010"  => ena := '1'; cb1_op := '1';
                    when "011"  => ena := '1'; cb1_ip := '1';
                    when "100"  => ena := '1'; use_t2 := '1'; free_run := '1';
                    when "101"  => ena := '1'; cb1_op := '1'; use_t2 := '1';
                    when "110"  => ena := '1';
                    when "111"  => ena := '1'; cb1_ip := '1';
                    when others => null;
                end case;

                if (cb1_ip = '1') then
                    sr_strobe <= I_CB1;
                else
                    if (sr_cnt(3) = '0') and (free_run = '0') then
                        sr_strobe <= '1';
                    else
                        if ((use_t2 = '1') and t2_sr_ena) or
                            ((use_t2 = '0') and (phase = "00")) then
                            sr_strobe <= not sr_strobe;
                        end if;
                    end if;
                end if;

                if sr_write_ena then
                    r_sr <= load_data;
                else
                    if (dir_out = '0') then
                        -- input
                        if (sr_cnt(3) = '1') or (cb1_ip = '1') then
                            if sr_strobe_rising then
                                r_sr <= r_sr(6 downto 0) & I_CB2;
                            end if;
                        end if;
                        sr_out <= '1';
                    else
                        -- output
                        if (sr_cnt(3) = '1') or (sr_off_delay = '1') or (cb1_ip = '1') or (free_run = '1') then
                            if sr_strobe_falling then
                                r_sr(7 downto 1) <= r_sr(6 downto 0);
                                r_sr(0)          <= r_sr(7);
                                sr_out           <= r_sr(7);
                            end if;
                        else
                            sr_out <= '1';
                        end if;
                    end if;
                end if;

                sr_count_ena := sr_strobe_rising;

                if sr_write_ena or sr_read_ena then
                    sr_cnt <= "1000";
                elsif sr_count_ena and (sr_cnt(3) = '1') then
                    sr_cnt <= sr_cnt + "1";
                end if;

                if (phase = "00") then
                    sr_off_delay <= sr_cnt(3);  -- give some hold time when shifting out
                end if;

                if sr_count_ena and (sr_cnt = "1111") and (ena = '1') and (free_run = '0') then
                    sr_irq <= '1';
                elsif sr_write_ena or sr_read_ena or (clear_irq(2) = '1') then
                    sr_irq <= '0';
                end if;

                -- assign ops
                sr_drive_cb2 <= dir_out;
                sr_cb1_oe_l  <= not cb1_op;
                sr_cb1_out   <= sr_strobe;
            end if;
        end if;
    end process;

    p_sr_strobe_rise_fall : process
    begin
        wait until rising_edge(CLK);
        if (ENA_4 = '1') then
            sr_strobe_t1      <= sr_strobe;
            sr_strobe_rising  <= (sr_strobe_t1 = '0') and (sr_strobe = '1');
            sr_strobe_falling <= (sr_strobe_t1 = '1') and (sr_strobe = '0');
        end if;
    end process;
    --
    -- Interrupts
    --
    p_ier : process(RESET_L, CLK)
    begin
        if (RESET_L = '0') then
            r_ier <= "0000000";
        elsif rising_edge(CLK) then
            if (ENA_4 = '1') then
                if ier_write_ena then
                    if (load_data(7) = '1') then
                        -- set
                        r_ier <= r_ier or load_data(6 downto 0);
                    else
                        -- clear
                        r_ier <= r_ier and not load_data(6 downto 0);
                    end if;
                end if;
            end if;
        end if;
    end process;

    p_ifr : process(t1_irq, t2_irq, final_irq, ca1_irq, ca2_irq, sr_irq,
                    cb1_irq, cb2_irq)
    begin
        r_ifr(7) <= final_irq;
        r_ifr(6) <= t1_irq;
        r_ifr(5) <= t2_irq;
        r_ifr(4) <= cb1_irq;
        r_ifr(3) <= cb2_irq;
        r_ifr(2) <= sr_irq;
        r_ifr(1) <= ca1_irq;
        r_ifr(0) <= ca2_irq;

        O_IRQ_L <= not final_irq;
    end process;

    p_irq : process(RESET_L, CLK)
    begin
        if (RESET_L = '0') then
            final_irq <= '0';
        elsif rising_edge(CLK) then
            if (ENA_4 = '1') then
                if ((r_ifr(6 downto 0) and r_ier(6 downto 0)) = "0000000") then
                    final_irq <= '0';   -- no interrupts
                else
                    final_irq <= '1';
                end if;
            end if;
        end if;
    end process;

    p_clear_irq : process(ifr_write_ena, load_data)
    begin
        clear_irq <= x"00";
        if ifr_write_ena then
            clear_irq <= load_data;
        end if;
    end process;

end architecture RTL;
