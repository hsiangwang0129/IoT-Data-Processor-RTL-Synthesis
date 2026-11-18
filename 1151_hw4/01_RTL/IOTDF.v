`timescale 1ns / 10ps
module IOTDF (
    clk,
    rst,
    in_en,
    iot_in,
    fn_sel,
    busy,
    valid,
    iot_out
);
  input clk;
  input rst;
  input in_en;
  input [7:0] iot_in;
  input [2:0] fn_sel;
  output reg busy;
  output reg valid;
  output reg [127:0] iot_out;

  localparam [2:0] WAIT_DATA = 3'd0, LOAD_INPUT = 3'd1, INIT = 3'd2, ROUND = 3'd3, OUTPUT = 3'd4;

  reg [2:0] state;
  reg [3:0] byte_count;
  reg [4:0] round_number;
  reg [127:0] data_buf;
  reg [63:0] main_key;
  reg [63:0] des_block;
  reg [31:0] left_reg;
  reg [31:0] right_reg;
  reg [27:0] key_left;
  reg [27:0] key_right;

  wire [63:0] ip_block;
  wire [31:0] left_initial;
  wire [31:0] right_initial;
  wire [55:0] pc1_key;
  wire [27:0] key_left_initial;
  wire [27:0] key_right_initial;
  wire shift_one;
  wire [27:0] key_left_rotated;
  wire [27:0] key_right_rotated;
  wire [47:0] round_key;
  wire [47:0] expanded_right;
  wire [47:0] mixed_right;
  wire [3:0] s1_output;
  wire [3:0] s2_output;
  wire [3:0] s3_output;
  wire [3:0] s4_output;
  wire [3:0] s5_output;
  wire [3:0] s6_output;
  wire [3:0] s7_output;
  wire [3:0] s8_output;
  wire [31:0] sbox_result;
  wire [31:0] f_result;
  wire [63:0] pre_fp;
  wire [63:0] des_result;

  assign ip_block = des_ip(des_block);
  assign left_initial = ip_block[63:32];
  assign right_initial = ip_block[31:0];
  assign pc1_key = des_pc1(main_key);
  assign key_left_initial = pc1_key[55:28];
  assign key_right_initial = pc1_key[27:0];

  assign shift_one = (round_number == 5'd1) ||
      (round_number == 5'd2) ||
      (round_number == 5'd9) ||
      (round_number == 5'd16);
  assign key_left_rotated = shift_one
      ? {key_left[26:0], key_left[27]}
      : {key_left[25:0], key_left[27:26]};
  assign key_right_rotated = shift_one
      ? {key_right[26:0], key_right[27]}
      : {key_right[25:0], key_right[27:26]};
  assign round_key = des_pc2({key_left_rotated, key_right_rotated});

  assign expanded_right = des_expand(right_reg);
  assign mixed_right = expanded_right ^ round_key;
  assign s1_output = des_s1(mixed_right[47:42]);
  assign s2_output = des_s2(mixed_right[41:36]);
  assign s3_output = des_s3(mixed_right[35:30]);
  assign s4_output = des_s4(mixed_right[29:24]);
  assign s5_output = des_s5(mixed_right[23:18]);
  assign s6_output = des_s6(mixed_right[17:12]);
  assign s7_output = des_s7(mixed_right[11:6]);
  assign s8_output = des_s8(mixed_right[5:0]);
  assign sbox_result = {
    s1_output, s2_output, s3_output, s4_output, s5_output, s6_output, s7_output, s8_output
  };
  assign f_result = des_p(sbox_result);
  assign pre_fp = {right_reg, left_reg};
  assign des_result = des_fp(pre_fp);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state <= WAIT_DATA;
      byte_count <= 4'd0;
      round_number <= 5'd1;
      data_buf <= 128'd0;
      main_key <= 64'd0;
      des_block <= 64'd0;
      left_reg <= 32'd0;
      right_reg <= 32'd0;
      key_left <= 28'd0;
      key_right <= 28'd0;
      busy <= 1'b0;
      valid <= 1'b0;
      iot_out <= 128'd0;
    end else begin
      valid <= 1'b0;
      case (state)
        WAIT_DATA: begin
          if (in_en && (fn_sel == 3'd1)) begin
            data_buf[(byte_count*8)+:8] <= iot_in;
            if (byte_count == 4'd14) busy <= 1'b1;
            if (byte_count == 4'd15) begin
              byte_count <= 4'd0;
              state <= LOAD_INPUT;
            end else begin
              byte_count <= byte_count + 4'd1;
            end
          end
        end
        LOAD_INPUT: begin
          main_key <= data_buf[127:64];
          des_block <= data_buf[63:0];
          state <= INIT;
        end
        INIT: begin
          left_reg <= left_initial;
          right_reg <= right_initial;
          key_left <= key_left_initial;
          key_right <= key_right_initial;
          round_number <= 5'd1;
          state <= ROUND;
        end
        ROUND: begin
          key_left  <= key_left_rotated;
          key_right <= key_right_rotated;
          left_reg  <= right_reg;
          right_reg <= left_reg ^ f_result;
          if (round_number == 5'd16) state <= OUTPUT;
          else round_number <= round_number + 5'd1;
        end
        OUTPUT: begin
          iot_out <= {main_key, des_result};
          valid <= 1'b1;
          busy <= 1'b0;
          state <= WAIT_DATA;
        end
        default: begin
          state <= WAIT_DATA;
          byte_count <= 4'd0;
          busy <= 1'b0;
        end
      endcase
    end
  end

  function [63:0] des_ip;
    input [63:0] block_in;
    begin
      des_ip = {
        block_in[6],
        block_in[14],
        block_in[22],
        block_in[30],
        block_in[38],
        block_in[46],
        block_in[54],
        block_in[62],
        block_in[4],
        block_in[12],
        block_in[20],
        block_in[28],
        block_in[36],
        block_in[44],
        block_in[52],
        block_in[60],
        block_in[2],
        block_in[10],
        block_in[18],
        block_in[26],
        block_in[34],
        block_in[42],
        block_in[50],
        block_in[58],
        block_in[0],
        block_in[8],
        block_in[16],
        block_in[24],
        block_in[32],
        block_in[40],
        block_in[48],
        block_in[56],
        block_in[7],
        block_in[15],
        block_in[23],
        block_in[31],
        block_in[39],
        block_in[47],
        block_in[55],
        block_in[63],
        block_in[5],
        block_in[13],
        block_in[21],
        block_in[29],
        block_in[37],
        block_in[45],
        block_in[53],
        block_in[61],
        block_in[3],
        block_in[11],
        block_in[19],
        block_in[27],
        block_in[35],
        block_in[43],
        block_in[51],
        block_in[59],
        block_in[1],
        block_in[9],
        block_in[17],
        block_in[25],
        block_in[33],
        block_in[41],
        block_in[49],
        block_in[57]
      };
    end
  endfunction

  function [55:0] des_pc1;
    input [63:0] key_in;
    begin
      des_pc1 = {
        key_in[7],
        key_in[15],
        key_in[23],
        key_in[31],
        key_in[39],
        key_in[47],
        key_in[55],
        key_in[63],
        key_in[6],
        key_in[14],
        key_in[22],
        key_in[30],
        key_in[38],
        key_in[46],
        key_in[54],
        key_in[62],
        key_in[5],
        key_in[13],
        key_in[21],
        key_in[29],
        key_in[37],
        key_in[45],
        key_in[53],
        key_in[61],
        key_in[4],
        key_in[12],
        key_in[20],
        key_in[28],
        key_in[1],
        key_in[9],
        key_in[17],
        key_in[25],
        key_in[33],
        key_in[41],
        key_in[49],
        key_in[57],
        key_in[2],
        key_in[10],
        key_in[18],
        key_in[26],
        key_in[34],
        key_in[42],
        key_in[50],
        key_in[58],
        key_in[3],
        key_in[11],
        key_in[19],
        key_in[27],
        key_in[35],
        key_in[43],
        key_in[51],
        key_in[59],
        key_in[36],
        key_in[44],
        key_in[52],
        key_in[60]
      };
    end
  endfunction

  function [47:0] des_pc2;
    input [55:0] key_in;
    begin
      des_pc2 = {
        key_in[42],
        key_in[39],
        key_in[45],
        key_in[32],
        key_in[55],
        key_in[51],
        key_in[53],
        key_in[28],
        key_in[41],
        key_in[50],
        key_in[35],
        key_in[46],
        key_in[33],
        key_in[37],
        key_in[44],
        key_in[52],
        key_in[30],
        key_in[48],
        key_in[40],
        key_in[49],
        key_in[29],
        key_in[36],
        key_in[43],
        key_in[54],
        key_in[15],
        key_in[4],
        key_in[25],
        key_in[19],
        key_in[9],
        key_in[1],
        key_in[26],
        key_in[16],
        key_in[5],
        key_in[11],
        key_in[23],
        key_in[8],
        key_in[12],
        key_in[7],
        key_in[17],
        key_in[0],
        key_in[22],
        key_in[3],
        key_in[10],
        key_in[14],
        key_in[6],
        key_in[20],
        key_in[27],
        key_in[24]
      };
    end
  endfunction

  function [47:0] des_expand;
    input [31:0] right_in;
    begin
      des_expand = {
        right_in[0],
        right_in[31],
        right_in[30],
        right_in[29],
        right_in[28],
        right_in[27],
        right_in[28],
        right_in[27],
        right_in[26],
        right_in[25],
        right_in[24],
        right_in[23],
        right_in[24],
        right_in[23],
        right_in[22],
        right_in[21],
        right_in[20],
        right_in[19],
        right_in[20],
        right_in[19],
        right_in[18],
        right_in[17],
        right_in[16],
        right_in[15],
        right_in[16],
        right_in[15],
        right_in[14],
        right_in[13],
        right_in[12],
        right_in[11],
        right_in[12],
        right_in[11],
        right_in[10],
        right_in[9],
        right_in[8],
        right_in[7],
        right_in[8],
        right_in[7],
        right_in[6],
        right_in[5],
        right_in[4],
        right_in[3],
        right_in[4],
        right_in[3],
        right_in[2],
        right_in[1],
        right_in[0],
        right_in[31]
      };
    end
  endfunction

  function [31:0] des_p;
    input [31:0] p_in;
    begin
      des_p = {
        p_in[16],
        p_in[25],
        p_in[12],
        p_in[11],
        p_in[3],
        p_in[20],
        p_in[4],
        p_in[15],
        p_in[31],
        p_in[17],
        p_in[9],
        p_in[6],
        p_in[27],
        p_in[14],
        p_in[1],
        p_in[22],
        p_in[30],
        p_in[24],
        p_in[8],
        p_in[18],
        p_in[0],
        p_in[5],
        p_in[29],
        p_in[23],
        p_in[13],
        p_in[19],
        p_in[2],
        p_in[26],
        p_in[10],
        p_in[21],
        p_in[28],
        p_in[7]
      };
    end
  endfunction

  function [63:0] des_fp;
    input [63:0] fp_in;
    begin
      des_fp = {
        fp_in[24],
        fp_in[56],
        fp_in[16],
        fp_in[48],
        fp_in[8],
        fp_in[40],
        fp_in[0],
        fp_in[32],
        fp_in[25],
        fp_in[57],
        fp_in[17],
        fp_in[49],
        fp_in[9],
        fp_in[41],
        fp_in[1],
        fp_in[33],
        fp_in[26],
        fp_in[58],
        fp_in[18],
        fp_in[50],
        fp_in[10],
        fp_in[42],
        fp_in[2],
        fp_in[34],
        fp_in[27],
        fp_in[59],
        fp_in[19],
        fp_in[51],
        fp_in[11],
        fp_in[43],
        fp_in[3],
        fp_in[35],
        fp_in[28],
        fp_in[60],
        fp_in[20],
        fp_in[52],
        fp_in[12],
        fp_in[44],
        fp_in[4],
        fp_in[36],
        fp_in[29],
        fp_in[61],
        fp_in[21],
        fp_in[53],
        fp_in[13],
        fp_in[45],
        fp_in[5],
        fp_in[37],
        fp_in[30],
        fp_in[62],
        fp_in[22],
        fp_in[54],
        fp_in[14],
        fp_in[46],
        fp_in[6],
        fp_in[38],
        fp_in[31],
        fp_in[63],
        fp_in[23],
        fp_in[55],
        fp_in[15],
        fp_in[47],
        fp_in[7],
        fp_in[39]
      };
    end
  endfunction

  function [3:0] des_s1;
    input [5:0] box_in;
    reg [5:0] address;
    begin
      address = {box_in[5], box_in[0], box_in[4:1]};
      case (address)
        6'd0: des_s1 = 4'd14;
        6'd1: des_s1 = 4'd4;
        6'd2: des_s1 = 4'd13;
        6'd3: des_s1 = 4'd1;
        6'd4: des_s1 = 4'd2;
        6'd5: des_s1 = 4'd15;
        6'd6: des_s1 = 4'd11;
        6'd7: des_s1 = 4'd8;
        6'd8: des_s1 = 4'd3;
        6'd9: des_s1 = 4'd10;
        6'd10: des_s1 = 4'd6;
        6'd11: des_s1 = 4'd12;
        6'd12: des_s1 = 4'd5;
        6'd13: des_s1 = 4'd9;
        6'd14: des_s1 = 4'd0;
        6'd15: des_s1 = 4'd7;
        6'd16: des_s1 = 4'd0;
        6'd17: des_s1 = 4'd15;
        6'd18: des_s1 = 4'd7;
        6'd19: des_s1 = 4'd4;
        6'd20: des_s1 = 4'd14;
        6'd21: des_s1 = 4'd2;
        6'd22: des_s1 = 4'd13;
        6'd23: des_s1 = 4'd1;
        6'd24: des_s1 = 4'd10;
        6'd25: des_s1 = 4'd6;
        6'd26: des_s1 = 4'd12;
        6'd27: des_s1 = 4'd11;
        6'd28: des_s1 = 4'd9;
        6'd29: des_s1 = 4'd5;
        6'd30: des_s1 = 4'd3;
        6'd31: des_s1 = 4'd8;
        6'd32: des_s1 = 4'd4;
        6'd33: des_s1 = 4'd1;
        6'd34: des_s1 = 4'd14;
        6'd35: des_s1 = 4'd8;
        6'd36: des_s1 = 4'd13;
        6'd37: des_s1 = 4'd6;
        6'd38: des_s1 = 4'd2;
        6'd39: des_s1 = 4'd11;
        6'd40: des_s1 = 4'd15;
        6'd41: des_s1 = 4'd12;
        6'd42: des_s1 = 4'd9;
        6'd43: des_s1 = 4'd7;
        6'd44: des_s1 = 4'd3;
        6'd45: des_s1 = 4'd10;
        6'd46: des_s1 = 4'd5;
        6'd47: des_s1 = 4'd0;
        6'd48: des_s1 = 4'd15;
        6'd49: des_s1 = 4'd12;
        6'd50: des_s1 = 4'd8;
        6'd51: des_s1 = 4'd2;
        6'd52: des_s1 = 4'd4;
        6'd53: des_s1 = 4'd9;
        6'd54: des_s1 = 4'd1;
        6'd55: des_s1 = 4'd7;
        6'd56: des_s1 = 4'd5;
        6'd57: des_s1 = 4'd11;
        6'd58: des_s1 = 4'd3;
        6'd59: des_s1 = 4'd14;
        6'd60: des_s1 = 4'd10;
        6'd61: des_s1 = 4'd0;
        6'd62: des_s1 = 4'd6;
        6'd63: des_s1 = 4'd13;
        default: des_s1 = 4'd0;
      endcase
    end
  endfunction

  function [3:0] des_s2;
    input [5:0] box_in;
    reg [5:0] address;
    begin
      address = {box_in[5], box_in[0], box_in[4:1]};
      case (address)
        6'd0: des_s2 = 4'd15;
        6'd1: des_s2 = 4'd1;
        6'd2: des_s2 = 4'd8;
        6'd3: des_s2 = 4'd14;
        6'd4: des_s2 = 4'd6;
        6'd5: des_s2 = 4'd11;
        6'd6: des_s2 = 4'd3;
        6'd7: des_s2 = 4'd4;
        6'd8: des_s2 = 4'd9;
        6'd9: des_s2 = 4'd7;
        6'd10: des_s2 = 4'd2;
        6'd11: des_s2 = 4'd13;
        6'd12: des_s2 = 4'd12;
        6'd13: des_s2 = 4'd0;
        6'd14: des_s2 = 4'd5;
        6'd15: des_s2 = 4'd10;
        6'd16: des_s2 = 4'd3;
        6'd17: des_s2 = 4'd13;
        6'd18: des_s2 = 4'd4;
        6'd19: des_s2 = 4'd7;
        6'd20: des_s2 = 4'd15;
        6'd21: des_s2 = 4'd2;
        6'd22: des_s2 = 4'd8;
        6'd23: des_s2 = 4'd14;
        6'd24: des_s2 = 4'd12;
        6'd25: des_s2 = 4'd0;
        6'd26: des_s2 = 4'd1;
        6'd27: des_s2 = 4'd10;
        6'd28: des_s2 = 4'd6;
        6'd29: des_s2 = 4'd9;
        6'd30: des_s2 = 4'd11;
        6'd31: des_s2 = 4'd5;
        6'd32: des_s2 = 4'd0;
        6'd33: des_s2 = 4'd14;
        6'd34: des_s2 = 4'd7;
        6'd35: des_s2 = 4'd11;
        6'd36: des_s2 = 4'd10;
        6'd37: des_s2 = 4'd4;
        6'd38: des_s2 = 4'd13;
        6'd39: des_s2 = 4'd1;
        6'd40: des_s2 = 4'd5;
        6'd41: des_s2 = 4'd8;
        6'd42: des_s2 = 4'd12;
        6'd43: des_s2 = 4'd6;
        6'd44: des_s2 = 4'd9;
        6'd45: des_s2 = 4'd3;
        6'd46: des_s2 = 4'd2;
        6'd47: des_s2 = 4'd15;
        6'd48: des_s2 = 4'd13;
        6'd49: des_s2 = 4'd8;
        6'd50: des_s2 = 4'd10;
        6'd51: des_s2 = 4'd1;
        6'd52: des_s2 = 4'd3;
        6'd53: des_s2 = 4'd15;
        6'd54: des_s2 = 4'd4;
        6'd55: des_s2 = 4'd2;
        6'd56: des_s2 = 4'd11;
        6'd57: des_s2 = 4'd6;
        6'd58: des_s2 = 4'd7;
        6'd59: des_s2 = 4'd12;
        6'd60: des_s2 = 4'd0;
        6'd61: des_s2 = 4'd5;
        6'd62: des_s2 = 4'd14;
        6'd63: des_s2 = 4'd9;
        default: des_s2 = 4'd0;
      endcase
    end
  endfunction

  function [3:0] des_s3;
    input [5:0] box_in;
    reg [5:0] address;
    begin
      address = {box_in[5], box_in[0], box_in[4:1]};
      case (address)
        6'd0: des_s3 = 4'd10;
        6'd1: des_s3 = 4'd0;
        6'd2: des_s3 = 4'd9;
        6'd3: des_s3 = 4'd14;
        6'd4: des_s3 = 4'd6;
        6'd5: des_s3 = 4'd3;
        6'd6: des_s3 = 4'd15;
        6'd7: des_s3 = 4'd5;
        6'd8: des_s3 = 4'd1;
        6'd9: des_s3 = 4'd13;
        6'd10: des_s3 = 4'd12;
        6'd11: des_s3 = 4'd7;
        6'd12: des_s3 = 4'd11;
        6'd13: des_s3 = 4'd4;
        6'd14: des_s3 = 4'd2;
        6'd15: des_s3 = 4'd8;
        6'd16: des_s3 = 4'd13;
        6'd17: des_s3 = 4'd7;
        6'd18: des_s3 = 4'd0;
        6'd19: des_s3 = 4'd9;
        6'd20: des_s3 = 4'd3;
        6'd21: des_s3 = 4'd4;
        6'd22: des_s3 = 4'd6;
        6'd23: des_s3 = 4'd10;
        6'd24: des_s3 = 4'd2;
        6'd25: des_s3 = 4'd8;
        6'd26: des_s3 = 4'd5;
        6'd27: des_s3 = 4'd14;
        6'd28: des_s3 = 4'd12;
        6'd29: des_s3 = 4'd11;
        6'd30: des_s3 = 4'd15;
        6'd31: des_s3 = 4'd1;
        6'd32: des_s3 = 4'd13;
        6'd33: des_s3 = 4'd6;
        6'd34: des_s3 = 4'd4;
        6'd35: des_s3 = 4'd9;
        6'd36: des_s3 = 4'd8;
        6'd37: des_s3 = 4'd15;
        6'd38: des_s3 = 4'd3;
        6'd39: des_s3 = 4'd0;
        6'd40: des_s3 = 4'd11;
        6'd41: des_s3 = 4'd1;
        6'd42: des_s3 = 4'd2;
        6'd43: des_s3 = 4'd12;
        6'd44: des_s3 = 4'd5;
        6'd45: des_s3 = 4'd10;
        6'd46: des_s3 = 4'd14;
        6'd47: des_s3 = 4'd7;
        6'd48: des_s3 = 4'd1;
        6'd49: des_s3 = 4'd10;
        6'd50: des_s3 = 4'd13;
        6'd51: des_s3 = 4'd0;
        6'd52: des_s3 = 4'd6;
        6'd53: des_s3 = 4'd9;
        6'd54: des_s3 = 4'd8;
        6'd55: des_s3 = 4'd7;
        6'd56: des_s3 = 4'd4;
        6'd57: des_s3 = 4'd15;
        6'd58: des_s3 = 4'd14;
        6'd59: des_s3 = 4'd3;
        6'd60: des_s3 = 4'd11;
        6'd61: des_s3 = 4'd5;
        6'd62: des_s3 = 4'd2;
        6'd63: des_s3 = 4'd12;
        default: des_s3 = 4'd0;
      endcase
    end
  endfunction

  function [3:0] des_s4;
    input [5:0] box_in;
    reg [5:0] address;
    begin
      address = {box_in[5], box_in[0], box_in[4:1]};
      case (address)
        6'd0: des_s4 = 4'd7;
        6'd1: des_s4 = 4'd13;
        6'd2: des_s4 = 4'd14;
        6'd3: des_s4 = 4'd3;
        6'd4: des_s4 = 4'd0;
        6'd5: des_s4 = 4'd6;
        6'd6: des_s4 = 4'd9;
        6'd7: des_s4 = 4'd10;
        6'd8: des_s4 = 4'd1;
        6'd9: des_s4 = 4'd2;
        6'd10: des_s4 = 4'd8;
        6'd11: des_s4 = 4'd5;
        6'd12: des_s4 = 4'd11;
        6'd13: des_s4 = 4'd12;
        6'd14: des_s4 = 4'd4;
        6'd15: des_s4 = 4'd15;
        6'd16: des_s4 = 4'd13;
        6'd17: des_s4 = 4'd8;
        6'd18: des_s4 = 4'd11;
        6'd19: des_s4 = 4'd5;
        6'd20: des_s4 = 4'd6;
        6'd21: des_s4 = 4'd15;
        6'd22: des_s4 = 4'd0;
        6'd23: des_s4 = 4'd3;
        6'd24: des_s4 = 4'd4;
        6'd25: des_s4 = 4'd7;
        6'd26: des_s4 = 4'd2;
        6'd27: des_s4 = 4'd12;
        6'd28: des_s4 = 4'd1;
        6'd29: des_s4 = 4'd10;
        6'd30: des_s4 = 4'd14;
        6'd31: des_s4 = 4'd9;
        6'd32: des_s4 = 4'd10;
        6'd33: des_s4 = 4'd6;
        6'd34: des_s4 = 4'd9;
        6'd35: des_s4 = 4'd0;
        6'd36: des_s4 = 4'd12;
        6'd37: des_s4 = 4'd11;
        6'd38: des_s4 = 4'd7;
        6'd39: des_s4 = 4'd13;
        6'd40: des_s4 = 4'd15;
        6'd41: des_s4 = 4'd1;
        6'd42: des_s4 = 4'd3;
        6'd43: des_s4 = 4'd14;
        6'd44: des_s4 = 4'd5;
        6'd45: des_s4 = 4'd2;
        6'd46: des_s4 = 4'd8;
        6'd47: des_s4 = 4'd4;
        6'd48: des_s4 = 4'd3;
        6'd49: des_s4 = 4'd15;
        6'd50: des_s4 = 4'd0;
        6'd51: des_s4 = 4'd6;
        6'd52: des_s4 = 4'd10;
        6'd53: des_s4 = 4'd1;
        6'd54: des_s4 = 4'd13;
        6'd55: des_s4 = 4'd8;
        6'd56: des_s4 = 4'd9;
        6'd57: des_s4 = 4'd4;
        6'd58: des_s4 = 4'd5;
        6'd59: des_s4 = 4'd11;
        6'd60: des_s4 = 4'd12;
        6'd61: des_s4 = 4'd7;
        6'd62: des_s4 = 4'd2;
        6'd63: des_s4 = 4'd14;
        default: des_s4 = 4'd0;
      endcase
    end
  endfunction

  function [3:0] des_s5;
    input [5:0] box_in;
    reg [5:0] address;
    begin
      address = {box_in[5], box_in[0], box_in[4:1]};
      case (address)
        6'd0: des_s5 = 4'd2;
        6'd1: des_s5 = 4'd12;
        6'd2: des_s5 = 4'd4;
        6'd3: des_s5 = 4'd1;
        6'd4: des_s5 = 4'd7;
        6'd5: des_s5 = 4'd10;
        6'd6: des_s5 = 4'd11;
        6'd7: des_s5 = 4'd6;
        6'd8: des_s5 = 4'd8;
        6'd9: des_s5 = 4'd5;
        6'd10: des_s5 = 4'd3;
        6'd11: des_s5 = 4'd15;
        6'd12: des_s5 = 4'd13;
        6'd13: des_s5 = 4'd0;
        6'd14: des_s5 = 4'd14;
        6'd15: des_s5 = 4'd9;
        6'd16: des_s5 = 4'd14;
        6'd17: des_s5 = 4'd11;
        6'd18: des_s5 = 4'd2;
        6'd19: des_s5 = 4'd12;
        6'd20: des_s5 = 4'd4;
        6'd21: des_s5 = 4'd7;
        6'd22: des_s5 = 4'd13;
        6'd23: des_s5 = 4'd1;
        6'd24: des_s5 = 4'd5;
        6'd25: des_s5 = 4'd0;
        6'd26: des_s5 = 4'd15;
        6'd27: des_s5 = 4'd10;
        6'd28: des_s5 = 4'd3;
        6'd29: des_s5 = 4'd9;
        6'd30: des_s5 = 4'd8;
        6'd31: des_s5 = 4'd6;
        6'd32: des_s5 = 4'd4;
        6'd33: des_s5 = 4'd2;
        6'd34: des_s5 = 4'd1;
        6'd35: des_s5 = 4'd11;
        6'd36: des_s5 = 4'd10;
        6'd37: des_s5 = 4'd13;
        6'd38: des_s5 = 4'd7;
        6'd39: des_s5 = 4'd8;
        6'd40: des_s5 = 4'd15;
        6'd41: des_s5 = 4'd9;
        6'd42: des_s5 = 4'd12;
        6'd43: des_s5 = 4'd5;
        6'd44: des_s5 = 4'd6;
        6'd45: des_s5 = 4'd3;
        6'd46: des_s5 = 4'd0;
        6'd47: des_s5 = 4'd14;
        6'd48: des_s5 = 4'd11;
        6'd49: des_s5 = 4'd8;
        6'd50: des_s5 = 4'd12;
        6'd51: des_s5 = 4'd7;
        6'd52: des_s5 = 4'd1;
        6'd53: des_s5 = 4'd14;
        6'd54: des_s5 = 4'd2;
        6'd55: des_s5 = 4'd13;
        6'd56: des_s5 = 4'd6;
        6'd57: des_s5 = 4'd15;
        6'd58: des_s5 = 4'd0;
        6'd59: des_s5 = 4'd9;
        6'd60: des_s5 = 4'd10;
        6'd61: des_s5 = 4'd4;
        6'd62: des_s5 = 4'd5;
        6'd63: des_s5 = 4'd3;
        default: des_s5 = 4'd0;
      endcase
    end
  endfunction

  function [3:0] des_s6;
    input [5:0] box_in;
    reg [5:0] address;
    begin
      address = {box_in[5], box_in[0], box_in[4:1]};
      case (address)
        6'd0: des_s6 = 4'd12;
        6'd1: des_s6 = 4'd1;
        6'd2: des_s6 = 4'd10;
        6'd3: des_s6 = 4'd15;
        6'd4: des_s6 = 4'd9;
        6'd5: des_s6 = 4'd2;
        6'd6: des_s6 = 4'd6;
        6'd7: des_s6 = 4'd8;
        6'd8: des_s6 = 4'd0;
        6'd9: des_s6 = 4'd13;
        6'd10: des_s6 = 4'd3;
        6'd11: des_s6 = 4'd4;
        6'd12: des_s6 = 4'd14;
        6'd13: des_s6 = 4'd7;
        6'd14: des_s6 = 4'd5;
        6'd15: des_s6 = 4'd11;
        6'd16: des_s6 = 4'd10;
        6'd17: des_s6 = 4'd15;
        6'd18: des_s6 = 4'd4;
        6'd19: des_s6 = 4'd2;
        6'd20: des_s6 = 4'd7;
        6'd21: des_s6 = 4'd12;
        6'd22: des_s6 = 4'd9;
        6'd23: des_s6 = 4'd5;
        6'd24: des_s6 = 4'd6;
        6'd25: des_s6 = 4'd1;
        6'd26: des_s6 = 4'd13;
        6'd27: des_s6 = 4'd14;
        6'd28: des_s6 = 4'd0;
        6'd29: des_s6 = 4'd11;
        6'd30: des_s6 = 4'd3;
        6'd31: des_s6 = 4'd8;
        6'd32: des_s6 = 4'd9;
        6'd33: des_s6 = 4'd14;
        6'd34: des_s6 = 4'd15;
        6'd35: des_s6 = 4'd5;
        6'd36: des_s6 = 4'd2;
        6'd37: des_s6 = 4'd8;
        6'd38: des_s6 = 4'd12;
        6'd39: des_s6 = 4'd3;
        6'd40: des_s6 = 4'd7;
        6'd41: des_s6 = 4'd0;
        6'd42: des_s6 = 4'd4;
        6'd43: des_s6 = 4'd10;
        6'd44: des_s6 = 4'd1;
        6'd45: des_s6 = 4'd13;
        6'd46: des_s6 = 4'd11;
        6'd47: des_s6 = 4'd6;
        6'd48: des_s6 = 4'd4;
        6'd49: des_s6 = 4'd3;
        6'd50: des_s6 = 4'd2;
        6'd51: des_s6 = 4'd12;
        6'd52: des_s6 = 4'd9;
        6'd53: des_s6 = 4'd5;
        6'd54: des_s6 = 4'd15;
        6'd55: des_s6 = 4'd10;
        6'd56: des_s6 = 4'd11;
        6'd57: des_s6 = 4'd14;
        6'd58: des_s6 = 4'd1;
        6'd59: des_s6 = 4'd7;
        6'd60: des_s6 = 4'd6;
        6'd61: des_s6 = 4'd0;
        6'd62: des_s6 = 4'd8;
        6'd63: des_s6 = 4'd13;
        default: des_s6 = 4'd0;
      endcase
    end
  endfunction

  function [3:0] des_s7;
    input [5:0] box_in;
    reg [5:0] address;
    begin
      address = {box_in[5], box_in[0], box_in[4:1]};
      case (address)
        6'd0: des_s7 = 4'd4;
        6'd1: des_s7 = 4'd11;
        6'd2: des_s7 = 4'd2;
        6'd3: des_s7 = 4'd14;
        6'd4: des_s7 = 4'd15;
        6'd5: des_s7 = 4'd0;
        6'd6: des_s7 = 4'd8;
        6'd7: des_s7 = 4'd13;
        6'd8: des_s7 = 4'd3;
        6'd9: des_s7 = 4'd12;
        6'd10: des_s7 = 4'd9;
        6'd11: des_s7 = 4'd7;
        6'd12: des_s7 = 4'd5;
        6'd13: des_s7 = 4'd10;
        6'd14: des_s7 = 4'd6;
        6'd15: des_s7 = 4'd1;
        6'd16: des_s7 = 4'd13;
        6'd17: des_s7 = 4'd0;
        6'd18: des_s7 = 4'd11;
        6'd19: des_s7 = 4'd7;
        6'd20: des_s7 = 4'd4;
        6'd21: des_s7 = 4'd9;
        6'd22: des_s7 = 4'd1;
        6'd23: des_s7 = 4'd10;
        6'd24: des_s7 = 4'd14;
        6'd25: des_s7 = 4'd3;
        6'd26: des_s7 = 4'd5;
        6'd27: des_s7 = 4'd12;
        6'd28: des_s7 = 4'd2;
        6'd29: des_s7 = 4'd15;
        6'd30: des_s7 = 4'd8;
        6'd31: des_s7 = 4'd6;
        6'd32: des_s7 = 4'd1;
        6'd33: des_s7 = 4'd4;
        6'd34: des_s7 = 4'd11;
        6'd35: des_s7 = 4'd13;
        6'd36: des_s7 = 4'd12;
        6'd37: des_s7 = 4'd3;
        6'd38: des_s7 = 4'd7;
        6'd39: des_s7 = 4'd14;
        6'd40: des_s7 = 4'd10;
        6'd41: des_s7 = 4'd15;
        6'd42: des_s7 = 4'd6;
        6'd43: des_s7 = 4'd8;
        6'd44: des_s7 = 4'd0;
        6'd45: des_s7 = 4'd5;
        6'd46: des_s7 = 4'd9;
        6'd47: des_s7 = 4'd2;
        6'd48: des_s7 = 4'd6;
        6'd49: des_s7 = 4'd11;
        6'd50: des_s7 = 4'd13;
        6'd51: des_s7 = 4'd8;
        6'd52: des_s7 = 4'd1;
        6'd53: des_s7 = 4'd4;
        6'd54: des_s7 = 4'd10;
        6'd55: des_s7 = 4'd7;
        6'd56: des_s7 = 4'd9;
        6'd57: des_s7 = 4'd5;
        6'd58: des_s7 = 4'd0;
        6'd59: des_s7 = 4'd15;
        6'd60: des_s7 = 4'd14;
        6'd61: des_s7 = 4'd2;
        6'd62: des_s7 = 4'd3;
        6'd63: des_s7 = 4'd12;
        default: des_s7 = 4'd0;
      endcase
    end
  endfunction

  function [3:0] des_s8;
    input [5:0] box_in;
    reg [5:0] address;
    begin
      address = {box_in[5], box_in[0], box_in[4:1]};
      case (address)
        6'd0: des_s8 = 4'd13;
        6'd1: des_s8 = 4'd2;
        6'd2: des_s8 = 4'd8;
        6'd3: des_s8 = 4'd4;
        6'd4: des_s8 = 4'd6;
        6'd5: des_s8 = 4'd15;
        6'd6: des_s8 = 4'd11;
        6'd7: des_s8 = 4'd1;
        6'd8: des_s8 = 4'd10;
        6'd9: des_s8 = 4'd9;
        6'd10: des_s8 = 4'd3;
        6'd11: des_s8 = 4'd14;
        6'd12: des_s8 = 4'd5;
        6'd13: des_s8 = 4'd0;
        6'd14: des_s8 = 4'd12;
        6'd15: des_s8 = 4'd7;
        6'd16: des_s8 = 4'd1;
        6'd17: des_s8 = 4'd15;
        6'd18: des_s8 = 4'd13;
        6'd19: des_s8 = 4'd8;
        6'd20: des_s8 = 4'd10;
        6'd21: des_s8 = 4'd3;
        6'd22: des_s8 = 4'd7;
        6'd23: des_s8 = 4'd4;
        6'd24: des_s8 = 4'd12;
        6'd25: des_s8 = 4'd5;
        6'd26: des_s8 = 4'd6;
        6'd27: des_s8 = 4'd11;
        6'd28: des_s8 = 4'd0;
        6'd29: des_s8 = 4'd14;
        6'd30: des_s8 = 4'd9;
        6'd31: des_s8 = 4'd2;
        6'd32: des_s8 = 4'd7;
        6'd33: des_s8 = 4'd11;
        6'd34: des_s8 = 4'd4;
        6'd35: des_s8 = 4'd1;
        6'd36: des_s8 = 4'd9;
        6'd37: des_s8 = 4'd12;
        6'd38: des_s8 = 4'd14;
        6'd39: des_s8 = 4'd2;
        6'd40: des_s8 = 4'd0;
        6'd41: des_s8 = 4'd6;
        6'd42: des_s8 = 4'd10;
        6'd43: des_s8 = 4'd13;
        6'd44: des_s8 = 4'd15;
        6'd45: des_s8 = 4'd3;
        6'd46: des_s8 = 4'd5;
        6'd47: des_s8 = 4'd8;
        6'd48: des_s8 = 4'd2;
        6'd49: des_s8 = 4'd1;
        6'd50: des_s8 = 4'd14;
        6'd51: des_s8 = 4'd7;
        6'd52: des_s8 = 4'd4;
        6'd53: des_s8 = 4'd10;
        6'd54: des_s8 = 4'd8;
        6'd55: des_s8 = 4'd13;
        6'd56: des_s8 = 4'd15;
        6'd57: des_s8 = 4'd12;
        6'd58: des_s8 = 4'd9;
        6'd59: des_s8 = 4'd0;
        6'd60: des_s8 = 4'd3;
        6'd61: des_s8 = 4'd5;
        6'd62: des_s8 = 4'd6;
        6'd63: des_s8 = 4'd11;
        default: des_s8 = 4'd0;
      endcase
    end
  endfunction

endmodule

