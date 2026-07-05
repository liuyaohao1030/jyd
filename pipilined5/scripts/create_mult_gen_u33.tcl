# Create the RV32M multiplier IP used by mul_ip_wrapper.v.
# Run from the Vivado Tcl console after opening the project:
#
#   source scripts/create_mult_gen_u33.tcl
#
# The exact Multiplier Generator CONFIG property names are Vivado/IP-version
# specific. This script intentionally creates the IP and prints the available
# CONFIG properties instead of guessing names that may not exist in 2023.2.
# Use the GUI steps in the final instructions to set the parameters below, or
# copy the exact property names from the printed list and add set_property here.

set ip_name mult_gen_u33

if {[llength [get_ips -quiet $ip_name]] == 0} {
    create_ip -name mult_gen -vendor xilinx.com -library ip -module_name $ip_name
}

puts "Created/found IP: $ip_name"
puts "Required GUI configuration:"
puts "  IP                    : Multiplier Generator"
puts "  Component Name        : mult_gen_u33"
puts "  A Width               : 33"
puts "  B Width               : 33"
puts "  Input Type            : Signed / two's complement signed"
puts "  Output Product Width  : 66, full precision"
puts "  Multiplier Type       : DSP48 / DSP block implementation"
puts "  Pipeline / Latency    : Automatic / Performance / Speed / maximum pipelining"
puts "  Clock                 : CPU clk_out2_pll / EX-stage clk"
puts "  CE / Clock Enable     : disabled if configurable; tie high if generated"
puts "  Reset / SCLR          : disabled if configurable; tie inactive if generated"
puts ""
puts "Available CONFIG properties for $ip_name:"
foreach p [lsort [list_property [get_ips $ip_name]]] {
    if {[string match "CONFIG.*" $p]} {
        puts [format "  %-45s %s" $p [get_property $p [get_ips $ip_name]]]
    }
}

puts ""
puts "After configuring the IP, run:"
puts "  generate_target all [get_ips $ip_name]"
puts "  export_ip_user_files -of_objects [get_ips $ip_name] -no_script -sync -force -quiet"
puts ""
puts "Then check mult_gen_u33.veo. The RTL wrapper currently expects native ports:"
puts "  CLK"
puts "  A[32:0]"
puts "  B[32:0]"
puts "  P[65:0]"
puts "If the template includes CE/ACLKEN or SCLR/ARESET, either regenerate without"
puts "those optional ports or connect CE to 1'b1 and reset to its inactive value in"
puts "mul_ip_wrapper.v. Also update MUL_LATENCY in mul_ip_wrapper.v to match the"
puts "latency reported by the GUI/veo."
