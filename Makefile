SV_SRCS := design/Helios_single_FPGA_core.v \
  design/single_FPGA_decoding_graph_dynamic_rsc.sv \
  design/control_node_single_FPGA.v \
  design/processing_unit_single_FPGA_v2.v \
  design/fifo_fwft.v \
  design/neighbor_link_internal_v2.v \
  design/tree_compare_solver.sv \
  design/serdes.sv

SV_INCS := -I design

test: build/full.vvp build/tree_compare.vvp build/min_val_less.vvp build/serdes.vvp build/blocking_channel.vvp
	vvp build/full.vvp
	vvp build/tree_compare.vvp
	vvp build/min_val_less.vvp
	vvp build/serdes.vvp
	vvp build/blocking_channel.vvp

build:
	@mkdir build

build/full.vvp: build $(SV_SRCS) test_benches/full_tests/single_FPGA_FIFO_verification_test_rsc.sv 
	iverilog -o build/full.vvp -g2012 $(SV_INCS) $(SV_SRCS) test_benches/full_tests/single_FPGA_FIFO_verification_test_rsc.sv

build/tree_compare.vvp: build $(SV_SRCS) test_benches/unit_tests/test_tree_compare_solver.sv
	iverilog -o build/tree_compare.vvp -g2012 $(SV_INCS) $(SV_SRCS) test_benches/unit_tests/test_tree_compare_solver.sv

build/min_val_less.vvp: build $(SV_SRCS) test_benches/unit_tests/test_min_val_less_8x_with_index.v
	iverilog -o build/min_val_less.vvp -g2012 $(SV_INCS) $(SV_SRCS) test_benches/unit_tests/test_min_val_less_8x_with_index.v

build/serdes.vvp: build $(SV_SRCS) test_benches/unit_tests/test_serdes.sv
	iverilog -o build/serdes.vvp -g2012 $(SV_INCS) $(SV_SRCS) test_benches/unit_tests/test_serdes.sv

build/blocking_channel.vvp: build design/blocking_channel.sv design/fifo_fwft.v test_benches/unit_tests/test_blocking_channel.sv
	iverilog -o build/blocking_channel.vvp -g2012 $(SV_INCS) design/blocking_channel.sv design/fifo_fwft.v test_benches/unit_tests/test_blocking_channel.sv

clean:
	rm -f build/*.vvp

linecount:
	wc -l $(SV_SRCS)

build/print_corrections.vvp: build $(SV_SRCS) test_benches/full_tests/print_corrections.sv 
	iverilog -o build/print_corrections.vvp -g2012 $(SV_INCS) $(SV_SRCS) test_benches/full_tests/print_corrections.sv

print_corrections: build build/print_corrections.vvp
	vvp build/print_corrections.vvp

build/test_corner_case.vvp: build $(SV_SRCS) test_benches/full_tests/test_corner_case.sv 
	iverilog -o build/test_corner_case.vvp -g2012 $(SV_INCS) $(SV_SRCS) test_benches/full_tests/test_corner_case.sv

test_corner_case: build build/test_corner_case.vvp
	vvp build/test_corner_case.vvp