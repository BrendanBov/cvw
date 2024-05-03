

onbreak {resume}

# create library
if [file exists work] {
    vdel -all
}
vlib work

# compile source files
vlog testbenchLFSR.sv

# start and run simulation
vsim -debugdb -voptargs=+acc work.testbench

# view list
# view wave

# Load Decoding
do wave.do

-- display input and output signals as hexidecimal values
# Diplays All Signals recursively
# add wave -hex -r /stimulus/*
add wave -noupdate -divider -height 32 "Top"
add wave -hex /testbenchLFSR/*



-- Set Wave Output Items 
TreeUpdate [SetDefaultTree]
WaveRestoreZoom {0 ps} {200 ns}
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2

-- Run the Simulation
#run 3000 ns
run 5 us

-- Save memory for checking (if needed)
# mem save -outfile memory.dat -wordsperline 1 /testbench/dut/dmem/RAM
