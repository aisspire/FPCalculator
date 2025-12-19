// src/common/alignment_shifter.v
// 功能：用于浮点加法对阶的右移位器，同时生成 G, R, S 位

`default_nettype none

module alignment_shifter (
    input  wire [52:0] mant_in,       // 需要移位的53位尾数
    input  wire [5:0]  shift_amount,  // 需要右移的位数 (0-63)

    output wire [52:0] mant_out,      // 移位后的53位尾数
    output wire        g_out,         // Guard bit (保护位)
    output wire        r_out,         // Round bit (舍入位)
    output wire        s_out          // Sticky bit (粘滞位)
);

    // 定义一个足够宽的临时变量，以防止移位时丢失信息
    // 宽度 = 尾数宽度 + 最大移位宽度 = 53 + 64 = 117
    localparam TEMP_WIDTH = 53 + 64;
    wire [TEMP_WIDTH-1:0] extended_mant;
    wire [TEMP_WIDTH-1:0] shifted_mant;

    // 将输入尾数扩展，低位补零
    // {mant_in, 64'b0}
    assign extended_mant = {mant_in, {64{1'b0}}};

    // 执行右移操作
    assign shifted_mant = extended_mant >> shift_amount;

    // 从移位结果中提取所需部分
    // mant_out 是结果的高53位
    assign mant_out = shifted_mant[TEMP_WIDTH-1 -: 53];

    // g, r, s 位是移位后，恰好在 mant_out 最低位之后的三位信息
    // Guard bit 是移出部分的第一位
    assign g_out = shifted_mant[63];

    // Round bit 是移出部分的第二位
    assign r_out = shifted_mant[62];

    // Sticky bit 是 Round bit 之后所有位的逻辑或
    assign s_out = |(shifted_mant[61:0]);

endmodule

`default_nettype wire
