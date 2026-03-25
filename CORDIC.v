module CORDIC #( 
    parameter WIDTH = 16,          // Q2.14 fixed-point width
    parameter ITER = 15            // Iterations
)(
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,
    input  wire signed [WIDTH-1:0] x_start, // usually 0.6073*2^F
    input  wire signed [WIDTH-1:0] y_start, // usually 0
    input  wire signed [31:0]      angle,   // Q12.20 fixed-point angle
    output reg  signed [WIDTH-1:0] cosine,
    output reg  signed [WIDTH-1:0] sine,
    output reg                    done
);

    // ---------- Constants ----------
    localparam signed [31:0] TWO_PI     = 32'sd6588397; //2*pi*2^20
    localparam signed [31:0] PI         = 32'sd3294199; //pi*2^20
    localparam signed [31:0] HALFPI     = 32'sd1647099;//pi/2*2^20
   // ---------- atan lookup table (Q3.29) ---------- 
   reg signed [31:0] atan_table [0:ITER-1]; 
   initial $readmemh("atan_table_verilog.txt", atan_table);
    // ---------- angle array ----------
    reg signed [WIDTH-1:0] x, y;
    reg signed [31:0] z;
    reg [$clog2(ITER):0] iter; // iteration counter
  
    reg busy ,valid,load;
    reg flip_x, flip_y;

    // Use signed array for angles
   reg signed [31:0] a_mod ;
   reg signed [31:0] a_tmp ; 
    
// ---------- angle wrapping ----------
    reg [2:0] current_state;
    reg [2:0] next_state;
    localparam IDLE = 3'd0,
               CHECK  = 3'd1,
               ADD  = 3'd2,
               SUB=3'd3,
               DONE = 3'd4;

    // Sequential state register
    always @(posedge clk or posedge rst) begin
        if (rst) begin
             current_state <= IDLE;
            a_mod      <= 0;
        end else begin
              current_state <= next_state;
            if (current_state == IDLE && start)
                a_mod  <= angle;   // load input
            else if (current_state == SUB)
                a_mod<= a_mod - TWO_PI;
            else if (current_state == ADD)
                a_mod <= a_mod + TWO_PI;
        end
    end
   // FSM next-state logic
    always@(*) begin
        next_state = IDLE ;
        valid       = 1'b0;
        case (current_state)
            IDLE:  if (start) next_state = CHECK;
            CHECK: if (a_mod >= TWO_PI) next_state = SUB;
                   else if (a_mod < 0)      next_state = ADD;
                   else                   next_state = DONE;
            SUB:   next_state = CHECK;
            ADD:   next_state = CHECK;
            DONE:  begin
                      valid       = 1'b1;
                    next_state = IDLE;
                    end
                  
          default: begin
       next_state = IDLE ;
       valid       = 1'b0;
       end
     endcase
    end
      

          


    // ---------- Sequential ----------
    always @(posedge clk or posedge rst) begin
        if(rst) begin
            x       <= 0;
            y       <= 0;
            z       <= 0;
            iter    <= 0;
            cosine  <= 0;
            sine    <= 0;
            done    <= 0;
            busy    <= 0;
            flip_x  <= 0;
            flip_y  <= 0;
            load <= 0;
            a_tmp<=0;
        end else begin
              // Load initial vector and angle                  
                    x <= x_start;
                    y <= y_start;
                   if(load) begin
                    z <= a_tmp;
                    busy <= 1;
                    load <= 0;
                    end

            if(valid) begin
                    // ----- Quadrant detection -----
                    if(a_mod <= HALFPI) begin
                        a_tmp<=a_mod;
                        flip_x <= 0;
                        flip_y <= 0;
                    end else if(a_mod <=PI) begin
                         a_tmp<=PI-a_mod;
                        flip_x <= 1;
                        flip_y <= 0;
                    end else if (a_mod <=(PI+HALFPI)) begin
                       a_tmp<=a_mod-PI;
                        flip_x <= 1;
                        flip_y <= 1;
                    end else begin
                       a_tmp<=TWO_PI-a_mod;
                        flip_x <= 0;
                        flip_y <= 1;
                    end
                      load <= 1;
                  end else if(busy) begin
                if(iter < ITER) begin
                    if(z >= 0) begin
                        x <= x - (y >>> iter);
                        y <= y + (x >>> iter);
                        z <= z - atan_table[iter];
                    end else begin
                        x <= x + (y >>> iter);
                        y <= y - (x >>> iter);
                        z <= z + atan_table[iter];
                    end
                    iter <= iter + 1;
                end else begin
                    // Apply quadrant corrections
                    cosine <= (flip_x ? -x : x);
                    sine   <= (flip_y ? -y : y);
                    done <= 1;
                    busy <= 0;
                    iter<=0;
                end
            end else begin
                done <= 0; // idle
            end
        end
    end
endmodule



