`timescale 1ns / 1ps

// ============================================================================
// Project       : Level-6 Dual-Clock Asynchronous FIFO
// Module        : async_fifo
// File          : async_fifo.v
// Developer     : Ghulam Yaseen Nangraj
// Date          : 05 November 2026
// Platform      : Xilinx Vivado 2025.2.1 / XSIM
// Target FPGA   : Xilinx Artix-7 (Arty A7-100T)
// Language      : Verilog-2001
//
// ============================================================================
// 1. DESIGN OVERVIEW
// ============================================================================
// This module implements a dual-clock asynchronous FIFO (First-In,
// First-Out) memory buffer.
//
// The FIFO allows data to be written and read using two independent clocks:
//
//   wr_clk : Controls write operations and write-pointer advancement.
//   rd_clk : Controls read operations and read-pointer advancement.
//
// Gray-coded pointers are used for safe clock-domain crossing (CDC).
// Each pointer passes through a two-stage synchronizer before entering
// the opposite clock domain.
//
// ============================================================================
// 2. DESIGN FEATURES
// ============================================================================
//   - Independent write and read clock domains.
//   - Independent active-low asynchronous reset inputs.
//   - Parameterized data width and FIFO address width.
//   - Binary pointers for memory addressing.
//   - Gray-coded pointers for clock-domain synchronization.
//   - Two-stage synchronizers for CDC.
//   - Full and empty status generation.
//   - Extra pointer bit for wrap-around detection.
//   - Registered read-data output.
//   - Synthesizable Verilog-2001 coding style.
//
// ============================================================================
// 3. PARAMETER DESCRIPTION
// ============================================================================
// DATA_WIDTH : Number of bits stored in each FIFO memory location.
// ADDR_WIDTH : Number of address bits.
// DEPTH      : Total number of FIFO memory locations.
//
// IMPORTANT:
// DEPTH must be equal to 2**ADDR_WIDTH.
// ADDR_WIDTH must be at least 2 for the full-comparison expression.
//
// ============================================================================
// 4. OPERATIONAL NOTES
// ============================================================================
//   - Write is accepted when wr_en is HIGH and full is LOW.
//   - Read is accepted when rd_en is HIGH and empty is LOW.
//   - A write operation advances only the write pointer.
//   - A read operation advances only the read pointer.
//   - Reset both clock domains consistently during FIFO initialization.
//   - Gray-pointer synchronization introduces CDC latency.
//
// ============================================================================
// 5. DESIGN LIMITATIONS
// ============================================================================
//   - This is an educational asynchronous FIFO implementation.
//   - Physical CDC constraints and synchronizer placement must be reviewed.
//   - Memory inference depends on FPGA architecture and synthesis settings.
//   - Independent reset release requires careful system-level coordination.
//   - The design does not include overflow/underflow counters or
//     programmable almost-full/almost-empty flags.
//
// ============================================================================


// ============================================================================
// MODULE DECLARATION
// ============================================================================

module async_fifo #(
    parameter DATA_WIDTH = 8,             // Number of bits per data word.
    parameter ADDR_WIDTH = 3,             // Number of memory address bits.
    parameter DEPTH      = (1 << ADDR_WIDTH) // FIFO memory capacity.
)(
    // ------------------------------------------------------------------------
    // CLOCK AND RESET INTERFACES
    // ------------------------------------------------------------------------

    input  wire                  wr_clk,      // Independent write clock.
    input  wire                  rd_clk,      // Independent read clock.

    input  wire                  wr_rst_n,    // Active-low write-domain reset.
    input  wire                  rd_rst_n,    // Active-low read-domain reset.

    // ------------------------------------------------------------------------
    // WRITE INTERFACE
    // ------------------------------------------------------------------------

    input  wire                  wr_en,       // Write request.
    input  wire [DATA_WIDTH-1:0] data_in,     // Input data word.

    // ------------------------------------------------------------------------
    // READ INTERFACE
    // ------------------------------------------------------------------------

    input  wire                  rd_en,       // Read request.
    output reg  [DATA_WIDTH-1:0] data_out,    // Registered output data.

    // ------------------------------------------------------------------------
    // FIFO STATUS FLAGS
    // ------------------------------------------------------------------------

    output wire                  full,        // FIFO cannot accept a write.
    output wire                  empty        // FIFO contains no readable data.
);


    // =========================================================================
    // SECTION 1: POINTER AND MEMORY DECLARATIONS
    // =========================================================================

    // An additional pointer bit distinguishes different memory wrap-around
    // cycles and helps identify the full and empty conditions.
    localparam PTR_WIDTH = ADDR_WIDTH + 1;

    // FIFO storage array.
    // Each memory location stores one DATA_WIDTH-bit word.
    reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];


    // =========================================================================
    // SECTION 2: BINARY AND GRAY-CODED POINTERS
    // =========================================================================

    // Binary write pointer:
    // Used to select the memory location for the next write operation.
    reg [PTR_WIDTH-1:0] wr_bin;

    // Gray-coded write pointer:
    // Used for transferring write-pointer information into the read domain.
    reg [PTR_WIDTH-1:0] wr_gray;


    // Binary read pointer:
    // Used to select the memory location for the next read operation.
    reg [PTR_WIDTH-1:0] rd_bin;

    // Gray-coded read pointer:
    // Used for transferring read-pointer information into the write domain.
    reg [PTR_WIDTH-1:0] rd_gray;


    // =========================================================================
    // SECTION 3: CLOCK-DOMAIN CROSSING SYNCHRONIZERS
    // =========================================================================

    // Read Gray pointer synchronized into the write-clock domain.
    // The first flip-flop receives the asynchronous pointer.
    reg [PTR_WIDTH-1:0] rd_gray_w1;

    // The second flip-flop provides the synchronized read pointer.
    reg [PTR_WIDTH-1:0] rd_gray_w2;


    // Write Gray pointer synchronized into the read-clock domain.
    // The first flip-flop receives the asynchronous pointer.
    reg [PTR_WIDTH-1:0] wr_gray_r1;

    // The second flip-flop provides the synchronized write pointer.
    reg [PTR_WIDTH-1:0] wr_gray_r2;


    // =========================================================================
    // SECTION 4: NEXT-POINTER GENERATION
    // =========================================================================

    // Advance the write binary pointer only when a write request is accepted.
    // If the FIFO is full, the write pointer remains unchanged.
    wire [PTR_WIDTH-1:0] wr_bin_next =
        wr_bin + (wr_en && !full);


    // Advance the read binary pointer only when a read request is accepted.
    // If the FIFO is empty, the read pointer remains unchanged.
    wire [PTR_WIDTH-1:0] rd_bin_next =
        rd_bin + (rd_en && !empty);


    // Convert the next binary write pointer into Gray code.
    // Gray code changes only one bit between consecutive pointer values.
    wire [PTR_WIDTH-1:0] wr_gray_next =
        (wr_bin_next >> 1) ^ wr_bin_next;


    // Convert the next binary read pointer into Gray code.
    wire [PTR_WIDTH-1:0] rd_gray_next =
        (rd_bin_next >> 1) ^ rd_bin_next;


    // =========================================================================
    // SECTION 5: FIFO FULL AND EMPTY DETECTION
    // =========================================================================

    // FULL DETECTION:
    //
    // The FIFO is full when the next write Gray pointer matches the
    // synchronized read Gray pointer after inversion of its two MSBs.
    //
    // This is the conventional full-detection method for a power-of-two
    // asynchronous FIFO using an extra pointer bit.
    assign full =  (wr_gray == {~rd_gray_w2[PTR_WIDTH-1:PTR_WIDTH-2],rd_gray_w2[PTR_WIDTH-3:0]});


    // EMPTY DETECTION:
    //
    // The FIFO is empty when the current read Gray pointer matches the
    // synchronized write Gray pointer.
    assign empty = (rd_gray == wr_gray_r2);


    // =========================================================================
    // SECTION 6: READ POINTER SYNCHRONIZATION
    // =========================================================================

    // Transfer the read Gray pointer into the write-clock domain.
    //
    // Both synchronizer stages operate using wr_clk.
    // The two stages reduce the probability of metastability propagating
    // into the write-domain control logic.

    always @(posedge wr_clk or negedge wr_rst_n) begin

        if (!wr_rst_n) begin

            // Initialize both synchronization stages.
            rd_gray_w1 <= {PTR_WIDTH{1'b0}};
            rd_gray_w2 <= {PTR_WIDTH{1'b0}};

        end

        else begin

            // Stage 1 samples the asynchronous read Gray pointer.
            rd_gray_w1 <= rd_gray;

            // Stage 2 samples the output of Stage 1.
            rd_gray_w2 <= rd_gray_w1;

        end

    end


    // =========================================================================
    // SECTION 7: WRITE POINTER SYNCHRONIZATION
    // =========================================================================

    // Transfer the write Gray pointer into the read-clock domain.
    //
    // Both synchronizer stages operate using rd_clk.
    // This prevents the read-domain control logic from directly depending
    // on an asynchronous write-pointer signal.

    always @(posedge rd_clk or negedge rd_rst_n) begin

        if (!rd_rst_n) begin

            // Initialize both synchronization stages.
            wr_gray_r1 <= {PTR_WIDTH{1'b0}};
            wr_gray_r2 <= {PTR_WIDTH{1'b0}};

        end

        else begin

            // Stage 1 samples the asynchronous write Gray pointer.
            wr_gray_r1 <= wr_gray;

            // Stage 2 provides the synchronized write Gray pointer.
            wr_gray_r2 <= wr_gray_r1;

        end

    end


    // =========================================================================
    // SECTION 8: WRITE-DOMAIN CONTROL AND MEMORY STORAGE
    // =========================================================================

    // The write pointer and memory write operation are controlled exclusively
    // by the write clock domain.

    always @(posedge wr_clk or negedge wr_rst_n) begin

        if (!wr_rst_n) begin

            // Reset the binary write pointer.
            wr_bin <= {PTR_WIDTH{1'b0}};

            // Reset the Gray-coded write pointer.
            wr_gray <= {PTR_WIDTH{1'b0}};

        end

        else if (wr_en && !full) begin

            // Store input data at the current write address.
            memory[wr_bin[ADDR_WIDTH-1:0]] <= data_in;

            // Advance the binary write pointer.
            wr_bin <= wr_bin_next;

            // Update the Gray-coded write pointer.
            wr_gray <= wr_gray_next;

        end

    end


    // =========================================================================
    // SECTION 9: READ-DOMAIN CONTROL AND DATA OUTPUT
    // =========================================================================

    // The read pointer and output register are controlled exclusively
    // by the read clock domain.

    always @(posedge rd_clk or negedge rd_rst_n) begin

        if (!rd_rst_n) begin

            // Reset the binary read pointer.
            rd_bin <= {PTR_WIDTH{1'b0}};

            // Reset the Gray-coded read pointer.
            rd_gray <= {PTR_WIDTH{1'b0}};

            // Initialize the registered output data.
            data_out <= {DATA_WIDTH{1'b0}};

        end

        else if (rd_en && !empty) begin

            // Read data from the current read address.
            data_out <= memory[rd_bin[ADDR_WIDTH-1:0]];

            // Advance the binary read pointer.
            rd_bin <= rd_bin_next;

            // Update the Gray-coded read pointer.
            rd_gray <= rd_gray_next;

        end

    end


// ============================================================================
// END OF MODULE: async_fifo
// ============================================================================

endmodule