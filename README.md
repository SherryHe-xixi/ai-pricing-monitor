# AI 产品定价监控系统

自动扫描 136 个 AI 产品的定价页面，检测价格变动，并将变更写入飞书多维表格。

## 文件说明

| 文件 | 用途 |
|------|------|
| `pricing_baseline.json` | 核心数据：136 个产品的当前定价基线、hash、扫描配置 |
| `SKILL.md` | 扫描任务定义（Claude Cowork scheduled task 使用） |
| `scan_history/` | 每次扫描的快照日志（JSON 格式） |
| `exports/` | 导出的 Excel 文件 |

## 飞书表格

- **定价变更记录表**: [打开](https://my.feishu.cn/base/OzoybmkRxaiMl8sBxjUcitpgnVb?table=tblUauXwu6z1UmRn)
- **扫描日志表**: [打开](https://my.feishu.cn/base/OzoybmkRxaiMl8sBxjUcitpgnVb?table=tblrHS5EJj2CJyuo)

## 运行方式

本系统通过 Claude Cowork 的 Scheduled Task 自动运行，每 12 小时执行一次扫描。

扫描流程：
1. 读取 `pricing_baseline.json` 获取基线数据
2. 使用 WebFetch / WebSearch 抓取各产品定价页
3. 对比 hash 检测变动，二次确认后写入飞书
4. 更新 baseline 并同步到本仓库

## 在新电脑上同步

```bash
git clone https://github.com/YOUR_USERNAME/ai-pricing-monitor.git
```

然后在 Claude Cowork 中挂载该文件夹即可恢复全部扫描配置。

## 品类覆盖

共 13 个品类、136 个产品：

- LLM API（24 个）
- AI 助手（18 个）
- AI 编程工具（17 个）
- AI 图像视频生成（10 个）
- AI 企业套件办公（12 个）
- AI 搜索（5 个）
- AI Agent 自动化（9 个）
- AI 设计工具（7 个）
- AI 音频语音音乐（6 个）
- AI 数据分析（7 个）
- AI 教育（7 个）
- AI 翻译（7 个）
- AI 数字人视频分身（7 个）
