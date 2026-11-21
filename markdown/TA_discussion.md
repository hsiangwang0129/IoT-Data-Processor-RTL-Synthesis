# HW4 TA 討論整理

整理日期：2026-11-22  
來源：[TA_discussion.txt](../TA_discussion.txt)  
範圍：Reminders 與 Q1～Q35，包含截至 2026-11-21 的 TA 回覆。

本文件以中文整理問題與 TA 結論，保留英文專有名詞、訊號名稱與原始 Question 編號。移除課程網站導覽、重複貼文及問候語；後續補充與早期說明有差異時，在相關題目標明。

## 1. 重要結論速查

| 主題 | TA 結論 | 來源 |
| --- | --- | --- |
| SDC 修改 | 在 IOTDF_DC.sdc 中只能修改 clock period。 | Reminders、Q12 |
| F3 收尾 | 最後一個 symbol 完成後，不論 Np 是否為 0，都先輸出一個 0，再補 1 至 1024 bits。 | Q2、Q9 |
| F3 輸出數量 | 每組 8 個 128-bit beats；P1 共 8 組、64 beats。 | Q4 |
| F3 codeword 長度 | 包含 hidden pattern，保證不超過 1024 bits。 | Q14 |
| 截位 | 乘法、除法採 truncation／round down，不是四捨五入。 | Q1、Q28 |
| 累積表順序 | 依 symbol 數值由小到大排列。 | Q29 |
| F4 補位 | Case 1、Case 2、Case 3 在 codeword 耗盡後都補入 1。 | Q3 |
| F4 公開測資 | 官方 TB 只測前 2 組，使用輸入檔前 18 rows，不必改成 8 組。 | Q8 |
| F4 特殊邊界 | P1／P2 排除 TA 指出的特殊情況，依 slides 的流程與精度實作即可。 | Q17、Q18 |
| Symbol count | 每個 symbol 的 count 不超過 255。 | Q19 |
| Pending 位寬 | TA 不保證最大 Np，也不保證 5 bits 足夠。 | Q31、Q33 |
| 輸出時機 | 可自行決定，但資料順序必須正確並設定 valid。 | Q25 |
| Latch | Netlist 除 clock gating 外，不得有 latch。 | Q5、Q6、Q7 |
| SRAM | 不允許使用 SRAM。 | Q24 |
| DesignWare | 允許使用。 | Q35 |
| Reset | 不要求每個內部 register 都有 reset，仍須通過 gate-level simulation。 | Q16 |
| Power library | 使用 slow library；dw_foundation.sldb 不需要用於 PrimeTime。 | Q10 |
| PrimeTime linking | link_library 必須包含 *，不能因 black box 漏算功耗；ranking 同樣適用。 | Q11、Q21 |
| SDF 路徑 | TA 評分時使用 ../03_GATE/IOTDF_syn.sdf。 | Q20 |
| 初始化 timing violation | 初始化期間可忽略，但仍須通過 gate-level simulation。 | Q22 |
| Clock period | 沒有固定上限；合成與 gate-level simulation 的週期可以不同。 | Q13、Q32 |
| Compile 後修改 | 可修改 netlist，但 area、timing reports 要在修改後產生。 | Q23 |
| Design rules | 可略過 design rules 檢查，仍需檢查 timing violations。 | Q34 |

## 2. 提問與提交規定

### 提問格式

- 在討論區以 Question 1、Question 2 等編號列出問題。
- 不得公開上傳 code 文字或 code screenshots；違規會扣 HW4 總分 10 分。

### 提交與工具限制

- [IOTDF_DC.sdc](../1151_hw4/02_SYN/IOTDF_DC.sdc) 中只能修改 clock period；其他原始設定不可任意更動。
- 只有 PrimeTime 無法處理 FSDB 時，才能改用 VCD 進行 power analysis。
- 產生 VCD waveforms 時，TA 指示在 gate-level simulation 執行命令加入 `+vcd`。
- NTU Cool 只需要提交 `01_RTL` 與 `report` folders 的檔案，壓縮檔名稱為 `cvsd_hw4_vk.tar`。
- 上一項保留 TA 原文的 `report` 名稱；本 workspace 的模板位於 [1151_hw4/reports/report.txt](../1151_hw4/reports/report.txt)。實際打包目錄需依正式提交要求核對，不在此自行改名。
- NTU Cool 的精簡提交內容不應直接視為其他提交管道的完整清單。

