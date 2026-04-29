# LLM Wiki 模式的工程化实现

> 本报告分析 LLM Wiki 项目如何将 Karpathy 的 LLM Wiki 抽象模式工程化为可运行的跨平台桌面应用。面向有计算机基础的读者，对领域特有术语给出简明技术性解释。

---

## 一、原始模式概述

Karpathy 的 [llm-wiki.md](llm-wiki.md) 描述了一个知识管理范式：让 LLM 增量构建并维护一个持久化 Wiki，而非传统 RAG 那样每次查询从头检索。核心主张——**知识编译一次、持续更新，查询时直接引用已编译的结果**。

原始模式定义了三个核心概念：

- **三层架构**：Raw Sources（不可变原始文档）→ Wiki（LLM 生成的互连页面）→ Schema（结构与规则）
- **三大操作**：Ingest（摄入）、Query（查询）、Lint（健康检查）
- **两个导航文件**：`index.md`（内容目录）、`log.md`（操作日志）

原始设计是抽象的——它是一个理念文档，设计上需要复制粘贴给 LLM Agent（如 Claude Code、Codex），由 Agent 与用户协作完成具体实现。

---

## 二、项目整体架构

本项目是一个基于 Tauri（Rust 后端 + React 前端）的跨平台桌面应用，将原始模式的"人与 LLM 协作"从命令行会话工程化为完整的 GUI 系统。

```
用户层：  三栏 UI（知识树 | 聊天 | 预览）+ 图谱可视化 + 设置面板
应用层：  React + Zustand 状态管理 + 流式 LLM 调用
持久层：  文件系统（Markdown + JSON）+ 可选 LanceDB 向量索引
后端层：  Tauri/Rust（文档预处理 + Clip Server + 文件操作）
```

---

## 三、三层架构的实现

### 3.1 Raw Sources 层

**原始理念**：用户策展的原始文档集合，不可变——LLM 只读不写。

**实现**：`raw/sources/` 目录存放源文档，LLM 在摄入时读取但从不修改。

**扩展——多格式预处理**（关键文件：[`src-tauri/src/commands/`](src-tauri/src/commands/)）：

| 格式 | 处理方式 | Rust crate |
|------|----------|------------|
| PDF | 文本提取 | pdf-extract |
| DOCX | 保留结构（标题/粗体/列表/表格） | docx-rs |
| PPTX | ZIP 解压 + XML 逐页提取 | — |
| XLSX/XLS/ODS | 输出 Markdown 表格 | calamine |
| 网页剪藏 | Readability.js 正文提取 + Turndown.js HTML→Markdown | — |
| 图片 | 原生预览（png/jpg/gif/webp/svg） | — |

原始设计仅隐含了文本文件，本项目通过 Rust 后端将预处理能力扩展到 6 种非文本格式。

### 3.2 The Wiki 层

**原始理念**：LLM 拥有此层——创建页面、更新交叉引用、保持一致性。用户只读。

**实现**：`wiki/` 目录下 7 种页面类型，每种有独立子目录和 frontmatter 约定：

| 类型 | 目录 | 用途 |
|------|------|------|
| entity | `wiki/entities/` | 命名事物：人、组织、产品 |
| concept | `wiki/concepts/` | 抽象知识：理论、方法、技术 |
| source | `wiki/sources/` | 每份原始文档的结构化摘要 |
| query | `wiki/queries/` | 研究问题与深度分析 |
| comparison | `wiki/comparisons/` | 横向比较 |
| synthesis | `wiki/synthesis/` | 跨来源综合分析 |
| overview | `wiki/` | 项目全局概览（仅一个） |

每个页面包含 YAML frontmatter（type / title / tags / related / sources / created / updated）和 Markdown 正文（含 `[[wikilink]]` 交叉引用）。

**关键约束**：`sources` 字段必须包含原始源文件名，实现来源可追溯性——这是原始模式中未显式要求但隐含需要的。

### 3.3 The Schema 层

**原始理念**：一个配置文档（如 CLAUDE.md），告诉 LLM 如何构建 Wiki。

**实现**：双文件配置，将结构规则与方向意图分离：

