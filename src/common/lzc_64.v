// src/common/lzc_64.v
// 功能：计算64位数据的前导零数量 (可综合版本)

`default_nettype none

module lzc_64 (
    input  wire [63:0] data_in,
    output reg  [6:0]  count
);
    // 使用层次化的if-else结构，对综合器友好
    always @(*) begin
        if (data_in == 0) begin
            count = 64;
        end else if (data_in[63:32] != 0) begin
            // 在高32位中查找
            if (data_in[63:48] != 0) begin // 高16位
                if (data_in[63:56] != 0) begin // 高8位
                    count = lzc_8(data_in[63:56]);
                end else begin // 低8位
                    count = 8 + lzc_8(data_in[55:48]);
                end
            end else begin // 低16位
                if (data_in[47:40] != 0) begin
                    count = 16 + lzc_8(data_in[47:40]);
                end else begin
                    count = 24 + lzc_8(data_in[39:32]);
                end
            end
        end else begin
            // 在低32位中查找
            if (data_in[31:16] != 0) begin // 高16位
                if (data_in[31:24] != 0) begin
                    count = 32 + lzc_8(data_in[31:24]);
                end else begin
                    count = 40 + lzc_8(data_in[23:16]);
                end
            end else begin // 低16位
                if (data_in[15:8] != 0) begin
                    count = 48 + lzc_8(data_in[15:8]);
                end else begin
                    count = 56 + lzc_8(data_in[7:0]);
                end
            end
        end
    end

    // 8位前导零计数器函数
    function [3:0] lzc_8 (input [7:0] d);
        if      (d[7]) lzc_8 = 0;
        else if (d[6]) lzc_8 = 1;
        else if (d[5]) lzc_8 = 2;
        else if (d[4]) lzc_8 = 3;
        else if (d[3]) lzc_8 = 4;
        else if (d[2]) lzc_8 = 5;
        else if (d[1]) lzc_8 = 6;
        else if (d[0]) lzc_8 = 7;
        else           lzc_8 = 8;
    endfunction

endmodule
`default_nettype wire
