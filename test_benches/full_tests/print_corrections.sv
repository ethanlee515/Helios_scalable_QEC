`timescale 1ns / 10ps

// Output file format
// Each line corresponds to a valid payload from `output_fifo`

module print_corrections;

`include "./parameters.sv"

localparam CODE_DISTANCE = 7;                
localparam CODE_DISTANCE_X = CODE_DISTANCE + 1;
localparam CODE_DISTANCE_Z = (CODE_DISTANCE_X - 1)/2;

parameter GRID_WIDTH_X = CODE_DISTANCE + 1;
parameter GRID_WIDTH_Z = (CODE_DISTANCE_X - 1)/2;
parameter GRID_WIDTH_U = CODE_DISTANCE;
parameter MAX_WEIGHT = 2;

`define MAX(a, b) (((a) > (b)) ? (a) : (b))
localparam MEASUREMENT_ROUNDS = CODE_DISTANCE;

localparam PU_COUNT = CODE_DISTANCE_X * CODE_DISTANCE_Z * MEASUREMENT_ROUNDS;

localparam X_BIT_WIDTH = $clog2(GRID_WIDTH_X);
localparam Z_BIT_WIDTH = $clog2(GRID_WIDTH_Z);
localparam U_BIT_WIDTH = $clog2(GRID_WIDTH_U);
localparam ADDRESS_WIDTH = X_BIT_WIDTH + Z_BIT_WIDTH + U_BIT_WIDTH;

localparam ITERATION_COUNTER_WIDTH = 8;  // counts up to CODE_DISTANCE iterations

// localparam NS_ERROR_COUNT = (CODE_DISTANCE_X-1) * CODE_DISTANCE_Z * MEASUREMENT_ROUNDS;
// localparam EW_ERROR_COUNT = CODE_DISTANCE_X * (CODE_DISTANCE_Z+1) * MEASUREMENT_ROUNDS;
// localparam UD_ERROR_COUNT = CODE_DISTANCE_X * CODE_DISTANCE_Z * MEASUREMENT_ROUNDS;
// localparam CORRECTION_COUNT = NS_ERROR_COUNT + EW_ERROR_COUNT + UD_ERROR_COUNT;

reg clk;
reg reset;


wire [(ADDRESS_WIDTH * PU_COUNT)-1:0] roots;

`define BYTES_PER_ROUND ((CODE_DISTANCE_X * CODE_DISTANCE_Z  + 7) >> 3)
`define ALIGNED_PU_PER_ROUND (`BYTES_PER_ROUND << 3)

reg [`ALIGNED_PU_PER_ROUND*GRID_WIDTH_U-1:0] measurements;

`define INDEX(i, j, k) (i * CODE_DISTANCE_Z + j + k * CODE_DISTANCE_Z*CODE_DISTANCE_X)
`define PADDED_INDEX(i, j, k) (i * CODE_DISTANCE_Z + j + k * `ALIGNED_PU_PER_ROUND)
`define measurements(i, j, k) measurements[`PADDED_INDEX(i, j, k)]
// `define is_odd_cluster(i, j, k) decoder.is_odd_clusters[`INDEX(i, j, k)]
`define root(i, j, k) decoder.roots[ADDRESS_WIDTH*`INDEX(i, j, k) +: ADDRESS_WIDTH]
`define root_x(i, j, k) decoder.roots[ADDRESS_WIDTH*`INDEX(i, j, k)+Z_BIT_WIDTH +: X_BIT_WIDTH]
`define root_z(i, j, k) decoder.roots[ADDRESS_WIDTH*`INDEX(i, j, k) +: Z_BIT_WIDTH]
`define root_u(i, j, k) decoder.roots[ADDRESS_WIDTH*`INDEX(i, j, k)+X_BIT_WIDTH+Z_BIT_WIDTH +: U_BIT_WIDTH]

reg [7:0] input_data;
reg input_valid;
wire input_ready;
wire [7:0] output_data;
wire output_valid;
reg output_ready;

wire [7:0] input_data_fifo;
wire input_valid_fifo;
wire input_ready_fifo;
wire [7:0] output_data_fifo;
wire output_valid_fifo;
wire output_ready_fifo;

// instantiate
Helios_single_FPGA #(
    .GRID_WIDTH_X(GRID_WIDTH_X),
    .GRID_WIDTH_Z(GRID_WIDTH_Z),
    .GRID_WIDTH_U(GRID_WIDTH_U),
    .MAX_WEIGHT(MAX_WEIGHT)
 ) decoder (
    .clk(clk),
    .reset(reset),
    .input_data(input_data_fifo),
    .input_valid(input_valid_fifo),
    .input_ready(input_ready_fifo),
    .output_data(output_data_fifo),
    .output_valid(output_valid_fifo),
    .output_ready(output_ready_fifo)
    
    //.roots(roots)
);

// FIFO
fifo_wrapper #(
    .WIDTH(8),
    .DEPTH(128)
) input_fifo (
    .clk(clk),
    .reset(reset),
    .input_data(input_data),
    .input_valid(input_valid),
    .input_ready(input_ready),
    .output_data(input_data_fifo),
    .output_valid(input_valid_fifo),
    .output_ready(input_ready_fifo)
);

