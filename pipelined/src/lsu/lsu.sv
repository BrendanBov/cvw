///////////////////////////////////////////
// lsu.sv
//
// Written: David_Harris@hmc.edu 9 January 2021
// Modified: 
//
// Purpose: Load/Store Unit 
//          Top level of the memory-stage hart logic
//          Contains data cache, DTLB, subword read/write datapath, interface to external bus
// 
// A component of the Wally configurable RISC-V project.
// 
// Copyright (C) 2021 Harvey Mudd College & Oklahoma State University
//
// MIT LICENSE
// Permission is hereby granted, free of charge, to any person obtaining a copy of this 
// software and associated documentation files (the "Software"), to deal in the Software 
// without restriction, including without limitation the rights to use, copy, modify, merge, 
// publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons 
// to whom the Software is furnished to do so, subject to the following conditions:
//
//   The above copyright notice and this permission notice shall be included in all copies or 
//   substantial portions of the Software.
//
//   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, 
//   INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR 
//   PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS 
//   BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, 
//   TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE 
//   OR OTHER DEALINGS IN THE SOFTWARE.
////////////////////////////////////////////////////////////////////////////////////////////////

`include "wally-config.vh"

module lsu (
   input logic 				   clk, reset,
   input logic 				   StallM, FlushM, StallW, FlushW,
   output logic 			   LSUStallM,
   // connected to cpu (controls)
   input logic [1:0] 		   MemRWM,
   input logic [2:0] 		   Funct3M,
   input logic [6:0] 		   Funct7M, 
   input logic [1:0] 		   AtomicM,
   input logic                 TrapM,
   input logic 				   FlushDCacheM,
   output logic 			   CommittedM, 
   output logic 			   SquashSCW,
   output logic 			   DCacheMiss,
   output logic 			   DCacheAccess,
   // address and write data
   input logic [`XLEN-1:0] 	   IEUAdrE,
   (* mark_debug = "true" *)output logic [`XLEN-1:0]    IEUAdrM,
   input logic [`XLEN-1:0] 	   WriteDataM, 
   output logic [`XLEN-1:0]    ReadDataM,
   // cpu privilege
   input logic [1:0] 		   PrivilegeModeW,
   input logic 				   DTLBFlushM,
   // faults
   output logic 			   DTLBLoadPageFaultM, DTLBStorePageFaultM,
   output logic 			   LoadMisalignedFaultM, LoadAccessFaultM,
   // cpu hazard unit (trap)
   output logic 			   StoreMisalignedFaultM, StoreAccessFaultM,
   // connect to ahb
(* mark_debug = "true" *)   output logic [`PA_BITS-1:0] LSUBusAdr,
(* mark_debug = "true" *)   output logic 			   LSUBusRead, 
(* mark_debug = "true" *)   output logic 			   LSUBusWrite,
(* mark_debug = "true" *)   input logic 				   LSUBusAck,
(* mark_debug = "true" *)   input logic [`XLEN-1:0] 	   LSUBusHRDATA,
(* mark_debug = "true" *)   output logic [`XLEN-1:0]    LSUBusHWDATA,
(* mark_debug = "true" *)   output logic [2:0] 		   LSUBusSize, 
   // page table walker
   input logic [`XLEN-1:0] 	   SATP_REGW, // from csr
   input logic 				   STATUS_MXR, STATUS_SUM, STATUS_MPRV,
   input logic [1:0] 		   STATUS_MPP,
   input logic [`XLEN-1:0] 	   PCF,
   input logic 				   ITLBMissF,
   output logic [`XLEN-1:0]    PTE,
   output logic [1:0] 		   PageType,
   output logic 			   ITLBWriteF,
   input 					   var logic [7:0] PMPCFG_ARRAY_REGW[`PMP_ENTRIES-1:0],
   input 					   var logic [`XLEN-1:0] PMPADDR_ARRAY_REGW[`PMP_ENTRIES-1:0] // *** this one especially has a large note attached to it in pmpchecker.
  );

  logic 					   DTLBPageFaultM;
  logic [`PA_BITS-1:0] 		   LSUPAdrM;  // from mmu to dcache
  logic [`XLEN+1:0] 		   IEUAdrExtM;
  logic 					   DTLBMissM;
  logic 					   DTLBWriteM;
  logic [1:0] 				   LSURWM;
  logic [1:0] 				   PreLSURWM;
  logic [2:0] 				   LSUFunct3M;
  logic [6:0] 				   LSUFunct7M;
  logic [1:0] 				   LSUAtomicM;
