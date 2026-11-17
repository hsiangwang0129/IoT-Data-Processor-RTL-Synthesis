# HW4 IOTDF 實作規劃

更新日期：2026-11-18

## 1. 目標與規格

完成可合成的 IOTDF，先確保四種功能與官方 golden 逐 bit 相符，再優化功耗、時間與面積。不硬編碼答案，不更動官方 golden。

| 功能 | fn_sel | 每組輸入 | 每組輸出 | PDF 指定組數 |
| --- | --- | --- | --- | --- |
| F1 DES 加密 | 3'b001 | 64-bit key + 64-bit plaintext | key + 64-bit ciphertext | 64 |
| F2 DES 解密 | 3'b010 | 64-bit key + 64-bit ciphertext | key + 64-bit plaintext | 64 |
| F3 算術編碼 | 3'b011 | 1024 bits，256 個 4-bit symbols | 1024 bits，8 個輸出 words | 8 |
| F4 算術解碼 | 3'b100 | 128-bit PMF + 1024-bit 碼流 | 1024 bits，8 個輸出 words | 2 |

- Top module 名稱為 IOTDF，維持原始介面。
- 正緣同步，rst 為非同步高有效 reset；fn_sel 在同一次模擬中不變。
- 輸入每次 8 bits，每個 128-bit word 由低位元組開始送入。
- busy 控制輸入暫停，valid 標示有效的 128-bit iot_out。
- DES 的輸入與輸出高 64 bits 都是原始 key，低 64 bits 是處理資料。
- F3 先處理 symbol 0，即第一個輸入 byte 的低 nibble；最早產生的碼流 bit 放在第一個輸出 word 的 bit 0。
- F4 先接收 P(0) 至 P(15)，再接收碼流；依 PDF 的反向排列還原碼流順序。
- 最佳化目標為 (P1*T1 + P2*T2 + P3*T3 + P4*T4) * Area，數值越小越好；效能計分必須通過 hidden patterns。

## 2. 初始檔案檢查

已閱讀兩份 PDF、初始文字檔、8 份測資與 14 份 Excel 查表。

| 檔案或目錄 | 現況與後續工作 |
| --- | --- |
| [IOTDF.v](1151_hw4/01_RTL/IOTDF.v) | 只有介面，尚無實作。 |
| [RTL file list](1151_hw4/01_RTL/rtl_01.f) | 若拆分設計，需補齊所有 RTL。 |
| [RTL 執行腳本](1151_hw4/01_RTL/runall_rtl) | 使用 VCS 執行 p1 的 F1 至 F4。 |
| [testfixture.v](1151_hw4/00_TESTBED/testfixture.v) | timeout 為 100,000 cycles，比 PDF 的 1,000,000 嚴格；以較嚴格者為設計目標。 |
| [公開測資](1151_hw4/00_TESTBED/pattern1_data) | F1/F2 各 64 組、F3 為 8 組；F4 檔案有 8 組，但 p1+F4 只使用前 2 組。 |
| [pattern2_data](1151_hw4/00_TESTBED/pattern2_data) | 空目錄，不能視為已取得 hidden patterns。 |
| [DES 查表](1151_hw4/DES_additional_material) | 6 份 permutation、8 份 S-box；依提供的 Verilog bit index 實作。 |
| [DC 設定](1151_hw4/02_SYN/.synopsys_dc.setup) | 使用 slow.db，需另補 synthesis script。 |
| [SDC](1151_hw4/02_SYN/IOTDF_DC.sdc) | 初始週期 6.5 ns；保留禁止修改的基本環境設定。 |
| [Gate file list](1151_hw4/03_GATE/rtl_03.f) | netlist 位於 03_GATE，但 testbench 的 SDF 指向 02_SYN/Netlist；需統一產物路徑。 |
| [Gate 執行腳本](1151_hw4/03_GATE/runall_syn) | 正式流程執行四功能 SDF gate-level simulation。 |
| [PT 設定](1151_hw4/06_POWER/.synopsys_pt.setup) | 包含 typical、fast，正式流程需符合 worst-case only。 |
| [FSDB 功耗腳本](1151_hw4/06_POWER/pt_script.tcl)、[VCD 功耗腳本](1151_hw4/06_POWER/pt_script_vcd.tcl) | 優先 FSDB，必要時使用 VCD；確認 annotation coverage、單位與報告命名。 |
| [報告模板](1151_hw4/reports/report.txt) | 最後填入正式量測的週期、面積、時間與功耗。 |

## 3. 已有驗證證據與待確認事項

以下為唯讀軟體參考運算，不代表 RTL、gate-level 或 PPA 已通過。

- F1：依 Excel 查表運算，64 筆全部符合 golden。
- F2：依 Excel 查表運算，64 筆全部符合 golden。
- F4：參考解碼運算符合檔案內全部 8 組 golden，包含官方 p1 未使用的後 6 組。
- F3：8 組的一般 renormalization 碼流前綴皆符合 golden，差異已定位於收尾。
- F3：目前觀察到 golden 在該前綴後接一個 0，再補 1。需確認 finalization 與 pending bits 的關係，不直接將測資觀察當成完整規格；必要時向 TA 釐清。
- F4：PDF 固定精度除法與常見 arithmetic decoder 公式在目前資料上皆能解碼，但邊界情況仍需測試，不能宣稱普遍等價。

