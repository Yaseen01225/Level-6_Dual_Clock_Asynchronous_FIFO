`timescale 1ns / 1ps

// ============================================================================
// Project       : Level-6 Dual-Clock Asynchronous FIFO
// Module        : tb_async_fifo
// File          : tb_async_fifo.v
// Developer     : Ghulam Yaseen Nangraj
// Date          : 05 November 2026
// Platform      : Xilinx Vivado 2025.2.1 / XSIM
// Target FPGA   : Xilinx Artix-7 (Arty A7-100T)
// Language      : Verilog-2001
//
// ============================================================================
// 1. TESTBENCH OVERVIEW
// ============================================================================
// This testbench verifies the basic operation of a dual-clock asynchronous
// FIFO using independent write and read clock signals.
//
// The testbench performs the following operations:
//
//   1. Generates independent write and read clocks.
//   2. Applies and releases the active-low reset signals.
//   3. Allows the synchronized pointers to settle.
//   4. Writes four data words into the FIFO.
//   5. Allows the read domain to synchronize the write pointer.
//   6. Reads the stored data words.
//   7. Checks the output data sequence.
//   8. Reports PASS or terminates simulation on a mismatch.
//
// ============================================================================
// 2. TEST CONFIGURATION
// ============================================================================
// DATA_WIDTH : 8 bits
// ADDR_WIDTH : 3 bits
// DEPTH      : 8 memory locations
//
// Write clock period : 10 ns (100 MHz)
// Read clock period  : 14 ns (approximately 71.43 MHz)
//
// ============================================================================
// 3. VERIFICATION OBJECTIVES
// ============================================================================
//   - Independent clock-domain operation.
//   - Reset initialization.
//   - Basic FIFO write operation.
//   - Basic FIFO read operation.
//   - Pointer synchronization delay.
//   - Data ordering verification.
//   - Basic read/write functionality.
//
// ============================================================================


// ============================================================================
// TESTBENCH MODULE DECLARATION
// ============================================================================

module tb_async_fifo;


    // =========================================================================
    // SECTION 1: TESTBENCH SIGNAL DECLARATIONS
    // =========================================================================

    // Independent clock signals for the two FIFO domains.
    reg wr_clk = 1'b0;
    reg rd_clk = 1'b0;

    // Active-low reset signals for the write and read domains.
    reg wr_rst_n = 1'b0;
    reg rd_rst_n = 1'b0;

    // FIFO write and read enable controls.
    reg wr_en = 1'b0;
    reg rd_en = 1'b0;

    // Eight-bit input data bus.
    reg [7:0] data_in = 8'h00;

    // Eight-bit registered FIFO output.
    wire [7:0] data_out;

    // FIFO status signals.
    wire full;
    wire empty;


    // =========================================================================
    // SECTION 2: DEVICE UNDER TEST (DUT) INSTANTIATION
    // =========================================================================

    // Instantiate the parameterized asynchronous FIFO.
    //
    // DATA_WIDTH = 8 : Each FIFO word contains eight bits.
    // ADDR_WIDTH = 3 : Three address bits select eight locations.
    // DEPTH      = 8 : Total FIFO storage capacity is eight words.

    async_fifo #(
        .DATA_WIDTH (8),
        .ADDR_WIDTH (3),
        .DEPTH      (8)
    ) dut (

        // Clock interfaces.
        .wr_clk   (wr_clk),
        .rd_clk   (rd_clk),

        // Independent reset interfaces.
        .wr_rst_n (wr_rst_n),
        .rd_rst_n (rd_rst_n),

        // Write interface.
        .wr_en    (wr_en),
        .data_in  (data_in),

        // Read interface.
        .rd_en    (rd_en),
        .data_out (data_out),

        // FIFO status outputs.
        .full     (full),
        .empty    (empty)

    );


    // =========================================================================
    // SECTION 3: INDEPENDENT CLOCK GENERATION
    // =========================================================================

    // Generate a 100 MHz write clock.
    // Half-period = 5 ns; complete period = 10 ns.

    always #5 wr_clk = ~wr_clk;


    // Generate an independent read clock.
    // Half-period = 7 ns; complete period = 14 ns.
    //
    // Different clock periods demonstrate asynchronous operation.

    always #7 rd_clk = ~rd_clk;


    // =========================================================================
    // SECTION 4: TESTBENCH VARIABLES
    // =========================================================================

    // Integer variable used to control the write and read test sequences.
    integer i;


    // =========================================================================
    // SECTION 5: MAIN TEST SEQUENCE
    // =========================================================================

    initial begin


        // ---------------------------------------------------------------------
        // TEST 1: RESET INITIALIZATION
        // ---------------------------------------------------------------------

        // Both resets initially remain LOW.
        // Wait 20 ns before releasing the resets.

        #20;

        // Release the write-domain and read-domain resets.
        wr_rst_n = 1'b1;
        rd_rst_n = 1'b1;


        // ---------------------------------------------------------------------
        // TEST 2: POINTER SYNCHRONIZATION SETTLING TIME
        // ---------------------------------------------------------------------

        // Wait for three write-clock positive edges.
        //
        // This provides time for the reset state and synchronized pointer
        // values to propagate through the two-stage synchronizer pipelines.

        repeat (3) @(posedge wr_clk);


        // ---------------------------------------------------------------------
        // TEST 3: FIFO WRITE OPERATION
        // ---------------------------------------------------------------------

        // Write four consecutive data words into the FIFO.
        //
        // Expected data sequence:
        //   A0
        //   A1
        //   A2
        //   A3
        //
        // Data is updated at the negative edge of wr_clk so that it is
        // stable before the next positive edge.

        for (i = 0; i < 4; i = i + 1) begin

            @(negedge wr_clk);

            // Enable the FIFO write operation.
            wr_en = 1'b1;

            // Generate the next data word.
            data_in = 8'hA0 + i;

        end


        // Disable the write request after all four words are supplied.
        @(negedge wr_clk);

        wr_en = 1'b0;


        // ---------------------------------------------------------------------
        // TEST 4: READ-DOMAIN POINTER SYNCHRONIZATION
        // ---------------------------------------------------------------------

        // Allow four read-clock positive edges.
        //
        // This provides time for the synchronized write Gray pointer to
        // propagate through the read-domain synchronizer.
        //
        // The empty flag can then reflect the availability of written data.

        repeat (4) @(posedge rd_clk);


        // ---------------------------------------------------------------------
        // TEST 5: FIFO READ OPERATION AND DATA VERIFICATION
        // ---------------------------------------------------------------------

        // Read four words from the FIFO.
        // Verify that the received data follows the original write order.

        for (i = 0; i < 4; i = i + 1) begin

            // Enable reading at the negative edge of rd_clk.
            @(negedge rd_clk);

            rd_en = 1'b1;


            // Wait for the positive edge where the FIFO captures the data.
            @(posedge rd_clk);

            // Allow nonblocking assignments to update data_out.
            #1;


            // Compare the received word with the expected data.
            //
            // Case inequality ( !== ) also detects unknown (X) and
            // high-impedance (Z) values.

            if (data_out !== (8'hA0 + i)) begin

                // Stop simulation immediately if data ordering is incorrect.
                $fatal(1,
                    "ERROR: Async FIFO data mismatch! Expected=%h Received=%h",
                    (8'hA0 + i),
                    data_out
                );

            end

        end


        // ---------------------------------------------------------------------
        // TEST 6: DISABLE FIFO READ OPERATION
        // ---------------------------------------------------------------------

        // Disable the read request at the next negative clock edge.
        @(negedge rd_clk);

        rd_en = 1'b0;


        // ---------------------------------------------------------------------
        // TEST 7: TEST COMPLETION
        // ---------------------------------------------------------------------

        // Report successful completion of the basic test sequence.
        $display("================================================");
        $display(" LEVEL 6 ASYNCHRONOUS FIFO BASIC TEST PASS");
        $display(" DATA WIDTH : 8 BITS");
        $display(" FIFO DEPTH : 8 WORDS");
        $display(" WORDS READ : 4");
        $display("================================================");

        // Terminate the simulation.
        $finish;

    end

// ============================================================================
// END OF TESTBENCH: tb_async_fifo
// ============================================================================

endmodule