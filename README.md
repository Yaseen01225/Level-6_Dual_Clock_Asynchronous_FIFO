# Level-6 Dual-Clock Asynchronous FIFO

**Developer:** Ghulam Yaseen Nangraj  
**Date:** 05 November 2026  
**Platform:** Xilinx Vivado 2025.2.1 / XSIM  
**Target FPGA:** Xilinx Artix-7 (Arty A7-100T)  
**HDL Standard:** Verilog-2001 (IEEE 1364-2001)

---

## 1. Project Overview

This project implements a parameterized, dual-clock asynchronous FIFO (First-In, First-Out) in Verilog. It allows data to be written in one clock domain and read in another clock domain, where the write and read clocks are independent and may operate at different frequencies.

The design uses binary pointers for memory addressing and Gray-coded pointers for clock-domain crossing (CDC). Each Gray-coded pointer is transferred to the opposite clock domain through a two-stage synchronizer.

The supplied testbench demonstrates basic asynchronous operation using an 8-bit data width, an eight-word FIFO, a 100 MHz write clock, and an approximately 71.43 MHz read clock.

## 2. Project Files

| File | Purpose |
|---|---|
| `async_fifo.v` | Synthesizable FIFO RTL design |
| `tb_async_fifo.v` | Simulation testbench for basic FIFO operation |
| `README.md` | Project description, interfaces, operation, verification scope, and implementation notes |

Keep synthesizable design sources and simulation testbench sources in separate Vivado project folders, for example:

```text
Level-6_Async_FIFO/
|
+-- Design/
|   +-- async_fifo.v
|
+-- Testbench/
|   +-- tb_async_fifo.v
|
+-- README.md
```

## 3. Design Parameters

| Parameter | Default | Description |
|---|---:|---|
| `DATA_WIDTH` | 8 | Number of bits in each stored word |
| `ADDR_WIDTH` | 3 | Number of address bits |
| `DEPTH` | `1 << ADDR_WIDTH` | Number of FIFO storage locations |

### Parameter constraints

- `DEPTH` must equal `2**ADDR_WIDTH`.
- `ADDR_WIDTH` must be at least 2 because the full-detection expression in this implementation inverts the two most-significant pointer bits.
- The pointer width is `ADDR_WIDTH + 1`. The additional bit distinguishes pointer wrap-around and supports full/empty detection.

The supplied testbench explicitly instantiates `DATA_WIDTH=8`, `ADDR_WIDTH=3`, and `DEPTH=8`.

## 4. Interface Description

### Clock and reset

| Signal | Direction | Description |
|---|---|---|
| `wr_clk` | Input | Write-domain clock |
| `rd_clk` | Input | Read-domain clock |
| `wr_rst_n` | Input | Active-low asynchronous reset for write-domain state and read-pointer synchronizers |
| `rd_rst_n` | Input | Active-low asynchronous reset for read-domain state and write-pointer synchronizers |

The reset inputs are separate, but the system should initialize both FIFO clock domains consistently. Reset assertion and release must be coordinated at system level. Releasing one domain substantially earlier than the other can leave the FIFO domains temporarily inconsistent.

### Write interface

| Signal | Direction | Description |
|---|---|---|
| `wr_en` | Input | Requests a write |
| `data_in[DATA_WIDTH-1:0]` | Input | Data word to store |
| `full` | Output | Indicates that a write must not be accepted |

A write is accepted on a rising edge of `wr_clk` when `wr_en=1` and `full=0`.

### Read interface

| Signal | Direction | Description |
|---|---|---|
| `rd_en` | Input | Requests a read |
| `data_out[DATA_WIDTH-1:0]` | Output | Registered read-data word |
| `empty` | Output | Indicates that no readable word is currently available |

A read is accepted on a rising edge of `rd_clk` when `rd_en=1` and `empty=0`. The selected memory word is captured in `data_out` on that read-clock edge.

## 5. Internal Architecture

### 5.1 Binary pointers

- `wr_bin` selects the memory location for the next write.
- `rd_bin` selects the memory location for the next read.
- The lower `ADDR_WIDTH` bits address the memory.
- The extra most-significant bit tracks pointer wrap-around.

### 5.2 Gray-code conversion

The next Gray pointer is calculated from the next binary pointer using:

```verilog
gray = (binary >> 1) ^ binary;
```

Adjacent Gray-code pointer values differ in only one bit. This reduces the chance that a destination clock domain samples a multi-bit pointer transition during clock-domain crossing.

### 5.3 Two-stage pointer synchronizers

The read Gray pointer is synchronized into the write domain using `rd_gray_w1` and `rd_gray_w2`, both clocked by `wr_clk`.

The write Gray pointer is synchronized into the read domain using `wr_gray_r1` and `wr_gray_r2`, both clocked by `rd_clk`.

The synchronizers reduce the probability that metastability propagates into the destination-domain control logic. They do not eliminate metastability or replace physical CDC implementation constraints.

### 5.4 Full detection

The RTL asserts `full` when the current write Gray pointer equals the synchronized read Gray pointer after inversion of its two most-significant bits.

This is the conventional Gray-pointer full comparison for a power-of-two asynchronous FIFO with an extra pointer bit.

### 5.5 Empty detection

The RTL asserts `empty` when the current read Gray pointer equals the synchronized write Gray pointer:

```verilog
assign empty = (rd_gray == wr_gray_r2);
```

Because the write pointer must pass through the read-domain synchronizer, the read domain sees write progress after CDC synchronization latency.

### 5.6 Memory and registered read output

The memory is declared as:

```verilog
reg [DATA_WIDTH-1:0] memory [0:DEPTH-1];
```

Writes are performed in the write-clock process. Reads and `data_out` updates are performed in the read-clock process. The memory array is not reset by this RTL; pointer and output registers are reset.

