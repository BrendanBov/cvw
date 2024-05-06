///////////////////////////////////////////
// cacherand.sv
//
// Written: Brendan Bovenschen brendanbovenschen03@gmail.com Landon Fox landon.fox@okstate.edu
// Created: 24 April 2024
// Modified: 24 April 2024
//
// Purpose: Implements pseudo random replacemet.
//
////////////////////////////////////////////////////////////////////////////////////////////////

module cacheLFSR
  #(parameter NUMWAYS = 4, SETLEN = 9, OFFSETLEN = 5, NUMLINES = 128) (
  input  logic                clk, 
  input  logic                reset,
  input  logic                FlushStage,
  input  logic [NUMWAYS-1:0]  ValidWay,        // Which ways for a particular set are valid, ignores tag
  input  logic                LRUWriteEn,      // Update the LFSR state
  output logic [NUMWAYS-1:0]  VictimWay        // LFSR selects a victim to evict
);

    localparam                           LOGNUMWAYS = $clog2(NUMWAYS);

    logic AllValid;
    logic RegEnable;

    logic [NUMWAYS-1:0] FirstZero;
    logic [LOGNUMWAYS-1:0] FirstZeroWay;
    logic [LOGNUMWAYS-1:0] VictimWayEnc;

    logic [LOGNUMWAYS+1:0] next;
    logic [LOGNUMWAYS+1:0] curr;

    logic [LOGNUMWAYS+1:0] val;

    assign AllValid = &ValidWay;
    assign RegEnable = !FlushStage & LRUWriteEn;

    assign val[0] = 1'b1;
    assign val[LOGNUMWAYS+1:1] = '0;


    priorityonehot #(NUMWAYS) FirstZeroEncoder(~ValidWay, FirstZero);
    binencoder #(NUMWAYS) FirstZeroWayEncoder(FirstZero, FirstZeroWay);

    // On a miss we need to ignore HitWay and derive the new replacement bits with the VictimWay.
    mux2 #(LOGNUMWAYS) WayMuxEnc(FirstZeroWay, curr[LOGNUMWAYS-1:0], AllValid, VictimWayEnc);

    decoder #(LOGNUMWAYS) decoder (VictimWayEnc, VictimWay);

    flopenl #(LOGNUMWAYS+2) LFSR(clk,reset,LRUWriteEn,next,val,curr);

    assign next[LOGNUMWAYS:0] = curr[LOGNUMWAYS+1:1];

    if(NUMWAYS == 2) begin
      assign next[2] = curr[2] ^ curr[0]; //mask = 101
    end
    else if(NUMWAYS == 4) begin
      assign next[3] = curr[3] ^ curr[0]; //mask = 1001
    end
    else if(NUMWAYS == 8) begin
      assign next[4] = curr[4] ^ curr[3] ^ curr[2] ^ curr[0]; //mask = 1_1101
    end
    else if(NUMWAYS == 16) begin
      assign next[5] = curr[5] ^ curr[4] ^ curr[2] ^ curr[1]; //mask = 11_0110
    end
    else if(NUMWAYS == 32) begin
      assign next[6] = curr[6] ^ curr[5] ^ curr[3] ^ curr[0]; //mask = 110_1001
    end
    else if(NUMWAYS == 64) begin
      assign next[7] = curr[7] ^ curr[5] ^ curr[2] ^ curr[1]; //mask = 1010_0110
    end
    else if(NUMWAYS == 128) begin
      assign next[8] = curr[8] ^ curr[6] ^ curr[5] ^ curr[4] ^ curr[3] ^ curr[2]; //mask = 1_0111_1100
    end


endmodule //cacheLFSR