| 文件 | 职责 | 关键文件 |
|------|------|----------|
| `schema.md` | 结构规则：页面类型、命名约定、frontmatter 格式、交叉引用规则、矛盾处理流程 | [`src-tauri/src/commands/project.rs`](src-tauri/src/commands/project.rs) 生成 |
| `purpose.md` | 方向意图：项目目标、关键问题、研究范围、演进中的论点 | 同上 |

**扩展——purpose.md**：原始设计只有 Schema（Wiki 如何运作），本项目新增 purpose.md（Wiki 为何存在）。LLM 在每次摄入和查询时读取两者——schema 约束格式，purpose 约束方向。这是一个原始设计中未显式区分的维度。

### 3.4 模板系统

**原始理念**：LLM Wiki 可应用于多种场景（研究、读书、个人成长等），但未提供场景化配置。

**实现**：5 种预设模板（关键文件：[`src/lib/templates.ts`](src/lib/templates.ts)），每种模板预配置 schema.md + purpose.md + 额外目录：

| 模板 | 额外目录 | 个性化配置 |
|------|----------|------------|
| Research | `wiki/methodology/`, `wiki/findings/`, `wiki/thesis/` | Schema 增加 thesis/methodology/finding 类型；Purpose 聚焦研究问题、假说 |
| Reading | `wiki/characters/`, `wiki/themes/`, `wiki/plot/` | Schema 增加 character/theme/plot 类型 |
| Personal Growth | `wiki/journal/`, `wiki/habits/`, `wiki/goals/` | Schema 增加 journal/habit/goal 类型 |
| Business | `wiki/stakeholders/`, `wiki/metrics/`, `wiki/decisions/` | Schema 增加 stakeholder/metric/decision 类型 |
| General | 无 | 最小化配置 |

---

## 四、Ingest（摄入）的实现

这是原始模式最核心的操作，也是本项目工程化程度最高的环节。

### 4.1 两步思维链摄入

**原始理念**：用户投入新源文档，LLM 读取、提取关键信息、写入多个 Wiki 页面、更新索引、追加日志。

**实现**：将 LLM 工作拆分为两个串行调用，而非单次调用直接生成（关键文件：[`src/lib/ingest.ts`](src/lib/ingest.ts)）：

```
源文档 → Step 1: 分析 → Step 2: 生成 → Step 3: 写文件 → Step 4: 解析 Review → Step 5: 缓存 → Step 6: 嵌入
```

#### Step 1 — Analysis（`buildAnalysisPrompt`）

LLM 读取：源文档 + purpose.md + schema.md + wiki/index.md + wiki/overview.md

输出结构化分析：

- **Key Entities**：关键实体，判断哪些可能已存在于 Wiki（对照 index.md）
- **Key Concepts**：关键概念，与已有页面的关联
- **Main Arguments & Findings**：核心论点与证据强度
- **Connections to Existing Wiki**：与已有知识的关系（加强/挑战/扩展）
- **Contradictions & Tensions**：与已有知识的矛盾
- **Recommendations**：建议创建/更新的页面

设计意图：先让 LLM "思考"再 "动手"，分离理解与生成。单次调用中 LLM 容易跳过分析直接输出，导致生成质量下降——这是 Chain-of-Thought（思维链，即让 LLM 分步推理）的工程实践。

#### Step 2 — Generation（`buildGenerationPrompt`）

LLM 以 Step 1 的分析为上下文，按严格格式输出：

```
---FILE: wiki/entities/transformer.md---
(完整文件内容，含 YAML frontmatter)
---END FILE---

---FILE: wiki/concepts/attention-mechanism.md---
(完整文件内容)
---END FILE---

---REVIEW: missing-page | 知识蒸馏---
文档提到"知识蒸馏"但 Wiki 中无对应页面
OPTIONS: Create Page | Skip
SEARCH: knowledge distillation AI | 知识蒸馏 深度学习
---END REVIEW---
```

格式约束极其严格（prompt 末尾重复强调）：第一个字符必须是 `-`（`---FILE:` 的开头），禁止任何前言、分析散文、markdown 表格——只有 FILE 块和 REVIEW 块。解析器（`FILE_BLOCK_REGEX`）只识别这两种分隔标记，其余文本全部忽略。

