module traffic_light_controller #(
    parameter int CLK_FREQ_HZ = 1   
)(
    input  logic clk,
    input  logic rst_n,
    input  logic sensor,

    output logic hw_red,
    output logic hw_yellow,
    output logic hw_green,

    output logic city_red,
    output logic city_yellow,
    output logic city_green
);

    //==================================================
    // State encoding
    //==================================================
    typedef enum logic [2:0] {
        HW_GREEN_IDLE = 3'd0,
        HW_YELLOW     = 3'd1,
        CITY_GREEN    = 3'd2,
        CITY_YELLOW   = 3'd3,
        HW_GREEN_HOLD = 3'd4
    } state_t;

    state_t state, next_state;

    //==================================================
    // Time constants in clock cycles
    //==================================================
    localparam int YELLOW_TIME = 3 * CLK_FREQ_HZ;
    localparam int GREEN_TIME  = 5 * CLK_FREQ_HZ;

    // counter width
    logic [$clog2(GREEN_TIME + 1)-1:0] timer;

    //==================================================
    // Sequential logic: state and timer update
    //==================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= HW_GREEN_IDLE;
            timer <= '0;
        end
        else begin
            state <= next_state;

            // reset timer whenever state changes
            if (state != next_state)
                timer <= '0;
            else
                timer <= timer + 1'b1;
        end
    end

    //==================================================
    // Next-state logic
    //==================================================
    always_comb begin
        next_state = state;

        case (state)
            //------------------------------------------
            // Initial/default highway green
            //------------------------------------------
            HW_GREEN_IDLE: begin
                if (sensor)
                    next_state = HW_YELLOW;
            end

            //------------------------------------------
            // Highway yellow for 3 sec
            //------------------------------------------
            HW_YELLOW: begin
                if (timer == YELLOW_TIME - 1)
                    next_state = CITY_GREEN;
            end

            //------------------------------------------
            // City green for 5 sec
            //------------------------------------------
            CITY_GREEN: begin
                if (timer == GREEN_TIME - 1)
                    next_state = CITY_YELLOW;
            end

            //------------------------------------------
            // City yellow for 3 sec
            //------------------------------------------
            CITY_YELLOW: begin
                if (timer == YELLOW_TIME - 1)
                    next_state = HW_GREEN_HOLD;
            end

            //------------------------------------------
            // Highway green again, must hold at least 5 sec
            //------------------------------------------
            HW_GREEN_HOLD: begin
                if (timer < GREEN_TIME - 1)
                    next_state = HW_GREEN_HOLD;
                else if (sensor)
                    next_state = HW_YELLOW;
                else
                    next_state = HW_GREEN_IDLE;
            end

            default: begin
                next_state = HW_GREEN_IDLE;
            end
        endcase
    end

    //==================================================
    // Output logic
    //==================================================
    always_comb begin
        // default all OFF
        hw_red      = 1'b0;
        hw_yellow   = 1'b0;
        hw_green    = 1'b0;
        city_red    = 1'b0;
        city_yellow = 1'b0;
        city_green  = 1'b0;

        case (state)
            HW_GREEN_IDLE: begin
                hw_green = 1'b1;
                city_red = 1'b1;
            end

            HW_YELLOW: begin
                hw_yellow = 1'b1;
                city_red  = 1'b1;
            end

            CITY_GREEN: begin
                hw_red     = 1'b1;
                city_green = 1'b1;
            end

            CITY_YELLOW: begin
                hw_red      = 1'b1;
                city_yellow = 1'b1;
            end

            HW_GREEN_HOLD: begin
                hw_green = 1'b1;
                city_red = 1'b1;
            end

            default: begin
                hw_green = 1'b1;
                city_red = 1'b1;
            end
        endcase
    end

endmodule