fifo_wrapper #(
    .WIDTH(8),
    .DEPTH(128)
) output_fifo (
    .clk(clk),
    .reset(reset),
    .input_data(output_data_fifo),
    .input_valid(output_valid_fifo),
    .input_ready(output_ready_fifo),
    .output_data(output_data),
    .output_valid(output_valid),
    .output_ready(output_ready)
);

always #5 clk = ~clk;  // flip every 5ns, that is 100MHz clock

reg valid_delayed = 0;
integer i;
integer j;
integer k;
integer input_file, corrections_file;
int v;
reg input_open = 1;
reg corrections_open = 1;
reg eof = 0;
reg input_eof = 0;
reg [31:0] read_value, test_case, input_read_value;
reg [X_BIT_WIDTH-1 : 0] expected_x;
reg [Z_BIT_WIDTH-1 : 0] expected_z;
reg [U_BIT_WIDTH-1 : 0] expected_u;
reg test_fail;
reg processing = 0;
reg [31:0] syndrome_count;
reg [31:0] corrections_count = 0;

reg [2:0] loading_state;
reg [31:0] input_fifo_counter;

reg new_round_start;
reg [31:0] cycle_counter;
reg [31:0] iteration_counter;
reg [31:0] message_counter;

always @(posedge clk) begin
    if(reset) begin
        loading_state <= 3'b0;
    end else begin
        case(loading_state)
            3'b0: begin
                loading_state <= 3'b1;
                input_fifo_counter <= 0;
            end
            3'b1: begin // start decoding header
                loading_state <= 3'b10;
            end
            3'b10: begin // measurement data header
                loading_state <= 3'b11;
                input_fifo_counter <= 0;
            end
            3'b11: begin
                if (input_fifo_counter == (`BYTES_PER_ROUND*GRID_WIDTH_U-1)) begin
                    loading_state <= 3'b100;
                end
                input_fifo_counter <= input_fifo_counter + 1; 
            end
            3'b100: begin
                if(output_valid == 1) begin
                    loading_state <= 3'b101;
                    message_counter <= 0;
                end
            end
            3'b101: begin
                if(output_valid == 0) begin
                    loading_state <= 3'b10;
                end else begin
                    message_counter <= message_counter + 1;
                    if (message_counter == 0) begin
                        iteration_counter <= {24'b0, output_data[7:0]};
                    end
                    if (message_counter == 1) begin
                        cycle_counter[15:8] <= {24'b0, output_data[7:0]};
                    end
                    if (message_counter == 2) begin
                        cycle_counter[7:0] <= {24'b0, output_data[7:0]};
                    end
                    cycle_counter[31:16] <= 16'b0;
                end
                
            end
        endcase
    end
end

always@(*) begin
    if(loading_state == 3'b1) begin
        input_valid = 1;
        input_data = START_DECODING_MSG;
    end else if (loading_state == 3'b10) begin
        input_valid = 1;
        input_data = MEASUREMENT_DATA_HEADER;
    end else if (loading_state == 3'b11) begin
        input_valid = 1;
        input_data = measurements[input_fifo_counter*8 +: 8];
    end else begin
        input_valid = 0;
    end
end

always @(*) begin
    if (loading_state == 3'b101) begin
        output_ready = 1;
    end else begin
        output_ready = 0;
    end
end

// Input loading logic
always @(negedge clk) begin
    if (loading_state == 3'b10) begin
        measurements = 0;
        if(input_open == 1) begin
            input_file = $fopen ("test_benches/test_data/input_data_7_rsc.txt", "r");
            input_open = 0;
        end
        if (input_eof == 0)begin 
            v = $fscanf (input_file, "%h\n", test_case);
            input_eof = $feof(input_file);
            if (input_eof == 0)begin 
                syndrome_count = 0;
            end
        end
        for (k=0 ;k <MEASUREMENT_ROUNDS; k++) begin
            for (i=0 ;i <CODE_DISTANCE_X; i++) begin
                for (j=0 ;j <CODE_DISTANCE_Z; j++) begin
                    if (input_eof == 0)begin 
                        v = $fscanf (input_file, "%h\n", input_read_value);
                        `measurements(i, j, k) = input_read_value;
                        if (input_read_value == 1) begin
                            syndrome_count = syndrome_count + 1;
                        end
                    end
                end
            end
        end
    end else begin
        new_round_start = 0;
    end
end

// Writing output onto file
always @(posedge clk) begin
    if(corrections_open == 1) begin
        corrections_file = $fopen("test_benches/test_data/corrections_7.txt", "w");
        corrections_open = 0;
    end
    if(decoder.controller.output_fifo_valid) begin
        $fwrite(corrections_file, "%h\n", decoder.controller.output_fifo_data);
        corrections_count = corrections_count + 1;
    end
    if(corrections_count == 100 * CODE_DISTANCE) begin
        $fclose(corrections_file);
        $finish;
    end
end

initial begin
    clk = 1'b1;
    reset = 1'b1;

    #107;
    reset = 1'b0;
    #100;


end


endmodule
