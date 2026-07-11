-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2023 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2023.2 (win64) Build 4029153 Fri Oct 13 20:14:34 MDT 2023
-- Date        : Sat Jul 11 13:49:56 2026
-- Host        : DESKTOP-MO7L2KR running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub -rename_top mult_gen_u33 -prefix
--               mult_gen_u33_ mult_gen_u33_stub.vhdl
-- Design      : mult_gen_u33
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7k325tffg900-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity mult_gen_u33 is
  Port ( 
    CLK : in STD_LOGIC;
    A : in STD_LOGIC_VECTOR ( 32 downto 0 );
    B : in STD_LOGIC_VECTOR ( 32 downto 0 );
    P : out STD_LOGIC_VECTOR ( 65 downto 0 )
  );

end mult_gen_u33;

architecture stub of mult_gen_u33 is
attribute syn_black_box : boolean;
attribute black_box_pad_pin : string;
attribute syn_black_box of stub : architecture is true;
attribute black_box_pad_pin of stub : architecture is "CLK,A[32:0],B[32:0],P[65:0]";
attribute x_core_info : string;
attribute x_core_info of stub : architecture is "mult_gen_v12_0_19,Vivado 2023.2";
begin
end;
