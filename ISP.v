
module ISP(
    //Input Port
    clk,
    rst_n,

    in_valid,
    in,
    param_valid,
    param_gain,

    //Output Port
    out_valid,
    r_out,
    g_out,
    b_out
    );

//==============================
//   INPUT/OUTPUT DECLARATION
//==============================
input clk;
input rst_n;
input in_valid;
input [11:0] in;
input param_valid;
input [11:0] param_gain;

output reg out_valid;
output reg [11:0] r_out;
output reg [11:0] g_out;
output reg [11:0] b_out;

//==============================
//   Design
//==============================

localparam IMG_W = 16;
localparam IMG_H = 16;
localparam TOTAL_PIXELS = 256;
localparam TH = 320;
localparam BLACK_LEVEL = 64;

localparam S_IDLE = 3'd0;
localparam S_INPUT = 3'd1;
localparam S_LSC = 3'd2;
localparam S_DPC = 3'd3;
localparam S_OUTPUT = 3'd4;

reg [2:0] state;
reg [7:0] in_cnt;
reg [7:0] calc_cnt;
reg [7:0] out_cnt;
reg [7:0] param_cnt;

reg [11:0] raw_img [0:255];
reg [11:0] lsc_img [0:255];
reg [11:0] dpc_img [0:255];

reg [11:0] gain_r [0:35];
reg [11:0] gain_gr [0:35];
reg [11:0] gain_gb [0:35];
reg [11:0] gain_b [0:35];

function [3:0] get_x;
    input [7:0] idx;
    begin 
        get_x = idx[3:0];
    end 
endfunction 

function [3:0] get_y;
    input [7:0] idx;
    begin 
        get_y = idx[7:4];
    end 
endfunction 

function integer reflect16;
    input integer v;
    begin 
        if (v < 0)
            reflect16 = -v;
        else if (v >= 16)
            reflect16 = 30 - v;
        else 
            reflect16 = v;
    end 
endfunction

function [7:0] idx_reflect;
    input integer x;
    input integer y;
    integer xr;
    integer yr;
    begin 
        xr = reflect16(x);
        yr = reflect16(y);
        idx_reflect = yr * 16 + xr;
    end 
endfunction

function [1:0] bayer_type;
    input integer x;
    input integer y;
    begin 
        if ((y % 2) == 0 && (x % 2) == 0)
            bayer_type = 2'd0;
        else if ((y % 2) == 0 && (x % 2) == 1)
            bayer_type = 2'd1;
        else if ((y % 2) == 1 && (X % 2) == 0)
            bayer_type = 2'd2;
        else 
            bayer_type = 2'd3;
    end
endfunction 

function [11:0] get_gain;
    input [1:0] ch;
    input integer row;
    input integer col;
    integer gidx;
    begin gidx = row * 6 + col;
        gidx = row * 6 + col;
        case (ch)
            2'd0: get_gain = gain_r[gidx];
            2'd1: get_gain = gain_gr[gidx];
            2'd2: get_gain = gain_gb[gidx];
            default: get_gain = gain_b[gidx];
        endcase
    end
endfunction

function [11:0] clip12;
    input integer v;
    begin 
        if (v < 0)
            clip12 = 12'd0;.
        else if (v > 4095)
            clip12 = 12'd4095;
        else 
            clip12 = v[11:0];
    end
endfunction

function integer abs_int;
    input integer a;
    begin 
        if (a < 0)
            abs_int = -a;
        else
            abs_int = a;
    end
endfunction

function [11:0] avg2;
    input [11:0] a;
    input [11:0] b;
    integer t;
    begin 
        t = a + b;
        avg2 = t >> 1;
    end
endfunction

function [11:0] avg4;
    input [11:0] a;
    input [11:0] b;
    input [11:0] c;
    input [11:0] d;
    integer t;
    begin
        t = a + b + c + d;
        avg4 = t >> 2;
    end
endfunction

function [11:0] median4;
    input [11:0] a;
    input [11:0] b;
    input [11:0] c;
    input [11:0] d;
    reg [11:0] v0, v1, v2, v3, tmp;
    begin
        v0 = a; v1 = b; v2 = c; v3 = d;
        if (v0 > v1) begin tmp = v0; v0 = v1; v1 = tmp; end
        if (v2 > v3) begin tmp = v2; v2 = v3; v3 = tmp; end
        if (v0 > v2) begin tmp = v0; v0 = v2; v2 = tmp; end
        if (v1 > v3) begin tmp = v1; v1 = v3; v3 = tmp; end
        if (v1 > v2) begin tmp = v1; v1 = v2; v2 = tmp; end
        median4 = (v1 + v2) >> 1;
    end
endfunction

function integer sad4;
    input [11:0] a;
    input [11:0] b;
    input [11:0] c;
    input [11:0] d;
    input [11:0] med;
    begin 
        sad4 = abs_int(a - med) + abs_int(b - med) + abs_int(c - med) + abs_int(d - med);
    end
endfunction

function [11:0] calc_lsc_pixel;
    input [7:0] idx;
    integer x, y;
    integer x0, y0;
    integer rx, ry;
    integer dx, ix;
    integer dy, iy;
    integer sum_gain;
    integer final_v;
    integer raw_minus_blc;
    reg [1:0] ch;
    reg [11:0] g00, g01, g10, g11;
    reg [11:0] interp_gain;
    begin 
        x = get_x(idx);
        y = get_y(idx);

        x0 = x / 3;
        y0 = y / 3;
        if (x0 > 4) x0 = 4;
        if (y0 > 4) y0 = 4; 
        
        rx = x - 3 * x0;
        ry = y - 3 * y0;
        if (rx > 2) rx = 2;
        if (ry > 2) ry = 2;

        dx = (rx * 256 + 1) / 3;
        ix = 256 - dx
        dy = (ry * 256 + 1) / 3;
        iy = 256 - dy;

        ch = bayer_type(x, y);
        g00 = get_gain(ch, y0, x0);
        g01 = get_gain(ch, y0, x0 + 1);
        g10 = get_gain(ch, y0+1, x0);
        g11 = get_gain(ch, y0 + 1, x0 + 1);

        sum_gain = g00 * ix * iy + g10 * ix * dy + g01 * dx * iy + g11 * dx * dy + 32768;
        interp_gain = sum_gain >> 16;

        if (raw_img[idx] > BLACK_LEVEL)
            raw_minus_blc = raw_img[idx] - BLACK_LEVEL;
        else 
            raw_minus_blc = 0;

        final_v = (raw_minus_blc * interp_gain + 512) >> 10;
        calc_lsc_pixel = clip12(final_v);
    end 
endfunction


