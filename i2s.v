module i2s(
    input         rst_i,

    input         mck_i,
    input         lrck_i,
    input         bck_i,
    input         data_i,

    output        mck_o,
    output        lrck_o,
    output        bck_o,
    output        data_o,

// 4 output
    output        mck,
    output reg    le,
    output        bck,
    output reg    sdo,

    output        mck1,
    output reg    le1,
    output        bck1,
    output reg    sdo1,

    output        mck2,
    output reg    le2,
    output        bck2,
    output reg    sdo2,

    output        mck3,
    output reg    le3,
    output        bck3,
    output reg    sdo3
);

localparam  BIT = 24;
localparam  B= 0;
localparam  E = B+BIT;

localparam  IDLE = 0;
localparam  R_START = 1;
localparam  R_TRANSFER = 2;
localparam  R_DONE = 3;
localparam  L_START = 4;
localparam  L_TRANSFER = 5;
localparam  L_DONE = 6;
localparam  FLASH = 7;

reg lrck_r;
reg lrck_rr;
wire left_start = ~lrck_r & lrck_rr;
wire right_start = lrck_r & ~lrck_rr;

always @(negedge bck_i or negedge rst_i) begin
    if (!rst_i) begin
        lrck_r <= 0;
        lrck_rr <= 0;
    end
    else begin
        lrck_r <= lrck_i;
        lrck_rr <= lrck_r;
    end
end

reg             data_r;
reg[3:0]        state;
reg[6:0]        count;
reg signed [BIT-1:0]    val;
reg signed [BIT-1:0]    l_val;
reg signed [BIT-1:0]    l_val_rr;
reg signed [BIT-1:0]    r_val;
reg signed [BIT-1:0]    r_val_rr;

reg [7:0] noise_a, noise_b;
always @(negedge bck_i or negedge rst_i) begin
    if (!rst_i) begin
        noise_a <= 8'h1;
        noise_b <= 8'h2;
    end else begin
        noise_a <= {noise_a[6:0], noise_a[7] ^ noise_a[5] ^ noise_a[4] ^ noise_a[3]};
        noise_b <= {noise_b[6:0], noise_b[7] ^ noise_b[5] ^ noise_b[4] ^ noise_b[3]};
    end
end
wire signed [8:0] dither_noise = {1'b0, noise_a} + {1'b0, noise_b}; // [-255, +255]

always @(negedge bck_i or negedge rst_i) begin
    if (!rst_i) begin
        state <= IDLE;
        count <= 0;

        val <= 0;
        l_val <= 0;
        l_val_rr <= 0;
        r_val <= 0;
        r_val_rr <= 0;

        data_r <= 0;
    end
    else begin
        data_r <= data_i;

        if (right_start)
            state <= R_TRANSFER;
        else if (left_start)
            state <= L_TRANSFER;
        else begin
            case(state)
                IDLE:
                    val <= 0;
                R_TRANSFER: begin
                    if (count == E) begin
                        count <= 0;
                        state <= R_DONE;
                    end
                    else if (count < E) begin
                        val <= {val[BIT-2:0], data_r};
                        count <= count + 1;
                    end
                end
                R_DONE: begin
                    r_val <= val;
                    // r_val_rr <= r_val;
                    r_val_rr <= r_val + {{15{dither_noise[6]}}, dither_noise};
 
                    state <= IDLE;
                end
                L_TRANSFER: begin
                    if (count == E) begin
                        count <= 0;
                        state <= L_DONE;
                    end
                    else if (count < E) begin
                        val <= {val[BIT-2:0], data_r};
                        count <= count + 1;
                    end
                end
                L_DONE: begin
                    l_val <= val;
                    // l_val_rr <= l_val;
                    l_val_rr <= l_val + {{15{dither_noise[6]}}, dither_noise}; 

                    state <= IDLE;
                end
            endcase
        end
    end
end

assign  mck = mck_i;
assign  mck2 = mck_i;
assign  mck3 = mck_i;

assign  bck = bck_i;
assign  bck2 = bck_i;
assign  bck3 = bck_i;

assign  mck_o = mck_i;
assign  bck_o = bck_i;
assign  lrck_o = lrck_i;
assign  data_o = bck_i;

// localparam  WORD = 18;
localparam  WORD = 16;
reg [3:0]       state_w;
reg [6:0]       count_w;
reg signed [BIT-1:0]      key;
reg signed [BIT-1:0]      key1;
reg signed [BIT-1:0]      key2;
reg signed [BIT-1:0]      key3;

always @(negedge bck_i or negedge rst_i) begin
    if (!rst_i)  begin
        key <= {BIT-1'h0};
        key1 <= {BIT-1'h0};
        key2 <= {BIT-1'h0};
        key3 <= {BIT-1'h0};
        sdo <= 0;
        sdo1 <= 0;
        sdo2 <= 0;
        sdo3 <= 0;
        le <= 1;
        le1 <= 1;
        le2 <= 1;
        le3 <= 1;

        count_w <= 0;
        state_w <= IDLE;
    end
    else if (left_start) begin
        key <= l_val_rr + l_val_rr[7:0];
        // key2 <= l_val_rr;
        // key3 <= r_val_rr;
        key2 <= l_val_rr + {l_val_rr[7], {7{1'b0}}};
        key3 <= r_val_rr + {r_val_rr[7], {7{1'b0}}};

        le <= 1;
        le2 <= 1;
        le3 <= 1;

        state_w <= FLASH;
    end
    else if (right_start) begin
        key <= r_val_rr + r_val_rr[7:0];;
        key2 <= l_val_rr;
        key3 <= r_val_rr;
        key2 <= l_val_rr + {l_val_rr[7], {7{1'b0}}};
        key3 <= r_val_rr + {r_val_rr[7], {7{1'b0}}};

        le <= 1;
        le2 <= 1;
        le3 <= 1;

        state_w <= FLASH;
    end
    else if (state_w == FLASH) begin
        if (count_w == WORD) begin
            state_w <= IDLE;
            count_w <= 0;
            
            sdo <= 0;
            sdo2 <= 0;
            sdo3 <= 0;

            le <= 0;
            le2 <= 0;
            le3 <= 0;
        end
        else begin
            sdo <= key[BIT-1 - count_w];
            sdo2 <= key2[BIT-1 - count_w];
            sdo3 <= key3[BIT-1 - count_w];

            count_w <= count_w + 1;
        end
    end
end
endmodule
