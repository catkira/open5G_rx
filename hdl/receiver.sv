`timescale 1ns / 1ns

`ifdef VERILATOR  // make parameter readable from VPI
  `define VL_RD /*verilator public_flat_rd*/
`else
  `define VL_RD
`endif

module receiver
#(
    parameter IN_DW `VL_RD = 32,           // input data width
    parameter OUT_DW `VL_RD = 32,          // correlator output data width
    parameter TAP_DW `VL_RD = 32,
    parameter PSS_LEN `VL_RD = 128,
    parameter [TAP_DW * PSS_LEN - 1 : 0] PSS_LOCAL_0 `VL_RD = {(PSS_LEN * TAP_DW){1'b0}},
    parameter [TAP_DW * PSS_LEN - 1 : 0] PSS_LOCAL_1 `VL_RD = {(PSS_LEN * TAP_DW){1'b0}},
    parameter [TAP_DW * PSS_LEN - 1 : 0] PSS_LOCAL_2 `VL_RD = {(PSS_LEN * TAP_DW){1'b0}},
    parameter ALGO `VL_RD = 1,
    parameter WINDOW_LEN `VL_RD = 8,
    parameter CP_ADVANCE `VL_RD = 9,
    localparam FFT_OUT_DW `VL_RD = 32,
    localparam N_id_1_MAX `VL_RD = 335
)
(
    input                                           clk_i,
    input                                           reset_ni,
    input   wire    [IN_DW-1:0]                     s_axis_in_tdata,
    input                                           s_axis_in_tvalid,

    output                                          PBCH_valid_o,
    output                                          SSS_valid_o,
    output          [FFT_OUT_DW-1:0]                m_axis_out_tdata,
    output                                          m_axis_out_tvalid,
    output          [$clog2(N_id_1_MAX) - 1 : 0]    m_axis_SSS_tdata,
    output                                          m_axis_SSS_tvalid,
    
    // debug outputs
    output  wire    [IN_DW-1:0]                     m_axis_cic_debug_tdata,
    output  wire                                    m_axis_cic_debug_tvalid,
    output  wire    [OUT_DW - 1 : 0]                m_axis_correlator_debug_tdata,
    output  wire                                    m_axis_correlator_debug_tvalid,
    output  reg                                     peak_detected_debug_o,
    output  wire    [FFT_OUT_DW-1:0]                fft_result_debug_o,
    output  wire                                    fft_sync_debug_o,
    output  wire    [15:0]                          sync_wait_counter_debug_o,
    output  reg                                     fft_demod_PBCH_start_o,
    output  reg                                     fft_demod_SSS_start_o
);

wire [IN_DW - 1 : 0] m_axis_cic_tdata;
wire                 m_axis_cic_tvalid;
assign m_axis_cic_debug_tdata = m_axis_cic_tdata;
assign m_axis_cic_debug_tvalid = m_axis_cic_tvalid;

cic_d #(
    .INP_DW(IN_DW/2),
    .OUT_DW(IN_DW/2),
    .CIC_R(2),
    .CIC_N(3),
    .VAR_RATE(0)
)
cic_real(
    .clk(clk_i),
    .reset_n(reset_ni),
    .s_axis_in_tdata(s_axis_in_tdata[IN_DW / 2 - 1 -: IN_DW / 2]),
    .s_axis_in_tvalid(s_axis_in_tvalid),
    .m_axis_out_tdata(m_axis_cic_tdata[IN_DW / 2 - 1 -: IN_DW / 2]),
    .m_axis_out_tvalid(m_axis_cic_tvalid)
);

cic_d #(
    .INP_DW(IN_DW / 2),
    .OUT_DW(IN_DW / 2),
    .CIC_R(2),
    .CIC_N(3),
    .VAR_RATE(0)
)
cic_imag(
    .clk(clk_i),
    .reset_n(reset_ni),
    .s_axis_in_tdata(s_axis_in_tdata[IN_DW - 1 -: IN_DW / 2]),
    .s_axis_in_tvalid(s_axis_in_tvalid),
    .m_axis_out_tdata(m_axis_cic_tdata[IN_DW - 1 -: IN_DW / 2])
);


