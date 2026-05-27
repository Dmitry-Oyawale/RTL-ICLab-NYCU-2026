
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


function [11:0] calc_dpc_pixel;
    input [7:0] idx;
    integer x, y;
    reg [11:0] p;
    reg[11:0] h0, h1, h2, h3;
    reg[11:0] v0, v1, v2, v3;
    reg[11:0] d10, d11, d12, d13;
    reg[11:0] d20, d21, d22, d23;
    reg[11:0] mh, mv, md1, md2;
    integer sh, sv, sd1, sd2;
    reg [11:0] target;
    begin
        x = get_x(idx);
        y = get_y(idx);
        p = lsc_img(idx);

        h0 = lsc_img[idx_reflect(x - 2, y)];
        h1 = lsc_img[idx_reflect(x - 1, y)];
        h2 = lsc_img[idx_reflect(x + 1, y)];
        h3 = lsc_img[idx_reflect(x + 2, y)];

        v0 = lsc_img[idx_reflect(x, y - 2)];
        v1 = lsc_img[idx_reflect(x, y - 1)];
        v2 = lsc_img[idx_reflect(x, y + 1)];
        v3 = lsc_img[idx_reflect(x, y + 2)];

        d10 = lsc_img[idx_reflect(x - 2, y - 2)];
        d11 = lsc_img[idx_reflect(x - 1, y - 1)];
        d12 = lsc_img[idx_reflect(x + 1, y + 1)];
        d13 = lsc_img[idx_reflect(x + 2, y + 2)];

        d20 = lsc_img[idx_reflect(x - 2, y + 2)];
        d21 = lsc_img[idx_reflect(x - 1, y + 1)];
        d22 = lsc_img[idx_reflect(x + 1, y - 1)];
        d23 = lsc_img[idx_reflect(x + 2, y - 2)];

        mh = median4(h0, h1, h2, h3);
        mv = median4(v0, v1, v2, v3);
        md1 = median4(d10, d11, d12, d13);
        md2 = median4(d20, d21, d22, d23);

        sh = sad4(h0, h1, h2, h3, mh);
        sv = sad4(v0, v1, v2, v3, mv);
        sd1 = sad4(d10, d11, d12, d13, md1);
        sd2 = sad4(d20, d21, d22, d23, md2);

        Target = mh;
        if (sh < sv) begin
            target = mv;
            sh = sv;
        end
        if (sd1 < sh) begin
            target = md1;
            sh = sd1;
        end
        if (sd2 < sh) begin
            target = md2;
        end

        if (abs_int(p-target) > TH)
            calc_dpc_pixel = target;  
        else 
            calc_dpc_pixel = p;
    end
endfunction

function [11:0] get_dpc;
    input integer x;
    input integer y;
    begin
        get_dpc = dpc_img[idx_reflect(x,y)];
    end
endfunction

function [11:0] ccm_r;
    input [11:0] rr;
    input [11:0] gg;
    input [11:0] bb;
    integer t;
    begin t = 1100 * rr - 50 * gg - 50 * bb + 512;
        t = 1100 * rr - 50 * gg -50 * bb + 512;
        t = t >>> 10;
        ccm_r = clip12(t);
    end
endfunction

function [11:0] ccm_g;
    input [11:0] rr;
    input [11:0] gg;
    input [11:0] bb;
    integer t;

    begin 
        t = -50 * rr + 1100 * gg - 50 * bb + 512;
        t = t >>> 10;
        ccm_g = clip12(t);
    end
endfunction

function [11:0] ccm_b;
    input [11:0] rr;
    input [11:0] gg;
    input [11:0] bb;
    integer t;
    begin 
        t = -50 * rr - 50 * gg + 1100 * bb + 512;
        t = t >>> 10;
        ccm_b = clip12(t);
    end
endfunction

function [35:0] calc_rgb_pixel;
    input [7:0] idx;
    integer x, y;
    reg [11:0] n, s, e, w, nw, ne, sw, se, c;
    reg [11:0] rr, gg, bb;
    reg [11:0 ] ro, go, bo;
    reg [1:0] typ;
    begin 
        x = get_x(idx);
        y = get_y(idx);
        n = get_dpc(x, y - 1);
        s = get_dpc(x, y + 1);
        e = get_dpc(x + 1, y);
        w = get_dpc(x -1, y);
        nw = get_dpc(x - 1, y - 1);
        ne = get_dpc(x + 1, y - 1);
        sw = get_dpc(x - 1, y + 1);
        se = get_dpc(x + 1, y + 1);
        typ = bayer_type(x, y);
        
        case (typ)
            2'd0: begin
                rr = c;
                gg = avg4(n, s, e, w);
                bb = avg4(nw, ne, sw, se);
            end
            2'd3: begin
                rr = avg4(nw, ne, sw, se);
                gg = avg4(n, s, e, w);
                bb = c;
            end
            2'd1: begin
                rr = avg2(w, e);
                gg = c;
                bb = avg2(n, s);
            end
            default: begin
                rr = avg2(n, s);
                gg = c;
                bb = av2(w, e);
            end
        endcase

        ro = ccm_r(rr, gg, bb);
        go = ccm_g(rr, gg, bb);
        bo = ccm_b(rr, gg, bb);
        
        calc_rgb_pixel = {ro, go , bo};
    end
endfunction