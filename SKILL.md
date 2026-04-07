---
name: ai-pricing-monitor
description: 每12小时自动扫描130+个AI产品定价页，检测变动并写入飞书多维表格和扫描日志
---

## AI 产品定价监控 — 自动扫描任务

你是一个 AI 产品定价监控系统。每次运行时，扫描 130+ 个 AI 产品的官网定价页面，检测价格变动，并将变更写入飞书多维表格。

---

### 第一步：读取基线数据

从工作目录查找 `pricing_baseline.json` 文件。如果找不到，尝试以下路径：
- 当前目录下
- `~/claude - AI产品定价/pricing_baseline.json`
- `~/AI产品PM landing/pricing_baseline.json`

用 Python 解析 JSON 获取以下关键结构：

**`monitored_products`** — 每个产品包含：
- `url`: 定价页 URL
- `category`: 品类（简写，如 "AI 图像/视频"）
- `region`: 区域（海外/国内）
- `company`: 厂商
- `tiers`: 当前已知定价档位（key=档位名, value=价格描述）
- `content_hash`: 上次扫描的页面内容哈希
- `auto_scan`: 是否自动扫描（false 的跳过）
- `last_changed`: 上次变动日期
- `scan_priority`: 扫描优先级（1=最高, 2=中, 3=低）

**`category_mapping`** — 品类名映射字典：
- key = baseline 中的 category 简写
- value = `{feishu_name, table_id}`（飞书全称 + 对应品类明细表 ID）
- 写入飞书时，**必须使用 `feishu_name`** 而非 baseline 简写

**`scan_log_table_id`** — 扫描日志表 ID（`tblrHS5EJj2CJyuo`）

---

### 第二步：确定扫描工具链

按以下优先级选择页面抓取工具（每次扫描开始时先测试可用性）：

**优先级 1 — WebFetch（最快、最精确）**
- 先对 3 个测试 URL 执行 WebFetch：`github.com/features/copilot/plans`、`claude.com/pricing`、`mistral.ai/pricing`
- 如果 ≥2 个成功 → 使用 WebFetch 作为主要抓取工具
- 如果大面积失败（egress proxy 封禁）→ 降级到优先级 2

**优先级 2 — Claude in Chrome MCP（DOM 级抓取）**
- 工具: `mcp__Claude_in_Chrome__navigate` + `mcp__Claude_in_Chrome__get_page_text`
- 逐个打开定价页并提取文本内容
- 比 WebFetch 慢但不受 egress proxy 限制
- 如果 Chrome 扩展未连接 → 降级到优先级 3

**优先级 3 — WebSearch（兜底方案）**
- 对每个品类执行 `"[品牌] pricing change [year]"` 搜索
- 只能捕捉有新闻报道的较大变动，小幅调价可能遗漏
- 无法计算 content_hash，跳过 Phase 1 直接做 Phase 2

在扫描报告中注明实际使用的工具链。

---

### 第三步：两阶段扫描

**扫描顺序**：严格按 `scan_priority` 排序执行——先扫完全部 P1 产品，再扫 P2，最后 P3。这样即使因 token/时间限制中断，也能保证高价值品类已覆盖。

#### Phase 1 — 轻量探测

对每个 `auto_scan=true` 的产品：
1. 用选定的抓取工具获取其 `url` 的页面内容
2. 如果 fetch 失败（403/超时/无内容），记录失败并跳过
3. 计算内容的 MD5 hash（取页面中与价格相关的核心文本部分，去除广告/导航等噪音）
4. 与 `content_hash` 对比：
   - **Hash 未变（且非空）** → 跳过（价格未变）
   - **Hash 变化** → 进入 Phase 2
   - **Hash 为空**（首次扫描该产品）→ **仅填充 hash，不触发 Phase 2**。这是"基线初始化"模式：将当前 hash 写入 baseline，提取当前定价写入 tiers，但不产生变更记录。

**如果使用 WebSearch 兜底**：跳过 Phase 1，直接对每个品类批量搜索变动信息，进入 Phase 2 分析。

#### Phase 2 — 深度分析（仅对 hash 变化的产品）

1. 从页面内容中提取所有定价信息：
   - 档位名称（Free/Basic/Pro/Enterprise 等）
   - 价格（月付/年付/按量）
   - 计费方式
2. 与基线 `tiers` 逐项对比，识别变动：
   - **涨价**: 同档位价格上涨
   - **降价**: 同档位价格下降
   - **新增档位**: 新出现的定价层级
   - **移除档位**: 档位消失
   - **产品重构**: 档位名称/结构大幅变化
   - **计费模式变更**: 从订阅变按量等

#### 即时二次确认机制

检测到疑似变动后，**当场立即二次确认**，不等待下次扫描：

1. 检测到变动后，等待 10-15 秒
2. **重新抓取同一 URL**（用相同工具），再次提取定价信息
3. 对比两次提取结果：
   - **两次一致** → 确认为真实变更，写入飞书
   - **两次不一致**（如第二次恢复原值）→ 标记为 `pending_change`，写入 baseline 的 `pending_change` 字段，附带 `pending_since: YYYY-MM-DD`
   - **第二次 fetch 失败** → 信任第一次结果，但标记 `confirm_method: single_fetch`
4. `pending_change` 过期规则：
   - 下次扫描仍检测到同样变动 → 确认为真实变更
   - 超过 **7 天**未二次触发 → 自动升级为"需人工核实"，在扫描报告中高亮提示
   - 下次扫描该产品价格恢复原值 → 清除 pending

