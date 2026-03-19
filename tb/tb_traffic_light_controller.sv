`timescale 1ns/1ps

module tb_traffic_light_controller;

    // -------------------------------------------------
    // Simulation parameters
    // -------------------------------------------------
    localparam int CLK_PERIOD_NS = 10;
    localparam int CLK_FREQ_HZ   = 4;  
    // yellow = 3 * 4 = 12 cycles
    // green  = 5 * 4 = 20 cycles

    localparam int YELLOW_CYCLES = 3 * CLK_FREQ_HZ;
    localparam int GREEN_CYCLES  = 5 * CLK_FREQ_HZ;

    // -------------------------------------------------
    // DUT signals
    // -------------------------------------------------
    logic clk;
    logic rst_n;
    logic sensor;

    logic hw_red;
    logic hw_yellow;
    logic hw_green;

    logic city_red;
    logic city_yellow;
    logic city_green;

    // -------------------------------------------------
    // DUT
    // -------------------------------------------------
    traffic_light_controller #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ)
    ) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .sensor      (sensor),
        .hw_red      (hw_red),
        .hw_yellow   (hw_yellow),
        .hw_green    (hw_green),
        .city_red    (city_red),
        .city_yellow (city_yellow),
        .city_green  (city_green)
    );

    // -------------------------------------------------
    // Clock generation
    // -------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    // -------------------------------------------------
    // Utility: wait N clock cycles
    // -------------------------------------------------
    task automatic wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    // -------------------------------------------------
    // Utility: print current lights
    // -------------------------------------------------
    task automatic show_lights(input string tag);
        $display("[%0t] %s | sensor=%0b | HW(RYG)=%0b%0b%0b | CITY(RYG)=%0b%0b%0b",
                 $time, tag, sensor,
                 hw_red, hw_yellow, hw_green,
                 city_red, city_yellow, city_green);
    endtask

    // -------------------------------------------------
    // Check exactly one light active per road
    // -------------------------------------------------
    task automatic check_onehot_per_road(input string where);
        if ((hw_red + hw_yellow + hw_green) != 1) begin
            $error("[%0t] %s : Highway lights invalid. hw_red=%0b hw_yellow=%0b hw_green=%0b",
                   $time, where, hw_red, hw_yellow, hw_green);
            $fatal;
        end

        if ((city_red + city_yellow + city_green) != 1) begin
            $error("[%0t] %s : City lights invalid. city_red=%0b city_yellow=%0b city_green=%0b",
                   $time, where, city_red, city_yellow, city_green);
            $fatal;
        end
    endtask

    // -------------------------------------------------
    // Check expected light combination
    // -------------------------------------------------
    task automatic expect_lights(
        input logic exp_hw_red,
        input logic exp_hw_yellow,
        input logic exp_hw_green,
        input logic exp_city_red,
        input logic exp_city_yellow,
        input logic exp_city_green,
        input string where
    );
        @(posedge clk);
        #1;
        check_onehot_per_road(where);

        if ({hw_red, hw_yellow, hw_green, city_red, city_yellow, city_green} !==
            {exp_hw_red, exp_hw_yellow, exp_hw_green, exp_city_red, exp_city_yellow, exp_city_green}) begin
            $error("[%0t] %s : Unexpected lights. Got HW=%0b%0b%0b CITY=%0b%0b%0b",
                   $time, where,
                   hw_red, hw_yellow, hw_green,
                   city_red, city_yellow, city_green);
            $fatal;
        end
    endtask

    // -------------------------------------------------
    // Check state duration in cycles
    // Samples current outputs for exactly n cycles
    // -------------------------------------------------
    task automatic expect_same_lights_for_cycles(
        input logic exp_hw_red,
        input logic exp_hw_yellow,
        input logic exp_hw_green,
        input logic exp_city_red,
        input logic exp_city_yellow,
        input logic exp_city_green,
        input int n,
        input string where
    );
        for (int i = 0; i < n; i++) begin
            expect_lights(exp_hw_red, exp_hw_yellow, exp_hw_green,
                          exp_city_red, exp_city_yellow, exp_city_green,
                          $sformatf("%s cycle %0d/%0d", where, i+1, n));
        end
    endtask

    // -------------------------------------------------
    // Scenario 1:
    // reset -> idle -> sensor request -> full cycle
    // -------------------------------------------------
    task automatic test_single_request;
        $display("\n=== TEST 1: single city request ===");

        sensor = 0;
        rst_n  = 0;
        wait_cycles(3);
        rst_n  = 1;

        // After reset: HW green, CITY red
        expect_lights(0,0,1, 1,0,0, "After reset, idle state");

        // Stay idle when no sensor
        wait_cycles(3);
        expect_lights(0,0,1, 1,0,0, "Still idle with no sensor");

        // Raise sensor
        sensor = 1;

        // Highway yellow for 3 seconds
        expect_same_lights_for_cycles(0,1,0, 1,0,0, YELLOW_CYCLES, "HW_YELLOW");

        // City green for 5 seconds
        expect_same_lights_for_cycles(1,0,0, 0,0,1, GREEN_CYCLES, "CITY_GREEN");

        // City yellow for 3 seconds
        expect_same_lights_for_cycles(1,0,0, 0,1,0, YELLOW_CYCLES, "CITY_YELLOW");

        // Highway green hold for at least 5 seconds
        expect_same_lights_for_cycles(0,0,1, 1,0,0, GREEN_CYCLES, "HW_GREEN_HOLD minimum");

        $display("TEST 1 PASSED");
    endtask

    // -------------------------------------------------
    // Scenario 2:
    // sensor drops during city phase, but city yellow still happens
    // -------------------------------------------------
    task automatic test_sensor_drop_during_city_phase;
        $display("\n=== TEST 2: sensor drops during city service ===");

        // Start from current state after previous test
        sensor = 1;

        // trigger next request after hold is over
        expect_same_lights_for_cycles(0,1,0, 1,0,0, YELLOW_CYCLES, "HW_YELLOW second cycle");

        // Enter city green
        for (int i = 0; i < GREEN_CYCLES; i++) begin
            if (i == 2)
                sensor = 0; // drop sensor during city green
            expect_lights(1,0,0, 0,0,1, $sformatf("CITY_GREEN with sensor drop cycle %0d", i+1));
        end

        // Must still go to city yellow regardless of sensor
        expect_same_lights_for_cycles(1,0,0, 0,1,0, YELLOW_CYCLES, "CITY_YELLOW despite sensor=0");

        // Return to highway hold
        expect_same_lights_for_cycles(0,0,1, 1,0,0, GREEN_CYCLES, "HW_GREEN_HOLD after sensor drop");

        $display("TEST 2 PASSED");
    endtask

    // -------------------------------------------------
    // Scenario 3:
    // sensor remains high continuously -> repeated cycles
    // but only after 5-second highway hold
    // -------------------------------------------------
    task automatic test_continuous_sensor;
        $display("\n=== TEST 3: continuous sensor ===");

        sensor = 1;

        // After hold expires, must start another cycle
        expect_same_lights_for_cycles(0,1,0, 1,0,0, YELLOW_CYCLES, "HW_YELLOW repeated");
        expect_same_lights_for_cycles(1,0,0, 0,0,1, GREEN_CYCLES, "CITY_GREEN repeated");
        expect_same_lights_for_cycles(1,0,0, 0,1,0, YELLOW_CYCLES, "CITY_YELLOW repeated");
        expect_same_lights_for_cycles(0,0,1, 1,0,0, GREEN_CYCLES, "HW_GREEN_HOLD repeated minimum");

        $display("TEST 3 PASSED");
    endtask

    // -------------------------------------------------
    // Assertions: sanity checks every cycle
    // -------------------------------------------------
    always @(posedge clk) begin
        if (rst_n) begin
            check_onehot_per_road("continuous assertion");

            // Never allow both roads green together
            if (hw_green && city_green) begin
                $error("[%0t] Illegal condition: both roads GREEN", $time);
                $fatal;
            end

            // Never allow both roads yellow together
            if (hw_yellow && city_yellow) begin
                $error("[%0t] Illegal condition: both roads YELLOW", $time);
                $fatal;
            end
        end
    end

    // -------------------------------------------------
    // Main test sequence
    // -------------------------------------------------
    initial begin
        $display("Starting traffic light controller testbench...");
        sensor = 0;
        rst_n  = 0;

        test_single_request();
        test_sensor_drop_during_city_phase();
        test_continuous_sensor();

        $display("\nALL TESTS PASSED");
        $finish;
    end

endmodule