wire [OUT_DW - 1 : 0] correlator_tdata;
wire correlator_tvalid;
assign m_axis_correlator_debug_tdata = correlator_tdata;
assign m_axis_correlator_debug_tvalid = correlator_tvalid;

reg N_id_2_valid;
wire [1 : 0] N_id_2;
wire [1 : 0] PSS_detector_mode;
wire [1 : 0] requested_N_id_2;

PSS_detector #(
    .IN_DW(IN_DW),
    .OUT_DW(OUT_DW),
    .TAP_DW(TAP_DW),
    .PSS_LEN(PSS_LEN),
    .PSS_LOCAL_0(PSS_LOCAL_0),
    .PSS_LOCAL_1(PSS_LOCAL_1),
    .PSS_LOCAL_2(PSS_LOCAL_2),
    .ALGO(ALGO),
    .USE_MODE(1)
)
PSS_detector_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .s_axis_in_tdata(m_axis_cic_tdata),
    .s_axis_in_tvalid(m_axis_cic_tvalid),
    .mode_i(PSS_detector_mode),
    .requested_N_id_2_i(requested_N_id_2),

    .N_id_2_valid_o(N_id_2_valid),
    .N_id_2_o(N_id_2)
);

assign peak_detected_debug_o = N_id_2_valid;

wire [FFT_OUT_DW - 1 : 0] fft_result, fft_result_demod;
wire [FFT_OUT_DW / 2 - 1 : 0] fft_result_re, fft_result_im;
wire fft_result_demod_valid;
wire fft_sync;

assign fft_result_debug_o = fft_result;
assign fft_sync_debug_o = fft_sync;

// this delay line is needed because peak_detected goes high
// at the end of SSS symbol plus some additional delay
localparam DELAY_LINE_LEN = 16;
reg [IN_DW-1:0] delay_line_data  [0 : DELAY_LINE_LEN - 1];
reg             delay_line_valid [0 : DELAY_LINE_LEN - 1];
always @(posedge clk_i) begin
    if (!reset_ni) begin
        for (integer i = 0; i < DELAY_LINE_LEN; i = i + 1) begin
            delay_line_data[i] = '0;
            delay_line_valid[i] = '0;
        end
    end else begin
        delay_line_data[0] <= s_axis_in_tdata;
        delay_line_valid[0] <= s_axis_in_tvalid;
        for (integer i = 0; i < DELAY_LINE_LEN - 1; i = i + 1) begin
            delay_line_data[i+1] <= delay_line_data[i];
            delay_line_valid[i+1] <= delay_line_valid[i];
        end
    end
end

reg [IN_DW - 1 : 0]     fs_out_tdata;
reg fs_out_tvalid;
reg fs_out_PBCH_start;
reg fs_out_symbol_start;
reg fs_out_SSS_start;


frame_sync #(
    .IN_DW(IN_DW)
)
frame_sync_i
(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .N_id_2_i(N_id_2),
    .N_id_2_valid_i(N_id_2_valid),
    .ibar_SSB_i(ce_ibar_SSB),
    .ibar_SSB_valid_i(ce_ibar_SSB_valid),
    .s_axis_in_tdata(delay_line_data[DELAY_LINE_LEN - 1]),
    .s_axis_in_tvalid(delay_line_valid[DELAY_LINE_LEN - 1]),

    .PSS_detector_mode_o(PSS_detector_mode),
    .requested_N_id_2_o(requested_N_id_2),

    .m_axis_out_tdata(fs_out_tdata),
    .m_axis_out_tvalid(fs_out_tvalid),
    .symbol_start_o(fs_out_symbol_start),
    .PBCH_start_o(fs_out_PBCH_start),
    .SSS_start_o(fs_out_SSS_start)
);

