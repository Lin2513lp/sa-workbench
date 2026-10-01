# SA_TOP Design Workbench

**[Open the SA_TOP Workbench](https://lin2513lp.github.io/sa-workbench/sa_workbench.html)**

A 16 x 16 systolic-array design workbench with multi-precision processing elements. The workbench runs in a browser and requires no installation.

## Workbench contents

- Array control, weight loading, PE interconnects, and output collection.
- INT4, INT8, FP16, and FP32 operation.
- Dataflow demonstrations, timing diagrams, simulation captures, and source browsing.

## Source files

[`code/`](code/) contains the current source snapshot from the shared `sa` project. Relative paths and file contents are preserved, including RTL, testbenches, Makefiles, file lists, and available helper scripts. The workbench's code viewer displays this same snapshot.

There are **23 project files** in this snapshot. [`source-manifest.json`](source-manifest.json) records the shared-directory mapping and SHA-256 checksums. Generated simulator databases, waveform dumps, editor temporary files, and license logs are excluded.

## Repository layout

| Path | Contents |
| --- | --- |
| [`sa_workbench.html`](sa_workbench.html) | Main design workbench |
| [`code/`](code/) | Shared-project source files and build entry points |
| [`source-manifest.json`](source-manifest.json) | Source inventory and checksums |
| [`index.html`](index.html) | English project introduction and workbench link |

## Using the project

Open the workbench through the link above to browse the report, code, and waveforms. For simulation, clone this repository, enter `code/`, and use its Makefile in a configured Linux EDA environment. The original tool paths and environment variables in the shared Makefile are preserved; configure these for your installation.

## Related workbenches

- [TPU_CRG](https://github.com/Lin2513lp/TPU_CRG_WORKBENCH)
- [AXI_TOP](https://github.com/Lin2513lp/AXI_TOP_WORKBENCH)
- [AHB_SLAVE](https://github.com/Lin2513lp/AHB_SLAVE_WORKBENCH)
- [PE_MP](https://github.com/Lin2513lp/pe-mp-workbench)