## 4. 建議基準架構

使用輸入控制、資料緩衝、DES 核心、算術編解碼核心與輸出控制。先採分區塊處理，正確後再評估重疊輸入與計算。

### DES 核心

- F1/F2 共用一套迭代式 round datapath，基準版每 cycle 一輪。
- 每輪使用 8 個平行 S-box；固定 permutation 直接接線。
- 使用兩個 28-bit key 暫存器產生 subkey，避免儲存全部 16 組 subkey。
- 解密先使用 K16，再依反向 key schedule 取得後續 subkey。
- 保留原始 key，正確處理最後一輪左右半部排列。

### 算術編解碼核心

- F3/F4 共用 cumulative table、區間更新乘法器與 renormalization datapath。
- low、high、code 固定 16 bits；range 至少 17 bits，以表示初始值 65536。
- 頻率與 cumulative count 至少 9 bits，以表示 256。
- 乘法保留足夠中間位寬，再做規定的截位；不可在中間運算提前溢位。
- F3 完整接收並統計頻率後，再逐 symbol 編碼；同 cycle 統計兩個相同 nibble 時必須加二。
- 三種 renormalization 依優先順序執行，直到無條件成立才前進至下一個 symbol。
- F4 先使用循序除法器；縮減商位數或改用乘法比較時，另驗證其邊界等價性。

### 緩衝與握手

- 優先分段定址，避免整個 1024-bit register 每 cycle 位移。
- 基準版先保持清楚的輸入與輸出儲存，再評估 register sharing。
- 以實際 testbench 的資料延遲驗證 busy，不漏收已送出的最後一個 byte。
- 計數器只在有效資料被接收或有效結果產生時前進，不硬編碼總測資組數。
- 每個 valid cycle 代表一筆輸出，檢查 word 數量與順序。

## 5. 執行順序與驗收

| 階段 | 工作 | 驗收條件 |
| --- | --- | --- |
| 1. 精確模型 | 固定 byte、symbol、碼流順序、截位與 finalization。 | 四功能逐 bit 符合全部可用 golden，未明確規則有依據。 |
| 2. 控制與 DES | 完成 reset、收送控制、key schedule、16 rounds。 | F1/F2 各 64 筆通過，輸入停頓及跨 block 正確。 |
| 3. F3 | 頻率統計、cumulative table、區間更新、pending bits 與收尾。 | 8 組共 64 個輸出 words 全對，區塊間狀態正確清除。 |
| 4. F4 | PMF 載入、初始 code、除法、symbol 搜尋與補位。 | 官方 2 組通過，獨立驗證環境再通過額外 6 組。 |
| 5. RTL 回歸 | 四功能整合與邊界測試。 | 原始 runall_rtl 全過，無 timeout、額外或遺漏 valid。 |
| 6. 合成與 gate | 補 synthesis script、統一路徑、timing 與 SDF 模擬。 | 無非預期 latch，timing 通過，四功能 gate-level 正確。 |
| 7. PPA 優化 | multiplier sharing、除法加速、緩衝共享、pipeline、clock gating。 | 每次修改皆回歸，依效能指標保留有益修改。 |
| 8. 提交檢查 | 填報告、確認 file lists、整理產物及壓縮檔。 | 解壓後可執行，週期及產物一致，命名符合要求。 |

第一個里程碑：F1/F2 RTL 全過，且 F3/F4 參考模型完整重現 golden。

## 6. 驗證策略與工具分工

- 本機有 Icarus Verilog，可用 VCD 模式做 RTL 功能驗證；目前沒有 VCS、Design Compiler、PrimeTime。
- 正式 RTL 流程、合成、gate-level 模擬及功耗分析在 ADFP 執行。
- 額外測試包含單一 symbol、零頻率、偏斜分布、長 pending、跨 128-bit 輸出邊界、輸入停頓及 reset。
- F4 的 PMF 須符合合法輸入限制；單一 symbol 出現 256 次不能直接用一個 8-bit PMF 欄位表示，不自行發明特殊編碼。
- F4 檢查碼流耗盡後補 1、除法臨界值與 cumulative interval 的開閉邊界。
- 除錯先找第一個錯誤 word、symbol 或 bit，對照區間狀態，不只比較最終輸出。
- 先以 6.5 ns 建立 baseline；正式週期同步反映於 SDC、模擬與報告。
- Clock gating 待功能穩定後評估，使用無毛刺方式並驗證 timing。

## 7. 提交前檢查

- 使用小寫學號命名 studentID_hw4，包含 PDF 指定的 RTL、合成報告、gate netlist/SDF、功耗報告及 report.txt。
- rtl_01.f 包含所有設計檔，沒有本機絕對路徑依賴。
- 報告的功耗、時間與面積均來自實測，不填入預估值。
- 確認 VCD 備援腳本的報告名稱與要求的 F1_4.power 提交產物一致。
- ADFP 與 NTU Cool 提交內容分別依 PDF 檢查，壓縮後確認可正常解壓執行。
- 截止時間：2026-11-24 13:59:59，UTC+8；不接受遲交。