REVIEW 块的操作选项仅允许 `Create Page` / `Skip`，防止 LLM 幻觉自定义操作；SEARCH 字段预生成搜索查询，供 Deep Research 直接使用。

#### Step 3 — 文件写入（`writeFileBlocks`）

正则 `FILE_BLOCK_REGEX` 解析 LLM 输出中的文件块，逐个写入磁盘。

保护机制：

- **语言守卫**：对每个 FILE 块做语言检测，与用户设定的输出语言不符的块被丢弃。豁免 log.md（结构性内容）和 sources/entities 页（天然包含跨语言专有名词）
- **日志追加模式**：`wiki/log.md` 采用 append 而非 overwrite
- **来源摘要兜底**：若 LLM 未生成 source summary 页，程序自动用 Step 1 的分析结果创建一个

### 4.2 摄入队列

**原始设计**：用户手动指示 LLM 处理源文档。

**实现**：串行化、持久化、可恢复的任务队列（关键文件：[`src/lib/ingest-queue.ts`](src/lib/ingest-queue.ts)）：

```
IngestTask {
  id: string
  projectId: string    // 稳定 UUID，通过注册表查找当前路径
  sourcePath: string   // 相对于项目根目录
  folderContext: string // 文件夹路径作为 LLM 分类提示
  status: "pending" | "processing" | "done" | "failed"
  retryCount: number
}
```

关键设计决策：

| 决策 | 原因 |
|------|------|
| **串行处理** | 同一时间只有一个 processing 任务，避免并发 LLM 调用导致状态冲突 |
| **磁盘持久化** | 队列状态保存到 `.llm-wiki/ingest-queue.json`，崩溃/重启后通过 `restoreQueue` 恢复 |
| **自动重试** | 失败任务最多重试 3 次（`MAX_RETRIES = 3`） |
| **取消清理** | 取消 processing 任务时，abort LLM 调用 + 删除已写入的半成品文件 |
| **项目切换握手** | `pauseQueue()` 刷盘 → 清空内存 → `restoreQueue()` 加载新项目队列 |
| **排空回调** | 队列排空后自动触发 `sweepResolvedReviews`（审核项自动清理） |

### 4.3 增量缓存

对源文件内容计算 SHA256 哈希，与 `.llm-wiki/ingest-cache.json` 中的记录比对——内容未变则跳过摄入，确保"编译一次"的语义（关键文件：[`src/lib/ingest-cache.ts`](src/lib/ingest-cache.ts)）。

---

## 五、Query（查询）的实现

### 5.1 多阶段检索管线

**原始理念**：LLM 搜索相关页面、阅读、合成答案、引用来源。

**实现**：4 阶段检索管线（关键文件：[`src/components/chat/chat-panel.tsx`](src/components/chat/chat-panel.tsx) `handleSend` 方法 + [`src/lib/search.ts`](src/lib/search.ts) + [`src/lib/graph-relevance.ts`](src/lib/graph-relevance.ts)）：

#### Phase 1 — Tokenized Search

`searchWiki` 在 `wiki/` 和 `raw/sources/` 中搜索：

- 英文：whitespace tokenization + stop word removal
- 中文：CJK bigram tokenization（`注意力机制` → `[注意力, 意力, 力机, 机制]`），兼顾单字匹配

评分函数：

| 信号 | 分值 | 说明 |
|------|------|------|
| Filename exact match | +200 | 文件名与查询完全匹配 |
| Phrase in title | +50 | 标题包含完整查询短语 |
| Phrase in content (per occ) | +20/次 | 内容中查询短语出现次数（上限 10 次） |
| Title token match | +5/token | 标题包含查询中的 token |
| Content token match | +1/token | 内容包含查询中的 token |

#### Phase 1.5 — Vector Semantic Search（可选）

若启用 embedding（关键文件：[`src/lib/embedding.ts`](src/lib/embedding.ts)）：

- 查询文本通过 `/v1/embeddings` 端点获取向量
- 在 LanceDB 中执行 ANN（Approximate Nearest Neighbor，近似最近邻）检索
- 结果合并：已有结果 boost 分数（`score += vr.score * 5`），新结果添加到结果集
- Benchmark：启用后整体 recall 从 58.2% 提升到 71.4%

