module DRCA (
    input [3:0]  drc_sel,
    input [18:0] shape0,
    input [18:0] shape1,
    input [18:0] shape2,
    input [18:0] shape3,
    input [18:0] shape4,
    input [18:0] shape5,
    input [18:0] shape6,
    input [18:0] shape7,
    input [18:0] shape8,
    input [18:0] shape9,
    input [18:0] shape10,
    input [18:0] shape11,
    input [18:0] shape12,
    input [18:0] shape13,
    input [18:0] shape14,
    input [18:0] shape15,
    output [4:0] drc_out
);


//**************************************************
// Parameter 
//**************************************************


//**************************************************
// Reg & Wire 
//**************************************************
integer i;
integer k;

integer z;
integer a;

reg [18:0] shapes [0:15];

reg [3:0] overlap_x_left;
reg [3:0] overlap_x_right;
reg [3:0] overlap_y_lower;
reg [3:0] overlap_y_upper;

reg [2:0] target_layer;
reg [3:0] requirement;
reg is_spacing;
reg [4:0] drc_result;

reg [4:0] shape_violation_count;
reg [4:0] overlap_violation_count;

reg overlap_added;

//**************************************************
// Design 
//**************************************************

always @(*) begin
    shapes[0]  = shape0;
    shapes[1]  = shape1;
    shapes[2]  = shape2;
    shapes[3]  = shape3;
    shapes[4]  = shape4;
    shapes[5]  = shape5;
    shapes[6]  = shape6;
    shapes[7]  = shape7;
    shapes[8]  = shape8;
    shapes[9]  = shape9;
    shapes[10] = shape10;
    shapes[11] = shape11;
    shapes[12] = shape12;
    shapes[13] = shape13;
    shapes[14] = shape14;
    shapes[15] = shape15;

    target_layer = 3'd0;
    requirement  = 4'd0;
    is_spacing   = 1'b0;
    drc_result   = 5'd0;

    shape_violation_count   = 5'd0;
    overlap_violation_count = 5'd0;

    overlap_added = 1'b0;

    case(drc_sel) 
        4'b0000: begin target_layer = 3'd1; requirement = 4'd2; is_spacing = 1'b0; end
        4'b0001: begin target_layer = 3'd1; requirement = 4'd2; is_spacing = 1'b1; end

        4'b0010: begin target_layer = 3'd2; requirement = 4'd3; is_spacing = 1'b0; end
        4'b0011: begin target_layer = 3'd2; requirement = 4'd2; is_spacing = 1'b1; end

        4'b0100: begin target_layer = 3'd3; requirement = 4'd2; is_spacing = 1'b0; end
        4'b0101: begin target_layer = 3'd3; requirement = 4'd2; is_spacing = 1'b1; end

        4'b0110: begin target_layer = 3'd4; requirement = 4'd3; is_spacing = 1'b0; end
        4'b0111: begin target_layer = 3'd4; requirement = 4'd2; is_spacing = 1'b1; end

        4'b1000: begin target_layer = 3'd5; requirement = 4'd4; is_spacing = 1'b0; end
        4'b1001: begin target_layer = 3'd5; requirement = 4'd3; is_spacing = 1'b1; end

        4'b1010: begin target_layer = 3'd6; requirement = 4'd4; is_spacing = 1'b0; end
        4'b1011: begin target_layer = 3'd6; requirement = 4'd3; is_spacing = 1'b1; end

        4'b1100: begin target_layer = 3'd7; requirement = 4'd5; is_spacing = 1'b0; end
        4'b1101: begin target_layer = 3'd7; requirement = 4'd4; is_spacing = 1'b1; end

        default: begin target_layer = 3'd0; requirement = 4'd0; is_spacing = 1'b0; end
    endcase
    

    // Width rule
    if (is_spacing == 1'b0) begin
        for (i = 0; i < 16; i = i + 1) begin
            if (shapes[i][18:16] == target_layer) begin

                z = shapes[i][7:4] - shapes[i][15:12];
                a = shapes[i][3:0] - shapes[i][11:8];

                if (z < requirement) begin
                    shape_violation_count = shape_violation_count + 5'd1;
                    drc_result = drc_result + 5'd1;
                end

                if (a < requirement) begin
                    shape_violation_count = shape_violation_count + 5'd1;
                    drc_result = drc_result + 5'd1;
                end
            

                // Derived overlap/touch region check
                for (k = 0; k < 16; k = k + 1) begin
                    if ((k < i) && (shapes[k][18:16] == target_layer)) begin

                        overlap_x_left = (shapes[i][15:12] > shapes[k][15:12]) ?
                                          shapes[i][15:12] : shapes[k][15:12];

                        overlap_x_right = (shapes[i][7:4] < shapes[k][7:4]) ?
                                           shapes[i][7:4] : shapes[k][7:4];

                        overlap_y_lower = (shapes[i][11:8] > shapes[k][11:8]) ?
                                           shapes[i][11:8] : shapes[k][11:8];

                        overlap_y_upper = (shapes[i][3:0] < shapes[k][3:0]) ?
                                           shapes[i][3:0] : shapes[k][3:0];

                        if ((overlap_x_left <= overlap_x_right) &&
                            (overlap_y_lower <= overlap_y_upper)) begin

                            if (!overlap_added &&
                                (((overlap_x_right - overlap_x_left) < requirement) ||
                                 ((overlap_y_upper - overlap_y_lower) < requirement))) begin

                                drc_result = drc_result + 5'd1;
                                overlap_violation_count = overlap_violation_count + 5'd1;
                                overlap_added = 1'b1;
                            end
                        end
                    end 
                end
            end     
        end      
    end


    // Spacing rule
    else if (is_spacing == 1'b1) begin
        for (i = 0; i < 16; i = i + 1) begin
            for (k = 0; k < 16; k = k + 1) begin 
                if ((k < i) &&
                    (shapes[i][18:16] == target_layer) &&
                    (shapes[k][18:16] == target_layer)) begin

                    overlap_x_left = (shapes[i][15:12] > shapes[k][15:12]) ?
                                      shapes[i][15:12] : shapes[k][15:12];

                    overlap_x_right = (shapes[i][7:4] < shapes[k][7:4]) ?
                                       shapes[i][7:4] : shapes[k][7:4];

                    overlap_y_lower = (shapes[i][11:8] > shapes[k][11:8]) ?
                                       shapes[i][11:8] : shapes[k][11:8];

                    overlap_y_upper = (shapes[i][3:0] < shapes[k][3:0]) ?
                                       shapes[i][3:0] : shapes[k][3:0];


                    // Vertical spacing:
                    // x-ranges overlap, y-ranges are separated.
                    if (overlap_x_left < overlap_x_right) begin 
                        if ((overlap_y_lower > overlap_y_upper) &&
                            ((overlap_y_lower - overlap_y_upper) < requirement)) begin

                            drc_result = drc_result + 5'd1;
                        end
                    end 


                    // Horizontal spacing:
                    // y-ranges overlap, x-ranges are separated.
                    if (overlap_y_lower < overlap_y_upper) begin 
                        if ((overlap_x_left > overlap_x_right) &&
                            ((overlap_x_left - overlap_x_right) < requirement)) begin

                            drc_result = drc_result + 5'd1;
                        end
                    end 
                end 
            end 
        end 
    end
end

assign drc_out = drc_result;

endmodule