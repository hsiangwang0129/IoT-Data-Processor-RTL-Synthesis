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

  localparam [4:0] WAIT_DATA = 5'd0,
                   LOAD_INPUT = 5'd1,
                   INIT = 5'd2,
                   ROUND = 5'd3,
                   OUTPUT = 5'd4,
                   F3_CUM_INIT = 5'd5,
                   F3_CUM_BUILD = 5'd6,
                   F3_ENCODE_INIT = 5'd7,
                   F3_UPDATE_INTERVAL = 5'd8,
                   F3_RENORMALIZE = 5'd9,
                   F3_EMIT_BASE = 5'd10,
                   F3_EMIT_PENDING = 5'd11,
                   F3_NEXT_SYMBOL = 5'd12,
                   F3_FINALIZE = 5'd13,
                   F3_PAD = 5'd14,
                   F3_OUTPUT = 5'd15,
                   F3_BLOCK_DONE = 5'd16,
                   F4_DECODE_INIT = 5'd17,
                   F4_PC_INIT = 5'd18,
                   F4_PC_DIV = 5'd19,
                   F4_SEARCH_INIT = 5'd20,
                   F4_SEARCH_SYMBOL = 5'd21,
                   F4_UPDATE_INTERVAL = 5'd22,
                   F4_RENORMALIZE = 5'd23,
                   F4_NEXT_SYMBOL = 5'd24;

  reg [4:0] state;
  reg [3:0] byte_count;
  reg [4:0] round_number;
  reg [127:0] data_buf;
  reg [63:0] main_key;
  reg [63:0] des_block;
  reg [31:0] left_reg;
  reg [31:0] right_reg;
  reg [27:0] key_left;
  reg [27:0] key_right;

  reg [1023:0] f3_input_buf;
  reg [1023:0] encoded_buf;
  reg [6:0] byte_index;
  reg [8:0] frequency [0:15];
  reg [8:0] cumulative [0:16];
  reg [3:0] cumulative_index;
  reg [7:0] symbol_index;
  reg [15:0] low;
  reg [15:0] high;
  reg [10:0] pending_count;
  reg [10:0] output_bit_count;
  reg [2:0] output_word_index;
  reg emit_bit;
  reg [7:0] f4_byte_index;
  reg [15:0] code;
  reg [15:0] code_probability;
  reg [10:0] next_bit_index;
  reg [3:0] search_symbol;
  reg [32:0] divide_dividend;
  reg [16:0] divide_divisor;
  reg [16:0] divide_remainder;
  reg [16:0] divide_quotient;
  reg [5:0] divide_bit_count;
  integer frequency_index;
  integer initial_bit_index;

  wire [3:0] current_symbol;
  wire [16:0] range;
  wire [25:0] lower_product;
  wire [25:0] upper_product;
  wire [16:0] lower_offset;
  wire [16:0] upper_offset;
  wire [16:0] code_distance;
  wire [17:0] divide_trial;
  wire [16:0] symbol_lower;
  wire [16:0] symbol_upper;
  wire next_code_bit;

  wire [63:0] ip_block;
  wire [31:0] left_initial;
  wire [31:0] right_initial;
  wire [55:0] pc1_key;
  wire [27:0] key_left_initial;
  wire [27:0] key_right_initial;
  wire decrypt_mode;
  wire decrypt_shift_one;
  wire [27:0] key_left_decrypt_next;
  wire [27:0] key_right_decrypt_next;
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

    assign current_symbol = (fn_sel == 3'd4)
      ? search_symbol : f3_input_buf[(symbol_index * 4) +: 4];
  assign range = {1'b0, high} - {1'b0, low} + 17'd1;
  assign lower_product = range * cumulative[current_symbol];
  assign upper_product = range * cumulative[current_symbol + 5'd1];
  assign lower_offset = lower_product >> 8;
  assign upper_offset = upper_product >> 8;
    assign code_distance = {1'b0, code} - {1'b0, low} + 17'd1;
    assign divide_trial = {divide_remainder, divide_dividend[32]};
    assign symbol_lower = {cumulative[search_symbol], 8'd0};
    assign symbol_upper = {cumulative[search_symbol + 5'd1], 8'd0};
    assign next_code_bit = (next_bit_index < 11'd1024)
      ? f3_input_buf[next_bit_index] : 1'b1;

  assign ip_block = des_ip(des_block);
  assign left_initial = ip_block[63:32];
  assign right_initial = ip_block[31:0];
  assign pc1_key = des_pc1(main_key);
  assign key_left_initial = pc1_key[55:28];
  assign key_right_initial = pc1_key[27:0];

    assign decrypt_mode = (fn_sel == 3'd2);
    assign decrypt_shift_one = (round_number == 5'd1) ||
      (round_number == 5'd8) || (round_number == 5'd15);
    assign key_left_decrypt_next = decrypt_shift_one
      ? {key_left[0], key_left[27:1]}
      : {key_left[1:0], key_left[27:2]};
    assign key_right_decrypt_next = decrypt_shift_one
      ? {key_right[0], key_right[27:1]}
      : {key_right[1:0], key_right[27:2]};

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
    assign round_key = des_pc2(decrypt_mode
      ? {key_left, key_right}
      : {key_left_rotated, key_right_rotated});

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
      f3_input_buf <= 1024'd0;
      encoded_buf <= 1024'd0;
      byte_index <= 7'd0;
      cumulative_index <= 4'd0;
      symbol_index <= 8'd0;
      low <= 16'h0000;
      high <= 16'hFFFF;
      pending_count <= 11'd0;
      output_bit_count <= 11'd0;
      output_word_index <= 3'd0;
      emit_bit <= 1'b0;
      f4_byte_index <= 8'd0;
      code <= 16'd0;
      code_probability <= 16'd0;
      next_bit_index <= 11'd16;
      search_symbol <= 4'd0;
      divide_dividend <= 33'd0;
      divide_divisor <= 17'd0;
      divide_remainder <= 17'd0;
      divide_quotient <= 17'd0;
      divide_bit_count <= 6'd0;
      for (frequency_index = 0; frequency_index < 16;
           frequency_index = frequency_index + 1) begin
        frequency[frequency_index] <= 9'd0;
        cumulative[frequency_index] <= 9'd0;
      end
      cumulative[16] <= 9'd0;
      busy <= 1'b0;
      valid <= 1'b0;
      iot_out <= 128'd0;
    end else begin
      valid <= 1'b0;
      case (state)
        WAIT_DATA: begin
          if (in_en && ((fn_sel == 3'd1) || (fn_sel == 3'd2))) begin
            data_buf[(byte_count*8)+:8] <= iot_in;
            if (byte_count == 4'd14) busy <= 1'b1;
            if (byte_count == 4'd15) begin
              byte_count <= 4'd0;
              state <= LOAD_INPUT;
            end else begin
              byte_count <= byte_count + 4'd1;
            end
          end else if (in_en && (fn_sel == 3'd3)) begin
            f3_input_buf[(byte_index * 8) +: 8] <= iot_in;
            if (iot_in[3:0] == iot_in[7:4]) begin
              frequency[iot_in[3:0]] <= frequency[iot_in[3:0]] + 9'd2;
            end else begin
              frequency[iot_in[3:0]] <= frequency[iot_in[3:0]] + 9'd1;
              frequency[iot_in[7:4]] <= frequency[iot_in[7:4]] + 9'd1;
            end
            if (byte_index == 7'd126)
              busy <= 1'b1;
            if (byte_index == 7'd127) begin
              byte_index <= 7'd0;
              state <= F3_CUM_INIT;
            end else begin
              byte_index <= byte_index + 7'd1;
            end
          end else if (in_en && (fn_sel == 3'd4)) begin
            if (f4_byte_index < 8'd16) begin
              frequency[f4_byte_index[3:0]] <= {1'b0, iot_in};
            end else begin
              f3_input_buf[((f4_byte_index - 8'd16) * 8) +: 8] <= iot_in;
            end
            if (f4_byte_index == 8'd142)
              busy <= 1'b1;
            if (f4_byte_index == 8'd143) begin
              f4_byte_index <= 8'd0;
              state <= F3_CUM_INIT;
            end else begin
              f4_byte_index <= f4_byte_index + 8'd1;
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
          if (decrypt_mode) begin
            if (round_number != 5'd16) begin
              key_left <= key_left_decrypt_next;
              key_right <= key_right_decrypt_next;
            end
          end else begin
            key_left <= key_left_rotated;
            key_right <= key_right_rotated;
          end
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
        F3_CUM_INIT: begin
          cumulative[0] <= 9'd0;
          cumulative_index <= 4'd0;
          state <= F3_CUM_BUILD;
        end
        F3_CUM_BUILD: begin
          cumulative[cumulative_index + 5'd1]
              <= cumulative[cumulative_index] + frequency[cumulative_index];
          if (cumulative_index == 4'd15) begin
            state <= (fn_sel == 3'd4) ? F4_DECODE_INIT : F3_ENCODE_INIT;
          end else begin
            cumulative_index <= cumulative_index + 4'd1;
          end
        end
        F3_ENCODE_INIT: begin
          low <= 16'h0000;
          high <= 16'hFFFF;
          symbol_index <= 8'd0;
          pending_count <= 11'd0;
          output_bit_count <= 11'd0;
          output_word_index <= 3'd0;
          emit_bit <= 1'b0;
          state <= F3_UPDATE_INTERVAL;
        end
        F3_UPDATE_INTERVAL: begin
          low <= {1'b0, low} + lower_offset;
          high <= {1'b0, low} + upper_offset - 17'd1;
          state <= F3_RENORMALIZE;
        end
        F3_RENORMALIZE: begin
          if (high < 16'h8000) begin
            emit_bit <= 1'b0;
            low <= {low[14:0], 1'b0};
            high <= {high[14:0], 1'b1};
            state <= F3_EMIT_BASE;
          end else if (low >= 16'h8000) begin
            emit_bit <= 1'b1;
            low <= {low[14:0], 1'b0};
            high <= {high[14:0], 1'b1};
            state <= F3_EMIT_BASE;
          end else if ((low >= 16'h4000) && (high < 16'hC000)) begin
            pending_count <= pending_count + 11'd1;
            low <= {low[15], low[13:0], 1'b0};
            high <= {high[15], high[13:0], 1'b1};
          end else begin
            state <= F3_NEXT_SYMBOL;
          end
        end
        F3_EMIT_BASE: begin
          if (output_bit_count < 11'd1024) begin
            encoded_buf[output_bit_count] <= emit_bit;
            output_bit_count <= output_bit_count + 11'd1;
          end
          state <= F3_EMIT_PENDING;
        end
        F3_EMIT_PENDING: begin
          if (pending_count != 11'd0) begin
            if (output_bit_count < 11'd1024) begin
              encoded_buf[output_bit_count] <= ~emit_bit;
              output_bit_count <= output_bit_count + 11'd1;
            end
            pending_count <= pending_count - 11'd1;
          end else begin
            state <= F3_RENORMALIZE;
          end
        end
        F3_NEXT_SYMBOL: begin
          if (symbol_index == 8'd255) begin
            state <= F3_FINALIZE;
          end else begin
            symbol_index <= symbol_index + 8'd1;
            state <= F3_UPDATE_INTERVAL;
          end
        end
        F3_FINALIZE: begin
          if (output_bit_count < 11'd1024) begin
            encoded_buf[output_bit_count] <= 1'b0;
            output_bit_count <= output_bit_count + 11'd1;
          end
          state <= F3_PAD;
        end
        F3_PAD: begin
          if (output_bit_count < 11'd1024) begin
            encoded_buf[output_bit_count] <= 1'b1;
            output_bit_count <= output_bit_count + 11'd1;
          end else begin
            pending_count <= 11'd0;
            output_word_index <= 3'd0;
            state <= F3_OUTPUT;
          end
        end
        F3_OUTPUT: begin
          iot_out <= encoded_buf[(output_word_index * 128) +: 128];
          valid <= 1'b1;
          if (output_word_index == 3'd7) begin
            state <= F3_BLOCK_DONE;
          end else begin
            output_word_index <= output_word_index + 3'd1;
          end
        end
        F3_BLOCK_DONE: begin
          for (frequency_index = 0; frequency_index < 16;
               frequency_index = frequency_index + 1) begin
            frequency[frequency_index] <= 9'd0;
          end
          byte_index <= 7'd0;
          f4_byte_index <= 8'd0;
          busy <= 1'b0;
          state <= WAIT_DATA;
        end
        F4_DECODE_INIT: begin
          low <= 16'h0000;
          high <= 16'hFFFF;
          symbol_index <= 8'd0;
          output_word_index <= 3'd0;
          next_bit_index <= 11'd16;
          for (initial_bit_index = 0; initial_bit_index < 16;
               initial_bit_index = initial_bit_index + 1) begin
            code[15 - initial_bit_index] <= f3_input_buf[initial_bit_index];
          end
          state <= F4_PC_INIT;
        end
        F4_PC_INIT: begin
          divide_dividend <= {code_distance, 16'd0};
          divide_divisor <= range;
          divide_remainder <= 17'd0;
          divide_quotient <= 17'd0;
          divide_bit_count <= 6'd0;
          state <= F4_PC_DIV;
        end
        F4_PC_DIV: begin
          divide_dividend <= {divide_dividend[31:0], 1'b0};
          if (divide_trial >= {1'b0, divide_divisor}) begin
            divide_remainder <= divide_trial - {1'b0, divide_divisor};
            divide_quotient <= {divide_quotient[15:0], 1'b1};
          end else begin
            divide_remainder <= divide_trial[16:0];
            divide_quotient <= {divide_quotient[15:0], 1'b0};
          end
          if (divide_bit_count == 6'd32) begin
            state <= F4_SEARCH_INIT;
          end else begin
            divide_bit_count <= divide_bit_count + 6'd1;
          end
        end
        F4_SEARCH_INIT: begin
          code_probability <= divide_quotient[15:0];
          search_symbol <= 4'd0;
          state <= F4_SEARCH_SYMBOL;
        end
        F4_SEARCH_SYMBOL: begin
          if ((symbol_lower <= {1'b0, code_probability}) &&
              ({1'b0, code_probability} < symbol_upper)) begin
            encoded_buf[(symbol_index * 4) +: 4] <= search_symbol;
            state <= F4_UPDATE_INTERVAL;
          end else if (search_symbol != 4'd15) begin
            search_symbol <= search_symbol + 4'd1;
          end
        end
        F4_UPDATE_INTERVAL: begin
          low <= {1'b0, low} + lower_offset;
          high <= {1'b0, low} + upper_offset - 17'd1;
          state <= F4_RENORMALIZE;
        end
        F4_RENORMALIZE: begin
          if ((high < 16'h8000) || (low >= 16'h8000)) begin
            low <= {low[14:0], 1'b0};
            high <= {high[14:0], 1'b1};
            code <= {code[14:0], next_code_bit};
            if (next_bit_index < 11'd1024)
              next_bit_index <= next_bit_index + 11'd1;
          end else if ((low >= 16'h4000) && (high < 16'hC000)) begin
            low <= {low[15], low[13:0], 1'b0};
            high <= {high[15], high[13:0], 1'b1};
            code <= {code[15], code[13:0], next_code_bit};
            if (next_bit_index < 11'd1024)
              next_bit_index <= next_bit_index + 11'd1;
          end else begin
            state <= F4_NEXT_SYMBOL;
          end
        end
        F4_NEXT_SYMBOL: begin
          if (symbol_index == 8'd255) begin
            state <= F3_OUTPUT;
          end else begin
            symbol_index <= symbol_index + 8'd1;
            state <= F4_PC_INIT;
          end
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

