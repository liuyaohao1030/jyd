# Create the RV32M unsigned divider IP used by div_ip_wrapper.v.
# Run from the Vivado Tcl console after opening the project:
#
#   source scripts/create_div_gen_u32.tcl
#
# The exact Divider Generator CONFIG property names are Vivado/IP-version
# specific. This script intentionally creates the IP and prints the available
# CONFIG properties instead of guessing names that may not exist in 2023.2.
# Use the GUI steps in the final instructions to set the parameters below, or
# copy the exact property names from the printed list and add set_property here.

set ip_name div_gen_u32

if {[llength [get_ips -quiet $ip_name]] == 0} {
    create_ip -name div_gen -vendor xilinx.com -library ip -module_name $ip_name
}

puts "Created/found IP: $ip_name"
puts "Required GUI configuration:"
puts "  Algorithm Type        : Radix-2"
puts "  Operand Sign          : Unsigned"
puts "  Dividend Width        : 32"
puts "  Divisor Width         : 32"
puts "  Remainder Type        : Remainder"
puts "  Clocks Per Division   : 1"
puts "  Flow Control          : NonBlocking"
puts "  Output has TREADY     : False / unchecked"
puts "  Latency Configuration : Automatic"
puts "  Detect Divide-by-Zero : unchecked; wrapper handles it"
puts "  ACLKEN                : False / unchecked"
puts "  ARESETn               : enabled if available"
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
puts "Then check div_gen_u32.veo. The RTL wrapper expects these synthesis ports:"
puts "  aclk, aresetn"
puts "  s_axis_dividend_tvalid, s_axis_dividend_tdata[31:0]"
puts "  s_axis_divisor_tvalid,  s_axis_divisor_tdata[31:0]"
puts "  m_axis_dout_tvalid, m_axis_dout_tdata[63:0]"
puts "No tready or aclken ports should be enabled for this configuration."
