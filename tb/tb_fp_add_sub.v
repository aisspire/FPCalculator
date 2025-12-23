`timescale 1ns / 1ps

module tb_fp_add_sub;

    // 1. 信号定义 (保持与 tb_fp_div 风格一致)
    reg         tb_clk;
    reg         tb_rst_n;      // 复位信号 (保留形式，即使纯组合逻辑可能不用)
    reg  [63:0] tb_fp_a;       // 操作数 A
    reg  [63:0] tb_fp_b;       // 操作数 B
    reg         tb_is_sub;     // 加减控制位 (Add=0, Sub=1)
    
    wire [63:0] tb_fp_out;     // 结果输出

    // 2. 实例化待测模块 (DUT)
    fp_add_sub uut (
        .fp_a_in    (tb_fp_a),
        .fp_b_in    (tb_fp_b),
        .is_sub     (tb_is_sub),
        .fp_res_out (tb_fp_out)
    );

    // 3. 时钟生成 (10ns 周期 -> 100MHz，保持一致性)
    always #5 tb_clk = ~tb_clk;

    // 4. 定义测试任务
    task run_test;
        input [63:0] a;
        input [63:0] b;
        input        is_sub;    // 新增：加减控制
        input [63:0] expected;
        input [511:0] test_name;
        
        begin
            // 同步驱动输入
            @(posedge tb_clk);
            tb_fp_a = a;
            tb_fp_b = b;
            tb_is_sub = is_sub;
            
            // 等待结果稳定
            // 原除法用例是等待 done 信号，这里加减法如果是组合逻辑，
            // 我们等待固定的时钟周期以确保稳定 (替代原文件中的 #10)
            repeat(2) @(posedge tb_clk);

            // 结果检查
            // 使用 === 进行严格比对 (包含 X/Z 态检查)
            if (tb_fp_out === expected) begin
                $display("PASS: %-45s. Got=%h", test_name, tb_fp_out);
            end else begin
                $display("FAIL: %-45s. Expected=%h, Got=%h", test_name, expected, tb_fp_out);
            end
            
            // 插入间隙
            @(posedge tb_clk);
        end
    endtask

    // 5. 测试主流程
    initial begin
        // 初始化
        tb_clk = 0;
        tb_rst_n = 0;
        tb_fp_a = 0;
        tb_fp_b = 0;
        tb_is_sub = 0;

        // 生成波形文件
        $dumpfile("./vcd/tb_fp_add_sub.vcd");
        $dumpvars(0, tb_fp_add_sub);

        // 释放复位
        #20;
        @(posedge tb_clk);
        tb_rst_n = 1;
        @(posedge tb_clk);
        
        $display("================== Start Test fp_add_sub ==================");

        // --- 测试用例 #1: 简单加法 ---
        // 1.0 + 2.0 = 3.0
        run_test(64'h3FF0000000000000, 64'h4000000000000000, 1'b0, 64'h4008000000000000, 
                 "Test 1: 1.0 + 2.0 (Basic Add)");

        // --- 测试用例 #2: 简单减法 ---
        // 3.0 - 1.5 = 1.5
        run_test(64'h4008000000000000, 64'h3FF8000000000000, 1'b1, 64'h3FF8000000000000, 
                 "Test 2: 3.0 - 1.5 (Basic Sub)");

        // --- 测试用例 #3: 结果为负数 ---
        // 1.5 - 3.0 = -1.5
        run_test(64'h3FF8000000000000, 64'h4008000000000000, 1'b1, 64'hBFF8000000000000, 
                 "Test 3: 1.5 - 3.0 (Result Negative)");

        // --- 测试用例 #4: 两个负数相加 ---
        // -2.0 + (-1.0) = -3.0
        run_test(64'hC000000000000000, 64'hBFF0000000000000, 1'b0, 64'hC008000000000000, 
                 "Test 4: -2.0 + (-1.0) (Neg + Neg)");

        // --- 测试用例 #5: 减去一个负数 (等效于加法) ---
        // -1.0 - (-2.0) = 1.0
        run_test(64'hBFF0000000000000, 64'hC000000000000000, 1'b1, 64'h3FF0000000000000, 
                 "Test 5: -1.0 - (-2.0) (Sub Neg)");

        // --- 测试用例 #6: 零的测试 ---
        // 5.0 + (-5.0) = +0.0
        run_test(64'h4014000000000000, 64'hC014000000000000, 1'b0, 64'h0000000000000000, 
                 "Test 6: 5.0 + (-5.0) (Result Zero)");

        // --- 测试用例 #7: 无穷大测试 ---
        // Inf + 1.0 = Inf
        run_test(64'h7FF0000000000000, 64'h3FF0000000000000, 1'b0, 64'h7FF0000000000000, 
                 "Test 7: Inf + 1.0 (Inf Propagation)");

        // --- 测试用例 #8: 无穷大减无穷大 ---
        // Inf - Inf = NaN (假设 NaN 格式为 7FF8000000000000)
        run_test(64'h7FF0000000000000, 64'h7FF0000000000000, 1'b1, 64'h7FF8000000000000, 
                 "Test 8: Inf - Inf (Invalid -> NaN)");

        // --- 测试用例 #9: NaN的传播 ---
        // NaN + 1.0 = NaN
        run_test(64'h7FF8000000000000, 64'h3FF0000000000000, 1'b0, 64'h7FF8000000000000, 
                 "Test 9: NaN + 1.0 (NaN Propagation)");

        // --- 测试用例 #10: 非规格化数 (Denormalized) ---
        // Min_Denorm + Min_Denorm
        run_test(64'h0000000000000001, 64'h0000000000000001, 1'b0, 64'h0000000000000002, 
                 "Test 10: Denorm + Denorm");
        
        // --- 测试用例 #11: 舍入测试 (Ties to Even) ---
        // 1.0 + 2^(-52) + 2^(-53) -> Round Up
        run_test(64'h3FF0000000000001, 64'h3CA0000000000000, 1'b0, 64'h3FF0000000000002, 
                 "Test 11: Rounding (Ties to Even)");

        $display("================== Stop Test fp_add_sub ==================");
        #20;
        $finish;
    end

endmodule
