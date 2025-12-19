// 文件名: tb/tb_fp_add_sub.v
// 描述: fp_add_sub 模块的测试平台

`timescale 1ns / 1ps // 定义仿真时间单位和精度

module tb_fp_add_sub;

    // 1. 定义输入和输出信号
    // 输入信号应为 reg 类型，因为我们需要在 initial 块中驱动它们
    reg  [63:0] tb_fp_a_in;
    reg  [63:0] tb_fp_b_in;
    reg         tb_is_sub;

    // 输出信号应为 wire 类型，用来连接到 DUT 的输出
    wire [63:0] tb_fp_res_out;

    // 2. 实例化待测模块 (DUT)
    // uut 是 "Unit Under Test" 的常用缩写
    fp_add_sub uut (
        .fp_a_in    (tb_fp_a_in),   // 将 testbench 的 reg 连接到 DUT 的 input
        .fp_b_in    (tb_fp_b_in),
        .is_sub     (tb_is_sub),
        .fp_res_out (tb_fp_res_out)  // 将 DUT 的 output 连接到 testbench 的 wire
    );

    // 3. 编写测试激励
    initial begin
        // 打开波形文件，用于 GTKWave 分析
        $dumpfile("tb_fp_add_sub.vcd");
        // 指定要记录波形的信号，0表示记录 uut 模块下的所有信号
        $dumpvars(0, uut);

        $display("================== 开始测试 fp_add_sub ==================");

        // --- 测试用例 #1: 简单加法 ---
        // 1.0 + 2.0 = 3.0
        // A = 1.0 -> 0x3FF0000000000000
        // B = 2.0 -> 0x4000000000000000
        // Res = 3.0 -> 0x4008000000000000
        tb_fp_a_in = 64'h3FF0000000000000;
        tb_fp_b_in = 64'h4000000000000000;
        tb_is_sub  = 1'b0; // 加法
        #10; // 等待 10ns，让电路稳定并产生结果
        $display("Test 1: 1.0 + 2.0. Expected=0x4008..., Got=%h", tb_fp_res_out);

        // --- 测试用例 #2: 简单减法 ---
        // 3.0 - 1.5 = 1.5
        // A = 3.0 -> 0x4008000000000000
        // B = 1.5 -> 0x3FF8000000000000
        // Res = 1.5 -> 0x3FF8000000000000
        tb_fp_a_in = 64'h4008000000000000;
        tb_fp_b_in = 64'h3FF8000000000000;
        tb_is_sub  = 1'b1; // 减法
        #10;
        $display("Test 2: 3.0 - 1.5. Expected=0x3FF8..., Got=%h", tb_fp_res_out);

        // --- 测试用例 #3: 结果为负数 ---
        // 1.5 - 3.0 = -1.5
        // A = 1.5 -> 0x3FF8000000000000
        // B = 3.0 -> 0x4008000000000000
        // Res = -1.5 -> 0xBFF8000000000000
        tb_fp_a_in = 64'h3FF8000000000000;
        tb_fp_b_in = 64'h4008000000000000;
        tb_is_sub  = 1'b1; // 减法
        #10;
        $display("Test 3: 1.5 - 3.0. Expected=0xBFF8..., Got=%h", tb_fp_res_out);

        // --- 测试用例 #4: 两个负数相加 ---
        // -2.0 + (-1.0) = -3.0
        // A = -2.0 -> 0xC000000000000000
        // B = -1.0 -> 0xBFF0000000000000
        // Res = -3.0 -> 0xC008000000000000
        tb_fp_a_in = 64'hC000000000000000;
        tb_fp_b_in = 64'hBFF0000000000000;
        tb_is_sub  = 1'b0; // 加法
        #10;
        $display("Test 4: -2.0 + (-1.0). Expected=0xC008..., Got=%h", tb_fp_res_out);

        // --- 测试用例 #5: 减去一个负数 (等效于加法) ---
        // -1.0 - (-2.0) = 1.0
        // A = -1.0 -> 0xBFF0000000000000
        // B = -2.0 -> 0xC000000000000000
        // Res = 1.0 -> 0x3FF0000000000000
        tb_fp_a_in = 64'hBFF0000000000000;
        tb_fp_b_in = 64'hC000000000000000;
        tb_is_sub  = 1'b1; // 减法
        #10;
        $display("Test 5: -1.0 - (-2.0). Expected=0x3FF0..., Got=%h", tb_fp_res_out);

        // --- 测试用例 #6: 零的测试 ---
        // 5.0 + (-5.0) = +0.0 (根据IEEE754，在非四舍五入模式下，符号位取决于最后一次有效操作，加法通常为+0)
        // A = 5.0  -> 0x4014000000000000
        // B = -5.0 -> 0xC014000000000000
        // Res = +0.0 -> 0x0000000000000000
        tb_fp_a_in = 64'h4014000000000000;
        tb_fp_b_in = 64'hC014000000000000;
        tb_is_sub  = 1'b0; // 加法
        #10;
        $display("Test 6: 5.0 + (-5.0). Expected=0x0..., Got=%h", tb_fp_res_out);

        // --- 测试用例 #7: 无穷大测试 ---
        // Infinity + 1.0 = Infinity
        // A = Infinity -> 0x7FF0000000000000
        // B = 1.0      -> 0x3FF0000000000000
        // Res = Infinity -> 0x7FF0000000000000
        tb_fp_a_in = 64'h7FF0000000000000;
        tb_fp_b_in = 64'h3FF0000000000000;
        tb_is_sub  = 1'b0; // 加法
        #10;
        $display("Test 7: Inf + 1.0. Expected=0x7FF0..., Got=%h", tb_fp_res_out);

        // --- 测试用例 #8: 无穷大减无穷大 ---
        // Infinity - Infinity = NaN (Not a Number)
        // A = Infinity -> 0x7FF0000000000000
        // B = Infinity -> 0x7FF0000000000000
        // Res = NaN -> 0x7FF8000000000001 (或其它任何指数全1,尾数非0的数)
        tb_fp_a_in = 64'h7FF0000000000000;
        tb_fp_b_in = 64'h7FF0000000000000;
        tb_is_sub  = 1'b1; // 减法
        #10;
        $display("Test 8: Inf - Inf. Expected=NaN (e.g. 0x7FF8...), Got=%h", tb_fp_res_out);

        // --- 测试用例 #9: NaN的传播 ---
        // NaN + 1.0 = NaN
        // A = NaN      -> 0x7FF8000000000000
        // B = 1.0      -> 0x3FF0000000000000
        // Res = NaN -> 0x7FF8000000000000
        tb_fp_a_in = 64'h7FF8000000000000;
        tb_fp_b_in = 64'h3FF0000000000000;
        tb_is_sub  = 1'b0; // 加法
        #10;
        $display("Test 9: NaN + 1.0. Expected=NaN (e.g. 0x7FF8...), Got=%h", tb_fp_res_out);

        // --- 测试用例 #10: 非规格化数 (Denormalized Number) ---
        // 这是一个非常小的数 + 另一个非常小的数
        // A = 2^(-1074) (最小的正非规格化数) -> 0x0000000000000001
        // B = 2^(-1074) (最小的正非规格化数) -> 0x0000000000000001
        // Res = 2 * 2^(-1074) = 2^(-1073) -> 0x0000000000000002
        tb_fp_a_in = 64'h0000000000000001;
        tb_fp_b_in = 64'h0000000000000001;
        tb_is_sub  = 1'b0; // 加法
        #10;
        $display("Test 10: Denorm + Denorm. Expected=0x0...2, Got=%h", tb_fp_res_out);
        
        // --- 测试用例 #11: 舍入测试 (平衡型舍入, Round to nearest, ties to even) ---
        // 考虑一个需要舍入的例子，结果的LSB为1，且后面的位是100... (正好一半)
        // A = 1.0 + 2^(-52) -> 0x3FF0000000000001
        // B = 2^(-53)       -> 0x3CA0000000000000
        // A+B = 1.0 + 2^(-52) + 2^(-53) = 1.0 + 1.5 * 2^(-52)
        // 尾数会是 1.0...011, 需要舍入。因为前一位是1（奇数），所以向上舍入
        // 结果: 1.0 + 2 * 2^(-52) = 1.0 + 2^(-51) -> 0x3FF0000000000002
        tb_fp_a_in = 64'h3FF0000000000001;
        tb_fp_b_in = 64'h3CA0000000000000;
        tb_is_sub = 1'b0; // 加法
        #10;
        $display("Test 11: Rounding (ties to even, odd case). Expected=0x3FF...2, Got=%h", tb_fp_res_out);

        $display("================== 结束测试 fp_add_sub ==================");
        #20; // 再多等待一会儿，确保所有打印信息都显示出来
        $finish; // 结束仿真
    end

endmodule