(* mark_debug = "true" *)  logic [`PA_BITS-1:0] 		   PreLSUPAdrM, LocalLSUBusAdr;
  logic [11:0] 				   PreLSUAdrE, LSUAdrE;  
  logic 					   CPUBusy;
  logic 					   MemReadM;
  logic 					   DCacheStallM;
  logic 					   CacheableM;
  logic 					   SelHPTW;
  logic 					   BusStall;
  logic 					   InterlockStall;
  logic 					   IgnoreRequest;
  logic 					   BusCommittedM, DCacheCommittedM;

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // HPTW and Interlock FSM (only needed if VM supported)
  // MMU include PMP and is needed if any privileged supported
  ////////////////////////////////////////////////////////////////////////////////////////////////

  flopenrc #(`XLEN) AddressMReg(clk, reset, FlushM, ~StallM, IEUAdrE, IEUAdrM);
  assign IEUAdrExtM = {2'b00, IEUAdrM}; 
 
  if(`MEM_VIRTMEM) begin : MEM_VIRTMEM
    logic 					   AnyCPUReqM;
    logic [`PA_BITS-1:0] 		   HPTWAdr;
    logic 					   HPTWRead;
    logic [2:0] 				   HPTWSize;
    logic 					   SelReplayCPURequest;

    assign AnyCPUReqM = (|MemRWM) | (|AtomicM);

    interlockfsm interlockfsm (.clk, .reset, .AnyCPUReqM, .ITLBMissF, .ITLBWriteF,
    .DTLBMissM, .DTLBWriteM, .TrapM, .DCacheStallM,
    .InterlockStall, .SelReplayCPURequest, .SelHPTW,
    .IgnoreRequest);
    
    hptw hptw(.clk, .reset, .SATP_REGW, .PCF, .IEUAdrM,
        .ITLBMissF(ITLBMissF & ~TrapM),
        .DTLBMissM(DTLBMissM & ~TrapM),
        .PTE, .PageType, .ITLBWriteF, .DTLBWriteM,
        .HPTWReadPTE(ReadDataM),
        .DCacheStallM, .HPTWAdr, .HPTWRead, .HPTWSize);

    // arbiter between IEU and hptw
    
    // multiplex the outputs to LSU
    mux2 #(2) rwmux(MemRWM, {HPTWRead, 1'b0}, SelHPTW, PreLSURWM);
    mux2 #(3) sizemux(Funct3M, HPTWSize, SelHPTW, LSUFunct3M);
    mux2 #(7) funct7mux(Funct7M, 7'b0, SelHPTW, LSUFunct7M);    
    mux2 #(2) atomicmux(AtomicM, 2'b00, SelHPTW, LSUAtomicM);
    mux2 #(12) adremux(IEUAdrE[11:0], HPTWAdr[11:0], SelHPTW, PreLSUAdrE);
    // When replaying CPU memory request after PTW select the IEUAdrM for correct address.
    assign LSUAdrE = SelReplayCPURequest ? IEUAdrM[11:0] : PreLSUAdrE;
   
    mux2 #(`PA_BITS) lsupadrmux(IEUAdrExtM[`PA_BITS-1:0], HPTWAdr, SelHPTW, PreLSUPAdrM);

    // always block interrupts when using the hardware page table walker.
    assign CPUBusy = StallW & ~SelHPTW;
    
    // Specify which type of page fault is occurring
    assign DTLBLoadPageFaultM = DTLBPageFaultM & PreLSURWM[1];
    assign DTLBStorePageFaultM = DTLBPageFaultM & PreLSURWM[0];
  end // if (`MEM_VIRTMEM)
  else begin
    assign {InterlockStall, SelHPTW, IgnoreRequest, PTE, PageType, DTLBWriteM, ITLBWriteF} = '0;
    assign {DTLBLoadPageFaultM, DTLBStorePageFaultM} = '0;
    assign CPUBusy = StallW;
    assign LSUAdrE = PreLSUAdrE; assign LSUFunct3M = Funct3M;  assign LSUFunct7M = Funct7M; assign LSUAtomicM = AtomicM;
    assign PreLSURWM = MemRWM; assign PreLSUAdrE = IEUAdrE[11:0]; assign PreLSUPAdrM = IEUAdrExtM;
   end


  // **** look into this confusing signal.
  // This signal is confusing.  CommittedM tells the CPU's trap unit the current instruction
  // in the memory stage is a memory operaton and that memory operation is either completed
  // or is partially executed.  This signal is only low for the first cycle of a memory
  // operation.
  // **** I think there is also a bug here.  Data cache misses and TLB misses both
  // set this bit in the first cycle.  It is not strickly wrong, but it may be better
  // to flush the memory operation at that time.
  assign CommittedM = SelHPTW | DCacheCommittedM | BusCommittedM;

  // MMU and Misalignment fault logic required if privileged unit exists
  if(`ZICSR_SUPPORTED == 1) begin : dmmu
    logic 					   DataMisalignedM;

    mmu #(.TLB_ENTRIES(`DTLB_ENTRIES), .IMMU(0))
    dmmu(.clk, .reset, .SATP_REGW, .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV, .STATUS_MPP,
      .PrivilegeModeW, .DisableTranslation(SelHPTW),
      .PAdr(PreLSUPAdrM),
      .VAdr(IEUAdrM),
      .Size(LSUFunct3M[1:0]),
      .PTE,
      .PageTypeWriteVal(PageType),
      .TLBWrite(DTLBWriteM),
      .TLBFlush(DTLBFlushM),
      .PhysicalAddress(LSUPAdrM),
      .TLBMiss(DTLBMissM),
      .Cacheable(CacheableM),
      .Idempotent(), .AtomicAllowed(),
      .TLBPageFault(DTLBPageFaultM),
      .InstrAccessFaultF(), .LoadAccessFaultM, .StoreAccessFaultM,
      .AtomicAccessM(|LSUAtomicM), .ExecuteAccessF(1'b0), 
      .WriteAccessM(PreLSURWM[0]), .ReadAccessM(PreLSURWM[1]),
      .PMPCFG_ARRAY_REGW, .PMPADDR_ARRAY_REGW
      );

    // *** lsumisaligned lsumisaligned(Funct3M, IEUAdrM, MemRW, LoadMisalignedFaultM, StoreMisalignedFaultM);
    // *** lump into lsumislaigned module
    // Determine if an Unaligned access is taking place
    // hptw guarantees alignment, only check inputs from IEU.
    always_comb
    case(Funct3M[1:0]) 
      2'b00:  DataMisalignedM = 0;                       // lb, sb, lbu
      2'b01:  DataMisalignedM = IEUAdrM[0];              // lh, sh, lhu
      2'b10:  DataMisalignedM = IEUAdrM[1] | IEUAdrM[0]; // lw, sw, flw, fsw, lwu
      2'b11:  DataMisalignedM = |IEUAdrM[2:0];           // ld, sd, fld, fsd
    endcase 

    // If the CPU's (not HPTW's) request is a page fault.
    assign LoadMisalignedFaultM = DataMisalignedM & MemRWM[1];
    assign StoreMisalignedFaultM = DataMisalignedM & MemRWM[0];
    
  end else begin
    assign {DTLBMissM, DTLBPageFaultM, LoadAccessFaultM, StoreAccessFaultM, LoadMisalignedFaultM, StoreMisalignedFaultM} = '0;
    assign LSUPAdrM = PreLSUPAdrM;
    assign CacheableM = 1;
  end
  assign LSUStallM = DCacheStallM | InterlockStall | BusStall;
  
  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Hart Memory System
  //  Either Data Cache or Data Tightly Integrated Memory or just bus interface
  ////////////////////////////////////////////////////////////////////////////////////////////////

  localparam integer   WORDSPERLINE = `MEM_DCACHE ? `DCACHE_LINELENINBITS/`XLEN : 1;
  localparam integer   LOGWPL = `MEM_DCACHE ? $clog2(WORDSPERLINE) : 1;
  localparam integer   LINELEN = `MEM_DCACHE ? `DCACHE_LINELENINBITS : `XLEN;
  localparam integer   WordCountThreshold = `MEM_DCACHE ? WORDSPERLINE - 1 : 0;

  localparam integer   LINEBYTELEN = LINELEN/8;
  localparam integer   OFFSETLEN = $clog2(LINEBYTELEN);

  logic [`XLEN-1:0]    FinalAMOWriteDataM, FinalWriteDataM;
  (* mark_debug = "true" *) logic [`XLEN-1:0]    PreLSUBusHWDATA;
  logic [`XLEN-1:0]    ReadDataWordM;
  logic [LINELEN-1:0] DCacheMemWriteData;
  logic [`XLEN-1:0]    ReadDataWordMuxM;
  logic [`PA_BITS-1:0] DCacheBusAdr;
  logic [`XLEN-1:0]    ReadDataLineSetsM [WORDSPERLINE-1:0];
  logic 			   DCacheWriteLine;
  logic 			   DCacheFetchLine;
  logic 			   DCacheBusAck;
  logic 			   SelUncachedAdr;

  if (`MEM_DTIM) begin : dtim
    simpleram #(.BASE(`RAM_BASE), .RANGE(`RAM_RANGE)) ram (
        .HCLK(clk), .HRESETn(~reset), 
        .HSELRam(1'b1), .HADDR(LSUPAdrM[31:0]),
        .HWRITE(LSURWM[0]), .HREADY(1'b1),
        .HTRANS(|LSURWM ? 2'b10 : 2'b00), .HWDATA(FinalWriteDataM), .HREADRam(ReadDataWordM),
        .HRESPRam(), .HREADYRam());

    // since we have a local memory the bus connections are all disabled.
    // There are no peripherals supported.
    assign {BusStall, LSUBusWrite, LSUBusRead, DCacheBusAck, BusCommittedM, SelUncachedAdr} = '0;   
    assign ReadDataWordMuxM = ReadDataWordM;
    assign {DCacheStallM, DCacheCommittedM, DCacheWriteLine, DCacheFetchLine, DCacheBusAdr} = '0;
    assign ReadDataLineSetsM[0] = 0;
    assign DCacheMiss = 1'b0; assign DCacheAccess = 1'b0;
end else begin : bus  // *** lsubusdp
    // Bus Side logic
    // register the fetch data from the next level of memory.
    // This register should be necessary for timing.  There is no register in the uncore or
    // ahblite controller between the memories and this cache.
    logic [LOGWPL-1:0]   WordCount;

    genvar               index;
    for (index = 0; index < WORDSPERLINE; index++) begin:fetchbuffer
      flopen #(`XLEN) fb(.clk, .en(LSUBusAck & LSUBusRead & (index == WordCount)),
                         .d(LSUBusHRDATA), .q(DCacheMemWriteData[(index+1)*`XLEN-1:index*`XLEN]));
    end

    assign LocalLSUBusAdr = SelUncachedAdr ? LSUPAdrM : DCacheBusAdr ;
    assign LSUBusAdr = ({{`PA_BITS-LOGWPL{1'b0}}, WordCount} << $clog2(`XLEN/8)) + LocalLSUBusAdr;
    assign PreLSUBusHWDATA = ReadDataLineSetsM[WordCount];
    // exclude the subword write for uncached.  We don't read the data first so we cannot
    // select the subword by masking.  Subword write also exists inside the uncore to
    // suport subword masking for i/o.  I'm not sure if this is necessary.
    assign LSUBusHWDATA = SelUncachedAdr ? FinalAMOWriteDataM : PreLSUBusHWDATA; 

    assign LSUBusSize = SelUncachedAdr ? LSUFunct3M : (`XLEN == 32 ? 3'b010 : 3'b011);

    // select between dcache and direct from the BUS. Always selected if no dcache.
    mux2 #(`XLEN) UnCachedDataMux(.d0(ReadDataWordM),
          .d1(DCacheMemWriteData[`XLEN-1:0]),
          .s(SelUncachedAdr),
          .y(ReadDataWordMuxM));

    busfsm #(WordCountThreshold, LOGWPL, `MEM_DCACHE)
    busfsm(.clk, .reset, .IgnoreRequest, .LSURWM, .DCacheFetchLine, .DCacheWriteLine,
		   .LSUBusAck, .CPUBusy, .CacheableM, .BusStall, .LSUBusWrite, .LSUBusRead,
		   .DCacheBusAck, .BusCommittedM, .SelUncachedAdr, .WordCount);

    if(`MEM_DCACHE) begin : dcache
      cache #(.LINELEN(`DCACHE_LINELENINBITS), .NUMLINES(`DCACHE_WAYSIZEINBYTES*8/LINELEN),
        .NUMWAYS(`DCACHE_NUMWAYS), .DCACHE(1)) 
        dcache(.clk, .reset, .CPUBusy,
            .RW(CacheableM ? LSURWM : 2'b00), .FlushCache(FlushDCacheM), .Atomic(CacheableM ? LSUAtomicM : 2'b00), 
            .NextAdr(LSUAdrE), .PAdr(LSUPAdrM),
            .FinalWriteData(FinalWriteDataM), .ReadDataWord(ReadDataWordM), .CacheStall(DCacheStallM),
            .CacheMiss(DCacheMiss), .CacheAccess(DCacheAccess), 
            .IgnoreRequest, .CacheCommitted(DCacheCommittedM),
            .CacheBusAdr(DCacheBusAdr), .ReadDataLineSets(ReadDataLineSetsM), .CacheMemWriteData(DCacheMemWriteData),
            .CacheFetchLine(DCacheFetchLine), .CacheWriteLine(DCacheWriteLine), .CacheBusAck(DCacheBusAck), .InvalidateCacheM(1'b0));

    end else begin : passthrough
      assign {ReadDataWordM, DCacheStallM, DCacheCommittedM, DCacheWriteLine, DCacheFetchLine, DCacheBusAdr} = '0;
      assign ReadDataLineSetsM[0] = 0;
      assign DCacheMiss = CacheableM; assign DCacheAccess = CacheableM;
    end
  end

  // sub word selection for read and writes and optional amo alu.
  subwordread subwordread(.ReadDataWordMuxM,
			  .LSUPAdrM(LSUPAdrM[2:0]),
			  .Funct3M(LSUFunct3M),
			  .ReadDataM);

  // this might only get instantiated if there is a dcache or dtim.
  // There is a copy in the ebu. *** is it needed there, or can data come in from ebu, get muxed here and sent back out
  subwordwrite subwordwrite(.HRDATA(ReadDataWordM),
			    .HADDRD(LSUPAdrM[2:0]),
			    .HSIZED({LSUFunct3M[2], 1'b0, LSUFunct3M[1:0]}),
			    .HWDATAIN(FinalAMOWriteDataM),
			    .HWDATA(FinalWriteDataM));

  ////////////////////////////////////////////////////////////////////////////////////////////////
  // Atomic operations
  ////////////////////////////////////////////////////////////////////////////////////////////////

  if (`A_SUPPORTED) begin:lrsc
    logic [`XLEN-1:0] AMOResult;
    amoalu amoalu(.srca(ReadDataM), .srcb(WriteDataM), .funct(LSUFunct7M), .width(LSUFunct3M[1:0]), 
                  .result(AMOResult));
    mux2 #(`XLEN) wdmux(WriteDataM, AMOResult, LSUAtomicM[1], FinalAMOWriteDataM);
    assign MemReadM = PreLSURWM[1] & ~(IgnoreRequest) & ~DTLBMissM;
    lrsc lrsc(.clk, .reset, .FlushW, .CPUBusy, .MemReadM, .PreLSURWM, .LSUAtomicM, .LSUPAdrM,
        .SquashSCW, .LSURWM);
  end else begin:lrsc
    assign SquashSCW = 0;
    assign LSURWM = PreLSURWM;
    assign FinalAMOWriteDataM = WriteDataM;
  end
endmodule