## 3. 算術編碼與解碼規格

### Q1：AC 數值精度與 fixed-point 格式

**問題：** L(s)、H(s) 應採哪種 fixed-point 格式？乘法與除法是否都直接截位？

**TA 回覆：**

- L(x)、H(x) 是 cumulative probability，數值介於 0 與 1。
- 可自行選擇 fixed-point 格式，前提是能正確計算其他 probability values。
- 乘法、除法後多出的 bits 應採 truncation，也就是 round down，以維持規定的 16-bit word length。
- 不能將 round down 改成 round to nearest。

### Q2：F3 Encoding Termination

**問題：** 最後一個 symbol 完成 renormalization 後，是否需要 termination bits？剩餘 pending bits 如何處理？

**TA 早期回覆：** 沒有額外 termination bits，但需處理剩餘 pending bits，再補 1 至 1024 bits。

**後續修正：** Q9 補充了早期回覆漏掉的最後一個 0。不能只根據 Q2 就直接開始 padding；完整收尾應以 Q9 為準。

### Q3：F4 Codeword 耗盡與區間邊界

**問題：** Case 3 在 codeword 用盡後是否也補 1？Pc 恰好等於區間邊界時如何選 symbol？

**TA 回覆：**

- Case 3 與 Case 1／Case 2 相同，codeword 已全部載入後，新的 bit 補入 1。
- 選擇符合下式的 symbol s：

$$
L(s) \le P_c < H(s)
$$

- `Pc = L(s)` 時選 symbol s。
- `Pc = H(s)` 時，TA 早期回覆指定選 symbol s+1。

**後續限制：** Q17 討論有限精度下的特殊邊界，Q18 再確認 hidden pattern 的產生規則。上述說明不能延伸成所有任意輸入都沒有邊界問題。

### Q4：F3 Output Beats 與 Golden 格式

**問題：** 每組 1024 bits 應輸出 8 beats，8 組應為 64 beats；是否另有 56 beats 的規定？

**TA 回覆：**

- 正確輸出長度是每組 1024 bits。
- P1 有 8 組，所以總共應輸出 64 次 valid beats。
- [f3_out.dat](../1151_hw4/00_TESTBED/pattern1_data/f3_out.dat) 應有 64 rows。
- TA 承認早期 golden-file 格式有誤，表示會更新。

### Q9：F3 Final Pending Bits 與最後的 0

**問題背景：** 提問者在八組資料結束時觀察到 Np 為 `0, 0, 0, 0, 0, 4, 3, 1`，且 golden 在一般編碼前綴後出現一個 0，再接 1。

**TA 補充回覆：**

- 不論 `Np = 0` 或 `Np > 0`，padding 前都需要輸出一個 0。
- 離開 renormalization 時，low 與 high 的 MSB 分別為 0、1；TA 說明採用 `01111...` 收尾，讓 codeword probability 位於最後區間。

**收尾結果摘要：**

```text
所有 symbols 完成，且最後一次 renormalization 結束
    -> 輸出一個 0
    -> 處理剩餘 pending，並以 1 補滿到 1024 bits
```

Q2 的 pending 規則與 Q9 的最後 0 合併後，剩餘 pending 的值為 1，與 padding 相同；最終尾端為一個 0 接若干個 1。這是兩題合併的整理，不是引用另一種 arithmetic coding 的 termination 演算法。

### Q14：Codeword 是否可能超過 1024 Bits

**問題：** 接近 uniform distribution 時，renormalization 輸出加上最後的 0 可能超過 1024 bits，是否要截掉？

**TA 回覆：**

- 一般情況確實可能超過 1024 bits，例如分布接近 uniform、幾乎沒有 redundant information。
- 本作業所有 test patterns，包含 hidden pattern，保證 codeword 長度不超過 1024 bits。
- 因此 TA 提供的是輸入保證，不是允許任意丟棄超出的 bits。

