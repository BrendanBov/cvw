module testbenchLFSR();

    logic clock;
    logic reset;
    logic FlushStage;
    logic [128-1:0]  ValidWay;
    logic LFSRWriteEn;
    logic [128-1:0]  VictimWay;

    // TESTBENCH LOGIC
    logic [31:0] rd1exp, rd2exp;        // expected values
    logic [31:0] vectornum, errors;     // store vector position and number of errors
    logic [123:0] testvectors[10000:0]; // store all test vectors


    cacheLFSR #(128) cache(clock, reset, FlushStage, ValidWay, LFSRWriteEn, VictimWay);

    // Setup the clock to toggle every 1 time units 
   initial 
     begin	
	clock = 1'b1;
	forever #5 clock = ~clock;
     if(VictimWay == 1'b1) $stop;
     end

endmodule