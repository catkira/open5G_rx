`timescale 1ns / 1ns

module PSS_detector
#(
    parameter IN_DW = 32,           // input data width
    parameter OUT_DW = 32,          // correlator output data width
    parameter TAP_DW = 32,
    parameter PSS_LEN = 128,
    parameter [TAP_DW * PSS_LEN - 1 : 0] PSS_LOCAL_0 = {(PSS_LEN * TAP_DW){1'b0}},
    parameter [TAP_DW * PSS_LEN - 1 : 0] PSS_LOCAL_1 = {(PSS_LEN * TAP_DW){1'b0}},
    parameter [TAP_DW * PSS_LEN - 1 : 0] PSS_LOCAL_2 = {(PSS_LEN * TAP_DW){1'b0}},
    parameter USE_TAP_FILE = 0,
    parameter TAP_FILE_0 = "",
    parameter TAP_FILE_1 = "",
    parameter TAP_FILE_2 = "",
    parameter ALGO = 1,
    parameter WINDOW_LEN = 8,
    parameter USE_MODE = 0,
    parameter CFO_LIMIT = 0,
    parameter CFO_DW = 24,
    parameter DDS_DW = 20
)
(
    input                                       clk_i,
    input                                       reset_ni,
    input   wire           [IN_DW-1:0]          s_axis_in_tdata,
    input                                       s_axis_in_tvalid,

    input                  [1 : 0]              mode_i,
    input                  [1 : 0]              requested_N_id_2_i,
    
    output  reg            [1 : 0]              N_id_2_o,
    output                                      N_id_2_valid_o,
    output  reg signed     [CFO_DW - 1 : 0]     CFO_angle_o,
    output  reg signed     [DDS_DW - 1 : 0]     CFO_DDS_inc_o,
    output  reg                                 CFO_valid_o,
    
    // debug outputs
    output  wire           [IN_DW-1:0]          m_axis_cic_debug_tdata,
    output  wire                                m_axis_cic_debug_tvalid,
    output  wire           [OUT_DW - 1 : 0]     m_axis_correlator_debug_tdata,
    output  wire                                m_axis_correlator_debug_tvalid,
    output                 [TAP_DW - 1 : 0]     taps_2_o [0 : PSS_LEN - 1]
);

localparam C_DW = IN_DW + TAP_DW + 2 + 2 * $clog2(PSS_LEN);

wire [OUT_DW - 1 : 0] correlator_0_tdata, correlator_1_tdata, correlator_2_tdata;
wire correlator_0_tvalid, correlator_1_tvalid, correlator_2_tvalid;
wire [C_DW - 1 : 0] C0 [0 : 2];
wire [C_DW - 1 : 0] C1 [0 : 2];
assign m_axis_correlator_debug_tdata = correlator_2_tdata;
assign m_axis_correlator_debug_tvalid = correlator_2_tvalid;
reg [2 : 0] peak_detected; 
reg correlator_en;
reg [IN_DW-1:0] score [0 : 2];

PSS_correlator #(
    .IN_DW(IN_DW),
    .OUT_DW(OUT_DW),
    .TAP_DW(TAP_DW),
    .PSS_LEN(PSS_LEN),
    .PSS_LOCAL(PSS_LOCAL_0),
    .USE_TAP_FILE(USE_TAP_FILE),
    .TAP_FILE(TAP_FILE_0),
    .ALGO(ALGO)
)
correlator_0_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .s_axis_in_tdata(s_axis_in_tdata),
    .s_axis_in_tvalid(s_axis_in_tvalid && correlator_en),
    .C0_o(C0[0]),
    .C1_o(C1[0]),
    .m_axis_out_tdata(correlator_0_tdata),
    .m_axis_out_tvalid(correlator_0_tvalid)
);

PSS_correlator #(
    .IN_DW(IN_DW),
    .OUT_DW(OUT_DW),
    .TAP_DW(TAP_DW),
    .PSS_LEN(PSS_LEN),
    .PSS_LOCAL(PSS_LOCAL_1),
    .USE_TAP_FILE(USE_TAP_FILE),
    .TAP_FILE(TAP_FILE_1),
    .ALGO(ALGO)
)
correlator_1_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .s_axis_in_tdata(s_axis_in_tdata),
    .s_axis_in_tvalid(s_axis_in_tvalid && correlator_en),
    .C0_o(C0[1]),
    .C1_o(C1[1]),
    .m_axis_out_tdata(correlator_1_tdata),
    .m_axis_out_tvalid(correlator_1_tvalid)
);

PSS_correlator #(
    .IN_DW(IN_DW),
    .OUT_DW(OUT_DW),
    .TAP_DW(TAP_DW),
    .PSS_LEN(PSS_LEN),
    .PSS_LOCAL(PSS_LOCAL_2),
    .USE_TAP_FILE(USE_TAP_FILE),
    .TAP_FILE(TAP_FILE_2),
    .ALGO(ALGO)
)
correlator_2_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .s_axis_in_tdata(s_axis_in_tdata),
    .s_axis_in_tvalid(s_axis_in_tvalid && correlator_en),
    .C0_o(C0[2]),
    .C1_o(C1[2]),
    .m_axis_out_tdata(correlator_2_tdata),
    .m_axis_out_tvalid(correlator_2_tvalid),
    .taps_o(taps_2_o)
);

Peak_detector #(
    .IN_DW(OUT_DW),
    .WINDOW_LEN(WINDOW_LEN)
)
peak_detector_0_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .s_axis_in_tdata(correlator_0_tdata),
    .s_axis_in_tvalid(correlator_0_tvalid),
    .peak_detected_o(peak_detected[0]),
    .score_o(score[0])    
);

Peak_detector #(
    .IN_DW(OUT_DW),
    .WINDOW_LEN(WINDOW_LEN)
)
peak_detector_1_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .s_axis_in_tdata(correlator_1_tdata),
    .s_axis_in_tvalid(correlator_1_tvalid),
    .peak_detected_o(peak_detected[1]),
    .score_o(score[1])
);

Peak_detector #(
    .IN_DW(OUT_DW),
    .WINDOW_LEN(WINDOW_LEN)
)
peak_detector_2_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .s_axis_in_tdata(correlator_2_tdata),
    .s_axis_in_tvalid(correlator_2_tvalid),
    .peak_detected_o(peak_detected[2]),
    .score_o(score[2])    
);


reg [C_DW - 1 : 0] C0_in, C1_in;
reg CFO_calc_valid_in;
reg CFO_calc_valid_out;
reg [CFO_DW - 1 : 0] CFO_angle;
reg [DDS_DW - 1 : 0] CFO_DDS_inc;
CFO_calc #(
    .C_DW(C_DW),
    .CFO_DW(CFO_DW),
    .DDS_DW(DDS_DW)
)
CFO_calc_i(
    .clk_i(clk_i),
    .reset_ni(reset_ni),
    .C0_i(C0_in),
    .C1_i(C1_in),
    .valid_i(CFO_calc_valid_in),

    .CFO_angle_o(CFO_angle),
    .CFO_DDS_inc_o(CFO_DDS_inc),
    .valid_o(CFO_calc_valid_out)
);

localparam [1 : 0]  SEARCH = 0;
localparam [1 : 0]  FIND   = 1;
localparam [1 : 0]  PAUSE  = 2;
localparam SSB_INTERVAL = $rtoi(1920000 * 0.02);
localparam TRACK_TOLERANCE = 100;
localparam CORRELATOR_DELAY = 160;
reg [$clog2(SSB_INTERVAL + TRACK_TOLERANCE) - 1 : 0] sample_cnt;
reg peak_valid;

reg [1 : 0] CFO_state;
localparam [1 : 0] WAIT_FOR_PEAK = 0;
localparam [1 : 0] DISABLE_CFO_IN = 1;
localparam [1 : 0] WAIT_FOR_CFO = 2;

//-------------------------------------------------------------------------------
// FSM to control CFO_calc
// it is not sensitive to new incoming peaks while it waits for CFO_calc to finish
// this can cause a peak to be ignored if it follows close after another peak
// 
// TODO: signal a valid N_id_2 only of the calculated CFO is below a certain threshold,
// i.e. +- 100 Hz, if it is above, wait for next SSB with corrected CFO
reg N_id_2_valid;
always @(posedge clk_i) begin
    if (!reset_ni) begin
        CFO_state <= WAIT_FOR_PEAK;
        N_id_2_valid <= '0;
        CFO_angle_o <= '0;
        CFO_DDS_inc_o <= '0;
        CFO_valid_o <= '0;
    end else begin
        case (CFO_state)
            WAIT_FOR_PEAK : begin
                N_id_2_valid <= '0;
                CFO_valid_o <= '0;
                if (peak_valid) begin
                    C0_in <= C0[N_id_2_o];
                    C1_in <= C1[N_id_2_o];
                    CFO_calc_valid_in <= 1;
                    CFO_state <= DISABLE_CFO_IN;
                end
            end
            DISABLE_CFO_IN : begin
                CFO_calc_valid_in <= '0;
                CFO_state <= WAIT_FOR_CFO;
            end
            WAIT_FOR_CFO : begin
                if (CFO_calc_valid_out) begin
                    CFO_state <= WAIT_FOR_PEAK;
                    N_id_2_valid <= 1;
                    CFO_angle_o <= CFO_angle;
                    CFO_DDS_inc_o <= CFO_DDS_inc;
                    CFO_valid_o <= 1;
                end
            end
        endcase
    end
end

//-------------------------------------------------------------------------------
// FSM for detection of peaks
// mode can be controlled by mode_i when the USE_MODE parameter is 1
//
// In SEARCH mode a valid peak is detected if one and only one PSS correlator signals peak_detected.
// In FIND mode, a peak is detected same as in SEARCH mode, except that search is limited to a certain N_id_2
// in PAUSE mode, the PSS correlators are disabled
//
// If USE_MODE is 0, the FSM is permanently in SEARCH mode
wire [1 : 0] mode_select;
assign mode_select = USE_MODE ? mode_i : SEARCH;

always @(posedge clk_i) begin
    if (!reset_ni) begin
        N_id_2_o <= '0;
        peak_valid <= '0;
        correlator_en <= '0;
    end else begin
        case(mode_select)
            SEARCH : begin
                correlator_en <= 1;
                if ((peak_detected == 1) || (peak_detected == 2) || (peak_detected == 4)) begin
                    case (peak_detected)
                        0 : N_id_2_o <= 0;
                        2 : N_id_2_o <= 1;
                        4 : N_id_2_o <= 2;
                    endcase
                    peak_valid <= 1;
                end else begin
                    peak_valid <= 0;
                end
            end
            FIND : begin
                correlator_en <= 1;
                if (peak_detected[requested_N_id_2_i] && 
                    ((peak_detected == 1) || (peak_detected == 2) || (peak_detected == 4))) begin
                    N_id_2_o <= requested_N_id_2_i;
                    peak_valid <= 1;
                end else begin
                    peak_valid <= 0;
                end
            end
            PAUSE : begin
                correlator_en <= 0;
                peak_valid <= 0;
            end
        endcase
    end
end

assign N_id_2_valid_o = CFO_LIMIT ? N_id_2_valid : peak_valid;

endmodule