### Q17：F4 Pc = 1 與有限精度邊界

**問題：** 當 `code = high`，Pc 可能等於 1；另外 Pc 恰好位於 H(s) 時，有限精度規則可能與原始資料還原結果不同。

**TA 回覆：**

- Slides 的描述不夠精確；特殊情況下 Pc 的精確表示需要 17 bits。
- P1／P2 不會出現回覆中指出的特殊情況。
- 可依 slides 使用 16-bit Pc，按照 slides 的步驟實作即可通過公開與 hidden patterns。

**適用範圍：** 這是作業測資的限制，不是對任意 arithmetic decoder 輸入的通用正確性保證。

### Q18：F4 Hidden Pattern 的產生規則

**問題：** Hidden golden 是原始資料，還是依 Q3 邊界規則解碼的結果？

**TA 回覆：** Hidden input 依 slides 的 encoding rule 產生，依 slides 的流程實作即可通過。

TA 沒有另訂一套不同的 decoder 演算法；應與 Q17 的測資限制一起閱讀。

### Q19：Symbol Count = 256

**問題：** 一個 symbol 出現 256 次，無法用 8-bit PMF 欄位表示，應如何編碼？

**TA 回覆：** 每個 symbol count 都不超過 255，不需要處理 count=256 的 PMF 輸入。

### Q26：16-bit 區間如何產生超過 16-bit 的 Codeword

**問題：** low／high 只有 16 bits，為什麼 output 可以有 1024 bits？

**TA 回覆：**

- Output bit 是 renormalization 時 shifted out 的 bit。
- Shift out 後，low／high 會 shift in 新的 bit，維持 16-bit word length。
- 只要還有 symbol 要編碼，便能持續產生 output bits；16-bit 區間不是整個 codeword 的儲存上限。

### Q27：Codeword 的唯一性

**問題：** 最後的區間是否只對應一個 codeword 數值？

**TA 回覆：** 按照 slides 的全部步驟執行，產生的 output codeword 是唯一值。

**閱讀註記：** 此處保留 TA 對指定產生流程的結論，不應解讀為一般數學區間只能包含一個實數。

### Q28：Truncation 是否為四捨五入

**TA 回覆：** 不是。Truncation 指 round down。

### Q29：Cumulative Intervals 的 Symbol 順序

**TA 回覆：** 按 symbol 數值 ascending order 排列，也就是 0、1、2、…、15。

此順序是建立累積區間的排序，不能與原始資料的 symbol 編碼順序混為一談。

### Q30：為什麼 Pending Bits 是反向值

**問題：** Case 1 為什麼輸出 `0` 後接 pending 的 `1`，Case 2 則輸出 `1` 後接 pending 的 `0`？

**TA 回覆：** Case 3 的 bit 14 暫時無法確定。之後 MSB 確定為 0，pending bits 必為 1；MSB 確定為 1，pending bits 必為 0。

```text
Case 1：0，接 Np 個 1
Case 2：1，接 Np 個 0
```

### Q31：Np 的意義與位寬

**TA 回覆：**

- Pending bit 是目前無法確定值、但可以先 shifted out 的 bit。
- TA 未指定 Np 的固定範圍或 word length。
- 設計者需選擇合理位寬，確保能通過 test patterns。

### Q33：5-bit Pending Counter 是否足夠

**問題：** 5 bits 最大 31，是否足以通過 hidden pattern？

**TA 回覆：**

- 最大 pending 數量取決於 input distribution，TA 無法保證最大值。
- Hidden patterns 是 randomly generated sequences，不是刻意建構的特殊序列。
- 這不等於保證 5-bit counter 足夠。

## 4. Testbench、輸出與測資數量

### Q8：F4 為何只載入前兩組

**問題：** [f4_in.dat](../1151_hw4/00_TESTBED/pattern1_data/f4_in.dat) 有 72 rows、[f4_out.dat](../1151_hw4/00_TESTBED/pattern1_data/f4_out.dat) 有 64 rows，但 TB 只宣告 18 筆輸入、16 筆輸出。

