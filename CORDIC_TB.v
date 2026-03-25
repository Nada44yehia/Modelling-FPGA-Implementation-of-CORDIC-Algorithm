`timescale 1ns/1ps

module CORDIC_TB;

    // --------------------------------------------------
    // Parameters
    // --------------------------------------------------
    parameter WIDTH = 16;        // Width of x, y, sine, and cosine
    parameter NUM_ITER = 15;      // Number of CORDIC iterations
    localparam TOL   = 4;       // tolerance in LSBs
    localparam CLK_PERIOD = 10;

    // --------------------------------------------------
    // DUT signals
    // --------------------------------------------------
    reg                    clk;
    reg                    rst;
    reg                    start;
    reg signed [WIDTH-1:0] x_start;
    reg signed [WIDTH-1:0] y_start;
    reg signed [31:0]      angle;
    wire signed [WIDTH-1:0] cosine;
    wire signed [WIDTH-1:0] sine;
    wire                   done;

    // --------------------------------------------------
    // Instantiate DUT (adjust module name/params if needed)
    // --------------------------------------------------
    CORDIC #(
        .WIDTH(WIDTH),
        .ITER (NUM_ITER)
    ) dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .x_start(x_start),
        .y_start(y_start),
        .angle(angle),
        .cosine(cosine),
        .sine(sine),
        .done(done)
    );

    // --------------------------------------------------
    // Clock
    // --------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // --------------------------------------------------
    // Test variables
    // --------------------------------------------------
    integer fd, r;
    integer line_num;
    integer pass_count, fail_count;
    reg signed [31:0] angle_ref;
    reg signed [WIDTH-1:0] cos_ref, sin_ref;

    // small timeout helper
    task wait_for_done_with_timeout(input integer timeout_cycles);
        integer c;
        begin
            c = 0;
            while (!done && c < timeout_cycles) begin
                @(posedge clk);
                c = c + 1;
            end
            if (!done) begin
                $display("ERROR: timeout waiting for done (after %0d cycles)", timeout_cycles);
                $finish;
            end
        end
    endtask

    // --------------------------------------------------
    // Main test
    // --------------------------------------------------
    initial begin
        // init
        line_num = 0;
        pass_count = 0;
        fail_count = 0;

        // initial signals
        rst = 1;
        start = 0;
        x_start = 16'sd9950;  // K=0.6073*2^14
        y_start = 16'sd0;
        angle = 0;

        // small reset
        #20;
        rst = 0;

        // open file
        fd = $fopen("cordic_vectors.txt", "r");
        if (fd == 0) begin
            $display("ERROR: Could not open cordic_vectors.txt");
            $finish;
        end

        $display("\n--- Starting CORDIC Verification ---\n");

        // read & apply vectors
        while (!$feof(fd)) begin
            r = $fscanf(fd, "%d %d %d\n", angle_ref, cos_ref, sin_ref);
            if (r != 3) begin
                $display("WARNING: malformed line %0d (ignored)", line_num+1);
            end else begin
                line_num = line_num + 1;

                // ---- ensure DUT is idle before starting new vector ----
                // Wait one posedge for stable sampling, then ensure done==0
                @(posedge clk);
                while (done) @(posedge clk);

                // ---- apply angle (stable before start) ----
                angle = angle_ref;

                // small settle cycle (optional but safe)
                @(posedge clk);

                // ---- pulse start for exactly one clock ----
                start = 1;
                @(posedge clk); // start seen by DUT on this rising edge
                start = 0;

                // ---- wait for DUT to finish (with timeout) ----
                wait_for_done_with_timeout(NUM_ITER + 50);

                // (optionally) wait one extra clock to let outputs settle
                @(posedge clk);

                // ---- compare with tolerance ----
                if ((cosine > cos_ref + TOL) || (cosine < cos_ref - TOL)) begin
                    $display("FAIL [line %0d]: angle=%0d | cos=%0d (ref=%0d)", 
                             line_num, angle_ref, cosine, cos_ref);
                    fail_count = fail_count + 1;
                end else begin
                    $display("PASS [line %0d]: angle=%0d | cos=%0d (ref=%0d)", 
                             line_num, angle_ref, cosine, cos_ref);
                    pass_count = pass_count + 1;
                end

                if ((sine > sin_ref + TOL) || (sine < sin_ref - TOL)) begin
                    $display("FAIL [line %0d]: angle=%0d | sin=%0d (ref=%0d)", 
                             line_num, angle_ref, sine, sin_ref);
                    fail_count = fail_count + 1;
                end else begin
                    $display("PASS [line %0d]: angle=%0d | sin=%0d (ref=%0d)", 
                             line_num, angle_ref, sine, sin_ref);
                    pass_count = pass_count + 1;
                end

                // small gap before next vector (optional)
                @(posedge clk);
            end
        end

        $fclose(fd);

        // summary
        $display("\n--- Verification Summary ---");
        $display("Total vectors = %0d", line_num);
        $display("Passed (checks) = %0d", pass_count);
        $display("Failed (checks) = %0d", fail_count);
        $display("---------------------------------\n");

        $finish;
    end

endmodule