#### Phase 2 — Graph Expansion

以 Phase 1 的 top 10 搜索结果为种子节点，沿知识图谱做 1-hop 扩展：

- `buildRetrievalGraph` 构建检索图（带 `dataVersion` 缓存）
- `getRelatedNodes` 对每个种子节点取相关性 top-3 邻居
- 过滤阈值：relevance ≥ 2.0

#### Phase 3 — Budget Control

根据用户配置的上下文窗口大小按比例分配：

| 分配项 | 比例 | 说明 |
|--------|------|------|
| Wiki 页面内容 | 60% | 主要知识来源 |
| 聊天历史 | 20% | 对话上下文 |
| Index 页 | 5% | 目录信息 |
| 系统提示 | 15% | 指令与规则 |

单页上限：`MAX_PAGE_SIZE = min(PAGE_BUDGET × 0.3, 30K)`

#### Phase 4 — Context Assembly

页面按优先级填入：

1. **P0**：Title match 页面（搜索结果中 titleMatch=true）
2. **P1**：Content match 页面
3. **P2**：Graph expansion 页面
4. **P3**：Overview 兜底（若前三级无结果）

组装格式：带编号的完整页面内容（非摘要），系统提示含 purpose.md + index.md + 语言指令。LLM 被要求用 [1], [2] 编号引用来源。

### 5.2 四信号相关性模型

衡量两个 Wiki 页面相关性的加权评分系统（关键文件：[`src/lib/graph-relevance.ts`](src/lib/graph-relevance.ts) `calculateRelevance` 函数）：

| 信号 | 权重 | 计算方式 |
|------|------|----------|
| Direct Link（直接链接） | ×3.0 | A→B 或 B→A 存在 `[[wikilink]]` |
| Source Overlap（来源重叠） | ×4.0 | A 和 B 的 frontmatter `sources[]` 交集大小——来自同一源文档的页面强相关 |
| Adamic-Adar（共同邻居） | ×1.5 | `Σ 1/log(degree(z))`，z 为 A 和 B 的共同邻居。高度数邻居的贡献被对数函数衰减，避免"超级节点"放大噪声 |
| Type Affinity（类型亲和） | ×1.0 | 查表获取类型对亲和系数（如 concept↔entity = 1.2，source↔source = 0.5） |

### 5.3 答案回写

**原始理念**：好的答案可以回写为新的 Wiki 页面。

**实现**：`Save to Wiki` 按钮（关键文件：[`src/components/chat/chat-message.tsx`](src/components/chat/chat-message.tsx) `handleSave`）：

1. 从 LLM 回复生成 slug + 日期，写入 `wiki/queries/`
2. 更新 `wiki/index.md`（追加到 ## Queries 节）
3. 追加 `wiki/log.md`
4. 调用 `autoIngest` 对保存的页面执行完整摄入——从中提取实体和概念，回写知识网络

---

## 六、Lint（健康检查）的实现

### 6.1 Structural Lint（结构化检查，纯规则，零 LLM token 消耗）

关键文件：[`src/lib/lint.ts`](src/lib/lint.ts) `runStructuralLint`

| 检查项 | 检测条件 | 严重度 |
|--------|----------|--------|
| Orphan（孤立页） | 无入链——其他页面均未 `[[引用]]` 它 | info |
| No-outlinks（无出链页） | 页面内无 `[[wikilink]]` | info |
| Broken-link（断链） | `[[target]]` 指向不存在的页面（case-insensitive） | warning |

### 6.2 Semantic Lint（语义检查，LLM 驱动）

关键文件：[`src/lib/lint.ts`](src/lib/lint.ts) `runSemanticLint`

LLM 通读所有 Wiki 页面的前 500 字符摘要，输出 `---LINT---` 格式块：

- `contradiction`：跨页面矛盾
- `stale`：过时信息
- `missing-page`：高引用但无专页的概念
- `suggestion`：改进建议

与摄入相同，语义 Lint 也使用分隔标记格式（`---LINT: type | severity | title---` / `---END LINT---`），解析器只识别标记块，忽略 LLM 的其他输出。

---

## 七、知识图谱与图谱洞察