**TA 回覆：**

- 官方 TB 刻意只測前 2 組，使用輸入檔最上面的 18 rows。
- 不需要修改 TB，額外資料造成的 readmem 警告可忽略。
- 原本打算測 8 組，後來因 gate-level simulation 與 power analysis 太久，改成 2 組。

### Q15：Hidden Pattern 與 P2 Testbench

**問題：** P2 的 PAT_NUM／F1_NUM～F4_NUM 全為 64，與 F4 每組 9 rows 不一致，hidden test 如何執行？

**TA 回覆：**

- Hidden pattern 資料數不超過 P1。
- P2 的預設數量尚未修改；評分時會使用同一份 testfixture，調整 P2 pattern 數量。
- TA 沒有另外要求用另一套輸入時序。

**設計提醒：** 不應把 P2 目前的預設 64 當成每個功能的固定輸入格式或 RTL 結束條件。

### Q25：輸出時間是否受限制

**TA 回覆：** 可自行決定 output 時間，只要順序正確並拉高 valid。

此回覆不取消作業原有的總模擬時間限制。

## 5. RTL、合成與 Timing

### Q5、Q6、Q7：Latch 與 Clock Gating

**問題：** 一般 latch、integrated clock-gating cell 內的 latch，以及手寫 latch-based clock gating 是否允許？

**TA 回覆：** 如同 HW3，netlist 除 clock gating 外不得包含 latch。

Q12 另補充直接例化 clock-gating cell 的條件。

### Q12：Synthesis Script、Clock-Gating Cell 與 Negedge FF

**問題：** SDC 限制是否也禁止修改 synthesis commands？能否例化 library clock-gating cell、使用 negedge FF？PrimeTime linking 警告能否忽略？

**TA 回覆：**

1. Synthesis script 可使用任何不與 IOTDF_DC.sdc 設定衝突的命令；`compile_ultra` 可使用。
2. 可以直接例化 clock-gating cell，但 latch 的輸入必須只含 control signal 與 clock。
3. 允許 negedge-triggered FF。
4. Black box 問題應依 Q11 修正 link_library，不應直接忽略。

### Q13：Clock Period 是否有上限

**TA 回覆：** Clock period 可自行設定，只要通過 gate-level simulation。

### Q16：每個 Register 是否都必須 Reset

**TA 回覆：** 不要求所有內部 registers 都有 reset，前提是能通過 gate-level simulation。

提問的情境是資料 register 在讀取前一定寫入；這不是允許 valid output 含 X。

### Q20：SDF 檔案路徑

**問題：** 原始 TB 指向 `../02_SYN/Netlist/IOTDF_syn.sdf`，提交規定卻要求放在 `03_GATE`。

**TA 回覆：** 評分的 gate-level simulation 會把 TB 路徑改為 `../03_GATE/IOTDF_syn.sdf`。依 slides 指定的 hierarchy 打包即可，不必因原始 TB 路徑額外提交第二份 SDF。

### Q22：初始化期間 Timing Violation

**問題背景：** 四功能在初始化約 9.75 ns 出現 clock-gating latch 的 setuphold violation，但之後輸出正確、DC setup／hold 均 MET。

**TA 回覆：** 初始化期間的 timing violations 可忽略，只要通過 gate-level simulation。

**適用範圍：** 此豁免針對 initialization，不是運作期間 timing violations 的全面豁免。來源中未編號的重複貼文與 Q22 為同一問題，此處合併。

### Q23：Compile 後可否修改 Netlist

**問題：** Compile 後用 DC 指令進行功能等價的 cell 更換、QN 使用或 reset 移除，是否允許？

**TA 回覆：** 允許在 compile 後修改 netlist，但必須在修改後重新產生 area 與 timing reports。

不能提交修改後 netlist，卻用修改前 reports 表示最終結果。

### Q24：SRAM Macro

**TA 回覆：** 不允許使用 SRAM。

### Q32：Synthesis 與 Gate-Level Clock Period 是否必須相同

**問題範例：** SDC 用 12.5 ns 合成，gate-level／power analysis 與 report 使用 14.0 ns，是否允許？

