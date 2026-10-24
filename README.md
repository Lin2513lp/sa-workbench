> 源码范围：仅本模块 RTL、内部子模块及独立 TB；其他模块源码请进入对应工作台。`code/` 不收录联调包装、构建脚本、Makefile 或说明文件。

# SA Design Workbench

[Open the SA workbench](https://lin2513lp.github.io/sa-workbench/sa_workbench.html) · [Native waveforms](https://lin2513lp.github.io/sa-workbench/sa_sim_waveforms.html)

SA keeps the original 18 external ports. CTRL supplies lane0 vector markers through existing VALID/LAST pins; SA restores the former PE shared-valid window internally with 15 single-bit history registers. The PE, SA_CTRL, numeric Skew path and pre-midnight collector are unchanged. There is no numeric data buffer or added result latency. VALID low can coexist with valid data in other skew lanes; this timing contract is documented explicitly.

The exact pre-midnight TOP TB, including DONE/TX-LAST/count assertions, passes 107 checks in Questa and VM VCS. Six SA top tests and three units pass. A dual real-FIFO / CTRL / SA comparison passes 108 tasks across four modes, three sizes and multiple input lengths and gaps. Three SA unit TBs and the mode wrappers are byte-identical to the pre-midnight files; only necessary top-level connections and CTRL marker checks are adapted.

`code/` contains source snapshots. `source-manifest.json` records source hashes; `sim/native_manifest.json` binds the current VCS sources, six FSDBs and twelve native Verdi screenshots with exactly 18 external signals. Raw run logs are under `sim/logs/`; [the correction report](sim/marker-validation.md) describes the changes and verification scope.

The published code directory contains only RTL and independent TB snapshots. Simulation uses the original local project environment.