**原始理念**：Obsidian 的 Graph View 是查看 Wiki 形状的最佳方式。原始设计仅依赖 Obsidian 的内置图谱可视化。

### 7.1 图谱构建

关键文件：[`src/lib/wiki-graph.ts`](src/lib/wiki-graph.ts) `buildWikiGraph`

1. 遍历 `wiki/` 目录所有 `.md` 文件
2. 从 frontmatter 提取 title、type、sources；从正文提取 `[[wikilinks]]`
3. Wikilink 解析：大小写不敏感，空格↔连字符兼容（`resolveTarget`）
4. 过滤 `type: query` 节点（研究结果是中间产物）
5. 边去重（无向图）
6. 边权重 = `calculateRelevance(A, B, graph)`
7. 运行 Louvain 社区检测

### 7.2 Louvain 社区检测

> Louvain Algorithm：基于模块度优化的层次聚合社区检测算法，时间复杂度近似 O(n log n)。

自动发现知识聚类——哪些页面在链接拓扑上自然成组。每个社区计算内聚度（cohesion）= 实际内部边数 / 理论最大边数 `n(n-1)/2`。内聚度 < 0.15 且成员 ≥ 3 标记为稀疏社区。

### 7.3 Graph Insights

关键文件：[`src/lib/graph-insights.ts`](src/lib/graph-insights.ts)

**Surprising Connections**（惊奇连接）——检测"意外"的边：

| 信号 | 加分 | 条件 |
|------|------|------|
| Cross-community | +3 | 边跨越社区边界 |
| Cross-type | +1~2 | 边连接不同类型的节点 |
| Peripheral-hub | +2 | 一端 degree ≤ 2，另一端 degree ≥ maxDegree × 0.5 |
| Weak but present | +1 | edge weight < 2 但 > 0 |

综合得分 ≥ 3 才显示。

**Knowledge Gaps**（知识空白）——三种检测：

1. Isolated nodes（degree ≤ 1）：几乎无入链的页面
2. Sparse communities（cohesion < 0.15, size ≥ 3）：某知识领域内部关联不足
3. Bridge nodes（连接 ≥ 3 个社区）：关键枢纽节点

每种 Gap 均可一键触发 Deep Research。

### 7.4 图谱可视化

关键文件：[`src/components/graph/graph-view.tsx`](src/components/graph/graph-view.tsx)

使用 sigma.js + graphology + ForceAtlas2 布局。支持按页面类型或社区着色、悬停高亮邻居、缩放控件、位置缓存。原始设计仅依赖 Obsidian 内置图谱，本项目构建了独立的图谱引擎和交互式可视化。

---

## 八、索引与日志的实现

**原始理念**：

- `index.md`：内容目录，LLM 每次摄入时更新，查询时先读索引再深入
- `log.md`：时间顺序的操作记录，追加模式，前缀格式化以支持简单文本工具解析

**实现**：

| 文件 | 实现方式 |
|------|----------|
| `wiki/index.md` | 按页面类型分组的目录，每项 `[[page-slug]] — 一行描述`。Step 2 生成时自动更新。查询管线 Phase 3 分配 5% 预算专门加载索引，超过预算时按查询 token 相关性裁剪 |
| `wiki/log.md` | 逆时间顺序追加，格式 `## YYYY-MM-DD`，追加模式写入（不覆盖历史）。语言守卫对 log.md 豁免语言检测 |

---

## 九、Wikilink 丰富化

**原始理念**：交叉引用是 Wiki 的核心价值，原始设计依赖 LLM 在生成时主动添加 `[[wikilink]]`。

**问题**：直接让 LLM 重写页面添加链接会导致模型"趁机"改写内容（改写句子、翻译、添加内容），中小模型尤为严重。

**解决方案**——LLM 只返回替换清单，程序做安全替换（关键文件：[`src/lib/enrich-wikilinks.ts`](src/lib/enrich-wikilinks.ts)）：

1. LLM 输出 JSON：`{"links": [{"term": "注意力机制", "target": "attention-mechanism"}, ...]}`
2. 程序在原文中定位 `term` 的首次出现（排除 frontmatter 区域和已有 `[[...]]` 包裹）
3. 替换为 `[[target|term]]`（若 term 与 target 大小写相同则 `[[term]]`）

