`timescale 1ns / 1ps

module tb_fp_to_int;

    // 1. 信号定义
    reg  [63:0] tb_fp_in;      // 输入：双精度浮点数
    wire [63:0] tb_int_out;    // 输出：64位整形 (Signed Long)

    // 2. 实例化待测模块 (DUT)
    fp_to_int uut (
        .fp_in      (tb_fp_in),
        .int_out    (tb_int_out)
    );

    // 3. 定义测试任务
    // 类似于参考代码中的 run_test，但针对组合逻辑进行了简化
    task run_test;
        input [63:0] fp_val;        // 输入浮点数
        input [63:0] expected_int;  // 预期整形值
        input [511:0] test_name;    // 测试名称
        
        begin
            // 赋值输入
            tb_fp_in = fp_val;
            
            // 等待组合逻辑稳定 (模拟传播延迟)
            #10; 

            // 结果检查
            if (tb_int_out === expected_int) begin
                $display("PASS: %-45s. In=%h, Got=%h (Dec:%0d)", 
                         test_name, fp_val, tb_int_out, $signed(tb_int_out));
            end else begin
                $display("FAIL: %-45s. Expected=%h, Got=%h", test_name, expected_int, tb_int_out);
                $display("      Expected Dec: %0d, Got Dec: %0d", $signed(expected_int), $signed(tb_int_out));
            end
            
            // 插入间隙
            #10;
        end
    endtask

    // 4. 测试主流程
    initial begin
        // 初始化
        tb_fp_in = 0;

        // 生成波形文件 (可选)
        $dumpfile("./vcd/tb_fp_to_int.vcd");
        $dumpvars(0, tb_fp_to_int);

        $display("================== Start Test fp_to_int (Round to Nearest Even) ==================");
        #10;

        // --- 1. 基础整数转换 ---
        // 1.0 -> 1
        run_test(64'h3FF0000000000000, 64'h0000000000000001, 
                 "Test 1: 1.0 -> 1");
        
        // -1.0 -> -1
        run_test(64'hBFF0000000000000, 64'hFFFFFFFFFFFFFFFF, 
                 "Test 2: -1.0 -> -1");

        // 0.0 -> 0
        run_test(64'h0000000000000000, 64'h0000000000000000, 
                 "Test 3: 0.0 -> 0");

        // --- 2. 正常舍入测试 (普通四舍五入) ---
        // 1.2 -> 1 (舍去)
        // Hex: 3FF3333333333333
        run_test(64'h3FF3333333333333, 64'h0000000000000001, 
                 "Test 4: 1.2 -> 1 (Round Down)");

        // 1.8 -> 2 (进位)
        // Hex: 3FFCCCCCCCCCCCCD
        run_test(64'h3FFCCCCCCCCCCCCD, 64'h0000000000000002, 
                 "Test 5: 1.8 -> 2 (Round Up)");

        // --- 3. 平衡舍入/银行家舍入 (Round to Nearest Even) ---
        // 规则：x.5 时，向最近的偶数舍入
        
        // 2.5 -> 2 (舍去，因为2是偶数)
        // Hex: 4004000000000000
        run_test(64'h4004000000000000, 64'h0000000000000002, 
                 "Test 6: 2.5 -> 2 (Tie-break to Even Down)");

        // 1.5 -> 2 (进位，因为2是偶数)
        // Hex: 3FF8000000000000
        run_test(64'h3FF8000000000000, 64'h0000000000000002, 
                 "Test 7: 1.5 -> 2 (Tie-break to Even Up)");
        
        // 3.5 -> 4 (进位，因为4是偶数)
        // Hex: 400C000000000000
        run_test(64'h400C000000000000, 64'h0000000000000004, 
                 "Test 8: 3.5 -> 4 (Tie-break to Even Up)");

        // -2.5 -> -2 (舍去，因为-2是偶数)
        // Hex: C004000000000000 -> Int: FFFFFFFFFFFFFFFE
        run_test(64'hC004000000000000, 64'hFFFFFFFFFFFFFFFE, 
                 "Test 9: -2.5 -> -2 (Negative Tie-break)");

        // --- 4. 边界与大数测试 ---
        
        // 小数测试：0.4 -> 0
        // Hex: 3FD999999999999A
        run_test(64'h3FD999999999999A, 64'h0000000000000000, 
                 "Test 10: 0.4 -> 0 (Small Number)");

        // 大数测试：2^60
        // 2^60 FP: 43B0000000000000
        // 2^60 Int: 1000000000000000
        run_test(64'h43B0000000000000, 64'h1000000000000000, 
                 "Test 11: 2^60 (Large Number)");

        // 负大数测试：-2^60
        // -2^60 FP: C3B0000000000000
        // -2^60 Int: F000000000000000
        run_test(64'hC3B0000000000000, 64'hF000000000000000, 
                 "Test 12: -2^60 (Negative Large Number)");

        // --- 5. 异常值 (可选，视具体实现而定) ---
        // 注意：FP转Int对于 NaN 和 Inf 的标准行为在硬件上通常是定义为
        // 返回整数的最大值或最小值，这里假设 NaN 返回 0 以作演示，实际需根据设计调整。
        // 如果你的设计对 NaN 输出全0：
        // run_test(64'h7FF8000000000001, 64'h0000000000000000, "Test 13: NaN -> 0 (Assumption)");

        $display("================== Stop Test fp_to_int ==================");
        #20;
        $finish;
    end

endmodule