**TA 回覆：** 允許。Synthesis clock period 不必與 gate-level simulation 相同。

### Q34：Design Rules 是否必須全部通過

**TA 回覆：** 可略過 design rules 檢查，只需要檢查 timing violations。

此回覆不取消其他規格，例如 latch、SRAM、資料正確性或提交要求。

### Q35：DesignWare

**TA 回覆：** 允許使用 DesignWare。

## 6. PrimeTime 與 Power Analysis

### Q10：Slow Library 與 dw_foundation.sldb

**問題：** 範例 PT 設定包含 typical／slow／fast libraries，是否只應使用 slow？dw_foundation.sldb 是否必要？

**TA 回覆要點：**

- 本作業只使用 slow library，其他 libraries 可忽略。
- PrimeTime 不需要 dw_foundation.sldb；它是從 DC 設定複製後遺留的項目。

### Q11：link_library 缺少 *

**問題背景：** 保留 hierarchy 或 clock-gating wrappers 時，缺少 `*` 可能導致 unresolved references／black boxes，漏算內部 cells 的 power。提問者觀察到修改前後 power 有明顯差異，但那些比例是其個別實驗，不是固定校正係數。

**TA 回覆：**

- 範例設定漏掉 `*`。
- 請在 link_library 加入 `*`，確保 power report 沒有 black box。
- TA 評分時也會採相同修正。

結合 Q10 的 slow library 要求，可使用的設定形式為：

```tcl
set link_library "* slow.db"
```

這是兩題合併的設定摘要，仍需依實際 search_path 確保 library 可讀取。

### Q21：Ranking 是否計入 Clock-Gating Cells

**TA 回覆：** Ranking 的 power analysis 使用含 `*` 的 link_library，不應有 black box 漏算功耗；與 Q11 一致。

## 7. 關鍵補充關係

| 早期說明 | 後續補充 | 最終閱讀方式 |
| --- | --- | --- |
| Q2：無額外 termination bits，處理 pending 後補 1。 | Q9：任何 Np 都必須先輸出最後一個 0。 | 不可省略最後的 0，也不要套用其他 encoder 的收尾演算法。 |
| Q3：按 L(s) <= Pc < H(s) 選 symbol。 | Q17、Q18：特殊邊界在作業測資中排除，hidden 依 slides 產生。 | 按指定有限精度流程實作，不宣稱適用所有任意輸入。 |
| 範例 PT 設定缺少 *。 | Q11、Q21：自行量測與 ranking 都要加 *。 | 不可利用 unresolved hierarchy 漏算 power。 |
| 只可修改 SDC clock period。 | Q12：Synthesis script 可使用不衝突的 commands。 | SDC 限制不等於禁止 compile options。 |
| Slides／初始流程看似使用同一週期。 | Q32：Synthesis 與 gate-level periods 可以不同。 | 依實際各階段設定與報告記錄，不要求兩者必然相同。 |

## 8. 專有名詞

| 英文 | 中文說明 |
| --- | --- |
| Arithmetic Coding（AC） | 算術編碼。 |
| Cumulative Interval／Probability | 依 symbol 排序累積的區間／機率邊界。 |
| Renormalization | 輸出或延後處理可釋出的 bits，重新縮放區間。 |
| Pending Bit／Np | 暫時無法決定值、但已由區間移出的 bit／其數量。 |
| Codeword／Bitstream | 編碼結果／按產生或消費順序排列的位元序列。 |
| Padding | 為達到固定輸出長度而補入的 bits。 |
| Truncation／Round Down | 捨去額外精度、向下取整，不是四捨五入。 |
| Beat | 一次有效輸出；本作業 iot_out 每次為 128 bits。 |
| Gate-Level Simulation（GLS） | 使用合成後 netlist，通常搭配 SDF 的模擬。 |
| Clock Gating／ICG | 時脈閘控／integrated clock-gating cell。 |
| Black Box／Unresolved Reference | 無法解析或連結的模組／cell reference，可能漏算 timing 或 power。 |
| P1／P2／Hidden Pattern | 公開測資／評分使用的隱藏測資設定。 |