保证：

- 原文内容 byte-level 不变，仅插入 `[[` 和 `]]` 等符号
- frontmatter 区域完全不受影响
- 每个 target 最多链接一次，避免重复
- 即使 LLM 输出异常，最坏结果也只是"链接未添加"，不会破坏页面内容

---

## 十、审核系统

**原始理念**：原始设计中，人参与循环的方式是审查 LLM 的输出并指导下一步。

**实现**：结构化审核队列 + 自动清理机制。

### 10.1 生成

LLM 在摄入 Step 2 输出 REVIEW 块，类型包括：

| 类型 | 含义 | 操作选项 |
|------|------|----------|
| contradiction | 知识冲突 | Create Page / Skip |
| duplicate | 疑似重复 | Create Page / Skip |
| missing-page | 缺失页面 | Create Page / Skip |
| suggestion | 研究建议 | Create Page / Skip |
| confirm | 待确认 | Create Page / Skip |

每个审核项包含预定义操作、受影响页面列表、预生成的搜索查询。关键文件：[`src/stores/review-store.ts`](src/stores/review-store.ts)

### 10.2 自动清理（Sweep）

关键文件：[`src/lib/sweep-reviews.ts`](src/lib/sweep-reviews.ts) `sweepResolvedReviews`

摄入队列排空后自动触发：

**Stage 1 — Rule-based matching**（O(1) 查找，零 token 消耗）：

- `missing-page`：检查候选名称是否已存在于 Wiki 索引
- `duplicate`：检查 affectedPages 是否仍有全部存在

**Stage 2 — LLM judgment**（批量判断，有限 token 消耗）：

- 对 Stage 1 未解决的剩余项，按 `JUDGE_BATCH_SIZE = 40` 分批发给 LLM
- LLM 返回 `{"resolved": ["id1", "id2"]}` JSON
- 上限：最多 `MAX_JUDGE_BATCHES = 5` 批，避免无限制 token 消耗

---

## 十一、深度研究

**原始设计未涉及**。自动化的网络搜索 + LLM 合成 + 二次摄入的闭环研究流程。

关键文件：[`src/lib/deep-research.ts`](src/lib/deep-research.ts)

```
用户/Review 触发 → 优化研究主题 → Tavily API 搜索 → LLM 合成带 [[wikilink]] 的研究页面
                                                          ↓
                                              保存到 wiki/queries/
                                                          ↓
                                              调用 autoIngest → 提取实体和概念 → 回写知识网络
```

"研究反哺知识库"——这是对原始模式的重要扩展：原始模式的知识只来源于用户投入的源文档，Deep Research 让 Wiki 自主获取外部知识并整合。

---

## 十二、Chrome 扩展与剪藏

**原始理念**：Obsidian Web Clipper 是快速获取源文档的有用工具。

**实现**：完整的剪藏系统：

| 组件 | 文件 | 功能 |
|------|------|------|
| Chrome Extension | [`extension/`](extension/) | Readability.js 正文提取 + Turndown.js HTML→Markdown + 项目选择器 |
| Clip Server | [`src-tauri/src/clip_server.rs`](src-tauri/src/clip_server.rs) | Rust tiny_http，端口 19827，4 个端点（/clip, /clips/pending, /project, /projects） |
| Clip Watcher | [`src/lib/clip-watch.ts`](src/lib/clip-watch.ts) | 前端每 3 秒轮询 `/clips/pending`，检测到新剪藏后自动 `enqueueIngest` |

---

## 十三、持久化与状态管理

| 数据 | 存储位置 | 格式 | 关键文件 |
|------|----------|------|----------|
| LLM 配置 | Tauri Store | JSON | [`src/stores/wiki-store.ts`](src/stores/wiki-store.ts) |
| 摄入队列 | `.llm-wiki/ingest-queue.json` | JSON | [`src/lib/ingest-queue.ts`](src/lib/ingest-queue.ts) |
| 摄入缓存 | `.llm-wiki/ingest-cache.json` | JSON | [`src/lib/ingest-cache.ts`](src/lib/ingest-cache.ts) |
| 审核项 | `.llm-wiki/review.json` | JSON | [`src/stores/review-store.ts`](src/stores/review-store.ts) |
| 聊天历史 | `.llm-wiki/chats/{id}.json` | JSON | [`src/stores/chat-store.ts`](src/stores/chat-store.ts) |
| 项目身份 | `.llm-wiki/project-identity.json` | JSON | [`src/lib/project-identity.ts`](src/lib/project-identity.ts) |
| 向量索引 | LanceDB（项目目录下） | 二进制 | [`src/lib/embedding.ts`](src/lib/embedding.ts) |