Whether the synthesis tool maps the memory to block RAM, distributed RAM, or another implementation depends on the target FPGA, coding pattern, and synthesis settings. Confirm the inferred resource in the Vivado synthesis reports.

## 6. Operational Flow

### Write-domain sequence

1. The write interface presents `data_in` and asserts `wr_en`.
2. The write domain checks `full`.
3. If `full=0`, the word is stored at the address selected by the current write pointer.
4. The binary write pointer advances.
5. The Gray write pointer is updated.
6. The read domain receives the Gray write pointer through its two-stage synchronizer.

### Read-domain sequence

1. The read interface asserts `rd_en`.
2. The read domain checks `empty`.
3. If `empty=0`, the word at the current read address is captured into `data_out`.
4. The binary read pointer advances.
5. The Gray read pointer is updated.
6. The write domain receives the Gray read pointer through its two-stage synchronizer.

## 7. Testbench Configuration and Test Sequence

The supplied testbench uses:

| Item | Configuration |
|---|---|
| Data width | 8 bits |
| Address width | 3 bits |
| FIFO depth | 8 words |
| Write clock | 10 ns period (100 MHz) |
| Read clock | 14 ns period (approximately 71.43 MHz) |
| Reset | Two active-low reset signals |

The testbench performs these basic checks:

1. Holds both reset inputs low initially.
2. Releases both resets after 20 ns.
3. Allows write-domain clock edges for reset and synchronizer settling.
4. Writes four consecutive bytes: `A0`, `A1`, `A2`, and `A3`.
5. Allows the read-domain synchronizer to observe the write pointer.
6. Reads four words in FIFO order.
7. Compares each received word with the expected sequence.
8. Reports a PASS message if all four comparisons succeed.

The testbench is a basic functional demonstration. It does not constitute exhaustive verification of all FIFO conditions.

## 8. Expected Simulation Result

The expected read sequence is:

| Read number | Expected `data_out` |
|---:|---:|
| 1 | `8'hA0` |
| 2 | `8'hA1` |
| 3 | `8'hA2` |
| 4 | `8'hA3` |

On successful completion, the testbench prints:

```text
================================================
 LEVEL 6 ASYNCHRONOUS FIFO BASIC TEST PASS
 DATA WIDTH : 8 BITS
 FIFO DEPTH : 8 WORDS
 WORDS READ : 4
================================================
```

A data mismatch invokes the testbench's error-termination path.

## 9. Important Review Notes

The following points should be considered before treating this educational implementation as production-ready:

1. **Full-flag comment alignment:** The RTL computes `full` by comparing the current `wr_gray` pointer with the transformed synchronized read pointer. Some nearby explanatory comments describe a next-pointer comparison. Update those comments to match the implemented current-pointer comparison, or deliberately redesign the flag as a registered next-pointer full flag and verify the resulting logic.
2. **Strict Verilog-2001 testbench compatibility:** The testbench uses `$fatal`. `$fatal` is a SystemVerilog system task, not a Verilog-2001 system task. If strict IEEE 1364-2001 compatibility is required, replace that error path with a Verilog-2001-compatible reporting/termination approach, such as `$display` followed by `$finish` (or use the simulator's supported failure mechanism).
3. **Reset coordination:** Although the reset inputs are independent, the two FIFO domains should be reset and brought out of reset under a deliberate system-level sequence. Do not assume arbitrary independent reset events are safe during active traffic.
4. **CDC constraints:** Apply and review appropriate Vivado CDC and timing constraints. Ensure synchronizer registers are recognized and placed appropriately. Gray coding alone does not complete physical CDC sign-off.
5. **Memory inference:** Inspect synthesis reports to confirm the intended memory implementation. Do not assume block RAM inference solely from the RTL declaration.
6. **Verification scope:** Add tests for full and empty behavior, pointer wrap-around, sustained traffic, simultaneous read/write activity, reset during idle and traffic, and different clock ratios before relying on the design in a larger system.
7. **Status latency:** `full` and `empty` are local-domain status indications based on synchronized remote pointers. They are not instantaneous global occupancy indicators.

## 10. Features Not Implemented

The supplied RTL does not implement:

- Programmable almost-full or almost-empty thresholds.
- Overflow or underflow counters.
- A separate `data_valid` output.
- Error correction or parity checking.
- A complete production CDC constraint set.
- An explicit memory reset or memory initialization sequence.

These features should not be represented as existing capabilities in a Level-6 architecture diagram.

## 11. Vivado Simulation Procedure

1. Create or open a Vivado project targeting the intended FPGA.
2. Add `Design/async_fifo.v` as a design source.
3. Add `Testbench/tb_async_fifo.v` as a simulation source.
4. Set `tb_async_fifo` as the simulation top module.
5. Run **Run Behavioral Simulation**.
6. Inspect `wr_clk`, `rd_clk`, both reset signals, `wr_en`, `rd_en`, `data_in`, `data_out`, `full`, and `empty`.
7. Confirm that the output sequence is `A0`, `A1`, `A2`, `A3`, in that order.
8. Review the Tcl console and simulation transcript for the PASS message.

## 12. Engineering Takeaway

An asynchronous FIFO safely transfers buffered data between independent clock domains by synchronizing Gray-coded pointers rather than directly synchronizing multi-bit binary pointers. The extra pointer bit supports wrap-around detection, while the synchronized remote pointer enables local full and empty decisions.

**Level-6 learning focus:** dual-clock operation, Gray-code pointer conversion, two-stage CDC synchronizers, wrap-around detection, and asynchronous FIFO status generation.

---

**Developed by: Ghulam Yaseen Nangraj**  
**Verilog-2001 | Xilinx Vivado 2025.2.1 | Artix-7**
