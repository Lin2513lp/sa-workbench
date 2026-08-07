# SA_TOP Design Workbench

## Online Workbench

[Open the SA_TOP Design Workbench](https://lin2513lp.github.io/sa-workbench/)

This repository hosts a standalone design workbench for a 16x16 systolic array. The complete workbench runs directly in a browser through GitHub Pages and requires no local installation.

## Workbench Contents

- **Design Report**: SA_TOP architecture, external interfaces, clock and reset handling, RegMap CDC, weight loading, PE array interconnects, and output collection.
- **RTL and Testbench Code**: Browse the current `Makefile`, 11 RTL files, and 11 testbench files online.
- **Simulation Waveforms**: Review top-level regression waveforms and check results for INT4, INT8, FP16, FP32, and multi-task operation.
- **WaveDrom Timing Diagrams**: Inspect B-weight clock-domain crossing, A-data flow, and output timing for different compute modes.
- **Design Notes**: Learn the dataflow from matrix multiplication and local MAC operations to partial-sum propagation across the 16x16 array, including an interactive pipeline demonstration.

## Current RTL Structure

The SA_TOP implementation is organized around the following modules:

- `sa_top`
- `sa_ctrl`
- `pe_array_16x16`
- `output_collector`
- `pe_mp/PE_MP_v1`

Top-level regression covers smoke, INT4, INT8, FP16, FP32, and multi-task scenarios. Both the Questa and Icarus regression sets pass 6 out of 6 cases. The workbench also documents the remaining verification boundaries, including packed INT4/INT8 sub-lanes, dynamic active sizes, and floating-point special cases.

## Repository Layout

- `sa_workbench.html`: Main design workbench.
- `sa_code_design.html`: RTL and testbench source browser.
- `sa_sim_waveforms.html`: Simulation waveform browser.
- `sa_wavedrom_int4.html`: Multi-mode WaveDrom timing diagrams.
- `code/`: RTL, testbench, and build-file snapshots displayed by the workbench.
- `sim/`: Five top-level simulation waveform images.

This is a static GitHub Pages repository. The `.nojekyll` file preserves the original asset and source-file paths.