**dataVersion**：单调递增计数器（[`src/stores/wiki-store.ts`](src/stores/wiki-store.ts) `bumpDataVersion`），Wiki 内容变更时 bump。用于图缓存失效和 UI 响应式刷新——整个系统围绕"变更检测"设计。

---

## 十四、关键文件索引

按功能域组织的核心源文件清单：

### 摄入系统

| 文件 | 职责 |
|------|------|
| [`src/lib/ingest.ts`](src/lib/ingest.ts) | 两步思维链摄入主逻辑、FILE/REVIEW 块解析、语言守卫 |
| [`src/lib/ingest-queue.ts`](src/lib/ingest-queue.ts) | 串行摄入队列、磁盘持久化、崩溃恢复、项目切换握手 |
| [`src/lib/ingest-cache.ts`](src/lib/ingest-cache.ts) | SHA256 增量缓存 |
| [`src/lib/templates.ts`](src/lib/templates.ts) | 5 种场景模板定义 |

### 查询系统

| 文件 | 职责 |
|------|------|
| [`src/lib/search.ts`](src/lib/search.ts) | 分词搜索（英文 whitespace + 中文 CJK bigram）、评分函数、向量搜索合并 |
| [`src/lib/graph-relevance.ts`](src/lib/graph-relevance.ts) | 四信号相关性模型、检索图构建、wikilink 解析 |
| [`src/lib/embedding.ts`](src/lib/embedding.ts) | 向量嵌入、LanceDB 操作、ANN 检索 |
| [`src/components/chat/chat-panel.tsx`](src/components/chat/chat-panel.tsx) | 4 阶段检索管线编排（Phase 1-4）、预算控制、上下文组装 |
| [`src/components/chat/chat-message.tsx`](src/components/chat/chat-message.tsx) | Save to Wiki、答案回写 |

### 知识图谱

| 文件 | 职责 |
|------|------|
| [`src/lib/wiki-graph.ts`](src/lib/wiki-graph.ts) | 图谱构建、Louvain 社区检测、内聚度计算 |
| [`src/lib/graph-insights.ts`](src/lib/graph-insights.ts) | Surprising Connections 检测、Knowledge Gaps 检测 |
| [`src/components/graph/graph-view.tsx`](src/components/graph/graph-view.tsx) | 图谱可视化（sigma.js + ForceAtlas2）、Insights 交互 |

### 质量保障

| 文件 | 职责 |
|------|------|
| [`src/lib/lint.ts`](src/lib/lint.ts) | Structural Lint（orphan/broken-link/no-outlinks）+ Semantic Lint（LLM 驱动） |
| [`src/lib/enrich-wikilinks.ts`](src/lib/enrich-wikilinks.ts) | Wikilink 安全替换丰富化 |
| [`src/lib/sweep-reviews.ts`](src/lib/sweep-reviews.ts) | 审核项自动清理（规则 + LLM 批量判断） |
| [`src/stores/review-store.ts`](src/stores/review-store.ts) | 审核项状态管理、去重合并 |

### 扩展功能

| 文件 | 职责 |
|------|------|
| [`src/lib/deep-research.ts`](src/lib/deep-research.ts) | Deep Research（Tavily 搜索 → LLM 合成 → 自动摄入） |
| [`src/lib/clip-watch.ts`](src/lib/clip-watch.ts) | 前端 Clip 轮询 |
| [`src-tauri/src/clip_server.rs`](src-tauri/src/clip_server.rs) | Rust Clip Server |
| [`extension/`](extension/) | Chrome 扩展（Readability.js + Turndown.js） |

### 项目与状态

