module i2s(
    input               rst_i,
    input               mck_i,
    input               lrck_i,
    input               bck_i,
    input               data_i,

    output              mck_o,
    output              lrck_o,
    output              bck_o,
    output              data_o,

    // 4 output
    output              mck0_o,
    output reg          le0_o,
    output              bck0_o,
    output reg          sdo0_o,

    output              mck1_o,
    output reg          le1_o,
    output              bck1_o,
    output reg          sdo1_o,

    output              mck2_o,
    output reg          le2_o,
    output              bck2_o,
    output reg          sdo2_o,

    output              mck3_o,
    output reg          le3_o,
    output              bck3_o,
    output reg          sdo3_o
);

localparam  FRAME = 24;
localparam  E = FRAME;

localparam  IDLE = 0, R_START = 1, R_TRANSFER = 2, R_DONE = 3;
localparam  L_START = 4, L_TRANSFER = 5, L_DONE = 6, FLASH = 7;

// LRCK 邊緣偵測
reg lrck_r, lrck_rr;
wire left_start  = ~lrck_r & lrck_rr;
wire right_start =  lrck_r & ~lrck_rr;

always @(posedge bck_i or negedge rst_i) begin
    if (!rst_i) begin
        lrck_r  <= 0;
        lrck_rr <= 0;
    end else begin
        lrck_r  <= lrck_i;
        lrck_rr <= lrck_r;
    end
end

// 資料暫存
reg             data_r;
reg [3:0]       state;
reg [6:0]       count;
reg signed [FRAME-1:0] val, l_val, l_val_rr, r_val, r_val_rr;

// 8bit TPDF dither產生器
reg [7:0] noise, noise2;
always @(posedge bck_i or negedge rst_i) begin
    if (!rst_i) begin
        noise  <= 8'h5A;
        noise2 <= 8'hA5;
    end else begin
        noise  <= {noise[6:0],  noise[7]  ^ noise[5]  ^ noise[4]  ^ noise[3]};
        noise2 <= {noise2[6:0], noise2[7] ^ noise2[5] ^ noise2[4] ^ noise2[3]};
    end
end
wire signed [8:0] dither_noise = {1'b0, noise} - {1'b0, noise2}; // TPDF, -255~+255

// 資料接收狀態機
always @(posedge bck_i or negedge rst_i) begin
    if (!rst_i) begin
        state    <= IDLE;
        count    <= 0;
        val      <= 0;
        l_val    <= 0;
        l_val_rr <= 0;
        r_val    <= 0;
        r_val_rr <= 0;
        data_r   <= 0;
    end else begin
        data_r <= data_i;
        if (right_start)
            state <= R_TRANSFER;
        else if (left_start)
            state <= L_TRANSFER;
        else begin
            case(state)
                IDLE: val <= 0;
                R_TRANSFER: begin
                    if (count == E) begin
                        count <= 0;
                        state <= R_DONE;
                    end else if (count < E) begin
                        val   <= {val[FRAME-2:0], data_r};
                        count <= count + 1;
                    end
                end
                R_DONE: begin
                    r_val    <= val;
                    // r_val_rr <= r_val;
                    r_val_rr <= r_val + {{15{dither_noise[8]}}, dither_noise}; // 若要加dither
                    state    <= IDLE;
                end
                L_TRANSFER: begin
                    if (count == E) begin
                        count <= 0;
                        state <= L_DONE;
                    end else if (count < E) begin
                        val   <= {val[FRAME-2:0], data_r};
                        count <= count + 1;
                    end
                end
                L_DONE: begin
                    l_val    <= val;
                    // l_val_rr <= l_val;
                    l_val_rr <= l_val + {{15{dither_noise[8]}}, dither_noise}; // 若要加dither
                    state    <= IDLE;
                end
            endcase
        end
    end
end

// 輸出時脈對應
assign mck0_o = mck_i;
assign mck2_o = mck_i;
assign mck3_o = mck_i;
assign bck0_o = bck_i;
assign bck2_o = bck_i;
assign bck3_o = bck_i;
assign mck_o  = mck_i;
assign bck_o  = bck_i;
assign lrck_o = lrck_i;
assign data_o = bck_i;

// 串列資料輸出狀態機
localparam BIT = 16;
reg [3:0]       state_w;
reg [6:0]       count_w;
reg [FRAME-1:0] key0, key1, key2, key3;

always @(negedge bck_o or negedge rst_i) begin
    if (!rst_i) begin
        key0  <= 0;
        key1  <= 0;
        key2  <= 0;
        key3  <= 0;
        sdo0_o <= 0;
        sdo1_o   <= 0;
        sdo2_o <= 0;
        sdo3_o <= 0;
        le0_o  <= 1;
        le1_o  <= 1;
        le2_o  <= 1;
        le3_o  <= 1;
        count_w <= 0;
        state_w <= IDLE;
    end else if (left_start) begin
        key0  <= l_val_rr + l_val_rr[7:0];
        key2  <= l_val_rr + l_val_rr[7:0];
        key3  <= r_val_rr + r_val_rr[7:0];
        le0_o <= 1;
        le2_o <= 1;
        le3_o <= 1;
        state_w <= FLASH;
    end else if (right_start) begin
        key0  <= r_val_rr + r_val_rr[7:0];
        key2  <= l_val_rr + l_val_rr[7:0]; 
        key3  <= r_val_rr + r_val_rr[7:0];
        le0_o <= 1;
        le2_o <= 1;
        le3_o <= 1;
        state_w <= FLASH;
    end else if (state_w == FLASH) begin
        if (count_w == BIT) begin
            state_w <= IDLE;
            count_w <= 0;
            sdo0_o  <= 0;
            sdo2_o  <= 0;
            sdo3_o  <= 0;
            le0_o   <= 0;
            le2_o   <= 0;
            le3_o   <= 0;
        end else begin
            sdo0_o  <= key0[FRAME-1 - count_w];
            sdo2_o  <= key2[FRAME-1 - count_w];
            sdo3_o  <= key3[FRAME-1 - count_w];
            count_w <= count_w + 1;
        end
    end
end

endmodule