---

### 第四步：写入飞书

#### 1. 定价变更记录表（每条确认的变更一行）
```
工具: mcp__lark-mcp__bitable_v1_appTableRecord_create
参数:
  path: {app_token: "OzoybmkRxaiMl8sBxjUcitpgnVb", table_id: "tblUauXwu6z1UmRn"}
  data: {fields: {
    "变更日期": "YYYY-MM-DD",
    "品类": "飞书全称(从category_mapping获取feishu_name)",
    "区域": "海外/国内",
    "品牌": "产品品牌名",
    "档位": "变更的档位名",
    "变更字段": "价格/档位/计费模式",
    "旧值": "旧价格或旧值",
    "新值": "新价格或新值",
    "变更类型": "涨价/降价/新增档位/移除档位/产品重构/计费模式变更",
    "数据来源": "自动扫描"
  }}
  useUAT: true
```

**品类名写入规则**：
- 从 baseline 的 `category_mapping` 中查找对应的 `feishu_name`
- 例：baseline 中 category="AI 图像/视频" → 写入飞书时用 "AI 图像视频生成"
- 例：baseline 中 category="AI Agent" → 写入飞书时用 "AI Agent 自动化"

#### 2. 扫描日志表（每次扫描一行）
```
工具: mcp__lark-mcp__bitable_v1_appTableRecord_create
参数:
  path: {app_token: "OzoybmkRxaiMl8sBxjUcitpgnVb", table_id: "tblrHS5EJj2CJyuo"}
  data: {fields: {
    "扫描日期": 毫秒时间戳,
    "扫描覆盖数": 总产品数,
    "成功扫描数": 成功抓取的产品数,
    "检测变动数": 确认变更的产品数,
    "待确认数": pending 的产品数,
    "失败/跳过数": fetch失败+auto_scan=false的产品数,
    "扫描方式": "WebFetch+WebSearch / 仅WebSearch / Chrome MCP / 混合模式",
    "变更摘要": "简要描述本次检测到的主要变更",
    "失败产品列表": "列出fetch失败的产品名",
    "备注": "任何异常情况说明"
  }}
  useUAT: true
```

#### 3. 更新本地 baseline JSON
- 更新变更产品的 `tiers`、`content_hash`、`last_changed`
- 清除已确认的 `pending_change`
- 对首次扫描（hash 为空）的产品：填充 `content_hash` 和 `tiers`
- 更新 `last_updated` 时间戳
- 写回 `pricing_baseline.json`
- **同步到两个存储位置**：
  - `~/claude - AI产品定价/pricing_baseline.json`
  - `~/AI产品PM landing/pricing_baseline.json`

---

### 第五步：生成扫描报告 + 发送链接

扫描完成后，输出以下内容：

#### 扫描报告（直接在对话中输出）
```
## AI 定价扫描报告 — YYYY-MM-DD HH:MM

**扫描覆盖**: X/130 产品成功扫描
**检测到变动**: Y 个产品有定价变化
**失败/跳过**: Z 个产品无法访问
**扫描工具**: WebFetch / WebSearch / Chrome MCP / 混合

### 确认的变更
| 品牌 | 品类 | 变更类型 | 详情 |
|------|------|----------|------|
| ... | ... | ... | ... |

### 待确认（pending）
| 品牌 | 品类 | 疑似变更 | pending 天数 |
|------|------|----------|-------------|
| ... | ... | ... | ... |

### 需人工核实（pending > 7天）
| 品牌 | 品类 | 疑似变更 | 首次发现 |
|------|------|----------|----------|
| ... | ... | ... | ... |

### 无法访问的产品
- ...（列出 fetch 失败的产品及原因）
```

#### 必须附上的飞书链接
每次扫描完成后，**必须**在最终输出中附上：
- **定价变更记录表**：`https://my.feishu.cn/base/OzoybmkRxaiMl8sBxjUcitpgnVb?table=tblUauXwu6z1UmRn`
- **扫描日志表**：`https://my.feishu.cn/base/OzoybmkRxaiMl8sBxjUcitpgnVb?table=tblrHS5EJj2CJyuo`

如果本次扫描还创建了新的飞书文档，也一并附上文档链接。

---

### 注意事项

1. **跳过 auto_scan=false 的 6 个产品**: OpenAI API, Midjourney, Ideogram, Udio, DeepL, D-ID（这些需要手动检查）
2. **速率控制**: 每次 WebFetch 之间间隔适当，避免被目标网站封禁
3. **容错**: 单个产品 fetch 失败不应中断整个扫描流程
4. **效率优先**: 如果 hash 未变则跳过深度分析，节省 token
5. **品类名映射**: 写入飞书时必须使用 `category_mapping` 中的 `feishu_name`，不要使用 baseline 简写
6. **数据来源字段**: 自动扫描写入时统一标注「自动扫描」
7. **扫描优先级**: 严格按 `scan_priority` 1→2→3 的顺序执行，确保 LLM API / AI 助手 / AI 编程工具这三个品类始终优先完成
8. **基线初始化**: 对 `content_hash` 为空的产品，首次扫描仅填充 hash 和 tiers，不产生变更记录
9. **即时确认**: 检测到变动后当场二次抓取确认，不延迟到下次扫描
10. **pending 过期**: 超过 7 天未二次确认的 pending 在报告中标记为"需人工核实"