FFT_demod #(
    .IN_DW(IN_DW),
    .CP_ADVANCE(CP_ADVANCE)
)
FFT_demod_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .SSB_start_i(fs_out_PBCH_start),
    .s_axis_in_tdata(fs_out_tdata),
    .s_axis_in_tvalid(fs_out_tvalid),
    .m_axis_out_tdata(m_axis_out_tdata),
    .m_axis_out_tvalid(m_axis_out_tvalid),
    .PBCH_start_o(fft_demod_PBCH_start_o),
    .SSS_start_o(fft_demod_SSS_start_o),
    .PBCH_valid_o(PBCH_valid_o),
    .SSS_valid_o(SSS_valid_o)
);

reg [10 : 0] PSS_cnt;
reg [3 : 0] state;
localparam SSS_START = 63;
localparam SSS_LEN = 127;
reg [$clog2(SSS_LEN) - 1 : 0] SSS_wait_cnt;
always @(posedge clk_i) begin
    if (!reset_ni) begin
        state <= 2;
        SSS_wait_cnt <= '0;
        SSS_valid <= '0;
    end else if (state == 2) begin // wait for SSS bits in SSS symbol
        if (SSS_wait_cnt == SSS_START && SSS_valid_o) begin
            $display("state 3");
            state <= 3;
            SSS_wait_cnt <= '0;
            SSS_valid <= 1;
        end else if (SSS_valid_o) begin
            SSS_wait_cnt <= SSS_wait_cnt + 1;
        end
    end else if (state == 3) begin // transfer SSS bites to SSS detector
        if (SSS_wait_cnt == SSS_LEN) begin
            $display("state 0");
            SSS_wait_cnt <= '0;
            SSS_valid <= 0;
            state <= 4;
        end else if (SSS_valid_o) begin
            $display("SSB bit %d", ~m_axis_out_tdata[FFT_OUT_DW / 2 - 1]);
            SSS_wait_cnt <= SSS_wait_cnt + 1;
            SSS_valid <= 1;
        end else begin
            SSS_valid <= 0;
        end
    end else if (state == 4) begin // wait for SSS detector to finish
        if (m_axis_SSS_tvalid) begin
            $display("detected N_id_1 %d", m_axis_SSS_tdata);
            state <= 2;
        end
    end
end

reg         SSS_valid;
SSS_detector
SSS_detector_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .N_id_2_i(N_id_2),
    .N_id_2_valid_i(N_id_2_valid),
    .s_axis_in_tdata(~m_axis_out_tdata[FFT_OUT_DW / 2 - 1]), // BPSK demod by just taking the MSB of the real part
    .s_axis_in_tvalid(SSS_valid),
    .m_axis_out_tdata(m_axis_SSS_tdata),
    .m_axis_out_tvalid(m_axis_SSS_tvalid),
    .N_id_o(N_id),
    .N_id_valid_o(N_id_valid)
);

reg [2 : 0] ce_ibar_SSB;
reg ce_ibar_SSB_valid;

localparam N_ID_MAX = 1007;
reg [$clog2(N_ID_MAX) - 1 : 0] N_id;
reg N_id_valid;

channel_estimator #(
    .IN_DW(IN_DW)
)
channel_estimator_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .N_id_i(N_id),
    .N_id_valid_i(N_id_valid),
    .PBCH_start_i(fft_demod_PBCH_start_o),
    .s_axis_in_tdata(m_axis_out_tdata),
    .s_axis_in_tvalid(PBCH_valid_o),

    .m_axis_out_tdata(),
    .m_axis_out_tvalid(),

    .debug_ibar_SSB_o(ce_ibar_SSB),
    .debug_ibar_SSB_valid_o(ce_ibar_SSB_valid)
);

`ifdef COCOTB_SIM
initial begin
  $dumpfile ("receiver.vcd");
  $dumpvars (0, receiver);
end
`endif

endmodule