| 文件 | 职责 |
|------|------|
| [`src/stores/wiki-store.ts`](src/stores/wiki-store.ts) | 全局状态（项目、LLM 配置、dataVersion） |
| [`src/stores/chat-store.ts`](src/stores/chat-store.ts) | 多会话聊天状态 |
| [`src/lib/project-identity.ts`](src/lib/project-identity.ts) | UUID→路径映射、项目迁移支持 |
| [`src/lib/persist.ts`](src/lib/persist.ts) | 跨重启状态持久化 |
| [`src-tauri/src/commands/project.rs`](src-tauri/src/commands/project.rs) | Rust 项目创建、schema.md/purpose.md 生成 |

---

## 十五、与原始模式的对照总览

| 原始理念 | 本项目实现 | 关键文件 |
|----------|------------|----------|
| Raw Sources 不可变层 | `raw/sources/` + Rust 多格式预处理 | [`src-tauri/src/commands/`](src-tauri/src/commands/) |
| The Wiki LLM 生成层 | `wiki/` 7 种页面类型 + 两步思维链摄入 | [`src/lib/ingest.ts`](src/lib/ingest.ts) |
| The Schema 规则层 | `schema.md` + `purpose.md`（新增方向意图层） | [`src/lib/templates.ts`](src/lib/templates.ts) |
| Ingest 操作 | 串行摄入队列 + 两步 CoT + Review 块 + 增量缓存 | [`src/lib/ingest-queue.ts`](src/lib/ingest-queue.ts) |
| Query 操作 | 4 阶段检索管线 + 引用追踪 + 答案回写 | [`src/components/chat/chat-panel.tsx`](src/components/chat/chat-panel.tsx) |
| Lint 操作 | 结构化 Lint（规则）+ 语义 Lint（LLM）+ 图谱洞察 | [`src/lib/lint.ts`](src/lib/lint.ts) |
| index.md 目录 | `wiki/index.md` + 查询管线预算加载 | [`src/lib/ingest.ts`](src/lib/ingest.ts) |
| log.md 日志 | `wiki/log.md` 追加模式 + 语言豁免 | [`src/lib/ingest.ts`](src/lib/ingest.ts) |
| Obsidian 兼容 | `.obsidian/` 目录 + `[[wikilink]]` + 内置 Graph View | [`src/components/graph/graph-view.tsx`](src/components/graph/graph-view.tsx) |
| Web Clipper | Chrome 扩展 + Clip Server + 自动摄入 | [`extension/`](extension/), [`src-tauri/src/clip_server.rs`](src-tauri/src/clip_server.rs) |
| （未提及） | Deep Research 网络搜索闭环 | [`src/lib/deep-research.ts`](src/lib/deep-research.ts) |
| （未提及） | Review 审核系统 + Sweep 自动清理 | [`src/lib/sweep-reviews.ts`](src/lib/sweep-reviews.ts) |
| （未提及） | Wikilink 安全替换丰富化 | [`src/lib/enrich-wikilinks.ts`](src/lib/enrich-wikilinks.ts) |
| （未提及） | 5 种场景模板 | [`src/lib/templates.ts`](src/lib/templates.ts) |
| （未提及） | Louvain 社区检测 + 四信号相关性模型 | [`src/lib/wiki-graph.ts`](src/lib/wiki-graph.ts), [`src/lib/graph-relevance.ts`](src/lib/graph-relevance.ts) |

---

## 十六、核心判断

本项目忠实实现了 Karpathy LLM Wiki 模式的全部核心理念——三层架构、三大操作、索引与日志、交叉引用、Obsidian 兼容，并在每个环节进行了深度工程化：

1. **可靠性**：将"人手动指示 LLM"的松散流程工程化为串行队列 + 磁盘持久化 + 崩溃恢复 + 自动重试
2. **安全性**：语言守卫防止输出语言偏移；Wikilink 丰富化保证 byte-level 内容不变；REVIEW 块操作选项白名单防止 LLM 幻觉
3. **可扩展性**：向量语义搜索作为可选插件；模板系统支持多场景；`dataVersion` 驱动缓存失效

同时通过 purpose.md 方向意图层、Deep Research 闭环、审核系统、图谱洞察等扩展，在原始设计的基础上增加了可操作性、可靠性和场景适应性。
