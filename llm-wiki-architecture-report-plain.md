# LLM Wiki 运行机制与工作原理

> 本报告面向有计算机基础的读者，对领域特有术语给出简明解释，保持技术准确性。

---

## 一、项目定位

LLM Wiki 是一个跨平台桌面应用，核心目标：**将用户文档自动转化为结构化、互连的知识库**。

与传统 RAG（Retrieval-Augmented Generation，检索增强生成）每次查询从头检索不同，LLM Wiki 采用**编译式知识管理**——LLM 增量构建并维护一个持久化 Wiki，知识编译一次、持续更新，查询时直接引用已编译的结果。

三层架构设计（源自 Karpathy 的 LLM Wiki 模式）：

```
Raw Sources（不可变原始文档）→ Wiki（LLM 生成页面）→ Schema（结构与规则）
```

---

## 二、技术栈

| 层 | 技术 | 说明 |
|---|---|---|
| 桌面容器 | Tauri v2 | Rust 后端处理文件 I/O、PDF 解析、向量存储等系统级操作 |
| 前端 | React 19 + TypeScript + Vite | SPA 架构，负责 UI 渲染和业务逻辑编排 |
| UI 组件 | shadcn/ui + Tailwind CSS v4 | 组件库 + 原子化 CSS |
| 编辑器 | Milkdown | 基于 ProseMirror 的 WYSIWYG Markdown 编辑器 |
| 知识图谱 | sigma.js + graphology + ForceAtlas2 | 图可视化 + 图数据结构 + 力导向布局算法 |
| 向量数据库 | LanceDB（Rust，嵌入式） | 可选的 ANN（Approximate Nearest Neighbor）向量检索引擎 |
| 状态管理 | Zustand | 轻量级全局状态管理，替代 Redux |
| LLM 通信 | 流式 fetch | 支持 OpenAI / Anthropic / Google / Ollama / MiniMax / Custom |
| 网络搜索 | Tavily API | 专为 AI Agent 设计的搜索 API |
| i18n | react-i18next | 国际化：英文 + 中文 |

前后端通信：前端通过 `@tauri-apps/api/core` 的 `invoke` IPC 机制调用 Rust 后端的 Tauri Command，实现文件读写、目录遍历、文档预处理、向量操作等。

---

## 三、Wiki 生成机制（核心）

### 3.1 项目创建

用户选择模板后，Rust 后端 `create_project` 命令执行初始化：

1. 创建标准目录结构：

```
project/
├── raw/sources/          ← 原始文档（不可变）
├── raw/assets/           ← 本地图片等资源
├── wiki/entities/        ← 实体页：人、组织、产品等命名事物
├── wiki/concepts/        ← 概念页：理论、方法、技术等抽象知识
├── wiki/sources/         ← 来源摘要页：每份原始文档的结构化摘要
├── wiki/queries/         ← 研究页：待探索问题与深度研究结果
├── wiki/comparisons/     ← 对比页：横向比较分析
├── wiki/synthesis/       ← 综合页：跨来源的总结分析
├── schema.md             ← 结构规则：定义页面类型、命名约定、frontmatter 格式
├── purpose.md            ← 项目意图：定义知识库的目标与范围
└── .obsidian/            ← Obsidian 兼容配置（可直接作为 Obsidian Vault 打开）
```

2. 生成关键初始文件：
   - `schema.md`：Wiki 的"元规则"，LLM 每次生成时读取以遵循格式约束
   - `purpose.md`：项目的"目标声明"，LLM 每次摄入和查询时读取以保持方向一致
   - `wiki/index.md`：内容目录页
   - `wiki/log.md`：操作日志（chronological log）
   - `wiki/overview.md`：全局概览

3. 模板系统（5 种预设）：Research / Reading / Personal Growth / Business / General，每种模板预配置 schema.md、purpose.md 和额外的 wiki 子目录。

### 3.2 两步思维链摄入（Two-Step Chain-of-Thought Ingest）

> **Ingest（摄入）**：将一份源文档转化为 Wiki 页面的完整过程。
> **Chain-of-Thought（思维链）**：让 LLM 分步推理而非直接输出，显著提升生成质量。

核心创新：将 LLM 工作拆分为两个串行调用，而非单次调用直接生成。

```
源文档 → Step 1: 分析 → Step 2: 生成 → Step 3: 写文件 → Step 4: 解析 Review → Step 5: 缓存 → Step 6: 嵌入
```

#### Step 1 — Analysis（分析阶段）

LLM 读取：源文档 + purpose.md + schema.md + wiki/index.md + wiki/overview.md

输出结构化分析，包含：
- **Key Entities**：关键实体（人名、组织、产品），判断哪些可能已存在于 Wiki
- **Key Concepts**：关键概念（理论、方法、技术），与已有页面的关联
- **Main Arguments & Findings**：核心论点与证据强度评估
- **Connections to Existing Wiki**：与已有知识的关系（加强/挑战/扩展）
- **Contradictions & Tensions**：与已有知识的矛盾点
- **Recommendations**：建议创建/更新的页面及侧重方向

设计意图：先让 LLM "思考"再 "动手"，分离理解与生成，避免单次调用中分析不充分导致输出质量下降。

#### Step 2 — Generation（生成阶段）

LLM 以 Step 1 的分析为上下文，按严格格式输出 Wiki 文件：

```
---FILE: wiki/entities/transformer.md---
(完整文件内容，含 YAML frontmatter)
---END FILE---

---FILE: wiki/concepts/attention-mechanism.md---
(完整文件内容)
---END FILE---
```

每个生成的页面包含：
- **YAML Frontmatter**：文件头部的元数据块（用 `---` 界定），记录 type / title / created / updated / tags / related / **sources**
  - `sources` 字段**必须**包含原始源文件名，实现来源可追溯性（source traceability）
- **正文**：Markdown 格式，含 `[[wikilink]]` 交叉引用

同时输出 **REVIEW 块**（审核项）：

```
---REVIEW: missing-page | 知识蒸馏---
文档提到"知识蒸馏"但 Wiki 中无对应页面
OPTIONS: Create Page | Skip
SEARCH: knowledge distillation AI | 知识蒸馏 深度学习
---END REVIEW---
```

关键约束：操作选项仅允许 `Create Page` / `Skip`，防止 LLM 幻觉自定义操作；SEARCH 字段预生成搜索查询，供 Deep Research 直接使用。

#### Step 3 — 文件写入

`writeFileBlocks` 使用正则 `FILE_BLOCK_REGEX` 解析 LLM 输出中的文件块，逐个写入磁盘。

保护机制：
- **语言守卫**：对每个 FILE 块做语言检测，与用户设定的输出语言不符的块被丢弃（跳过 log.md 和 sources/entities 页——这些页面天然包含跨语言专有名词）
- **日志追加模式**：`wiki/log.md` 采用 append 而非 overwrite
- **来源摘要兜底**：若 LLM 未生成 source summary 页，程序自动用 Step 1 的分析结果创建一个

#### Step 4 — 解析 Review 项

`parseReviewBlocks` 从 LLM 输出中提取 REVIEW 块，类型包括：
- `contradiction`：与已有知识矛盾
- `duplicate`：疑似重复页面
- `missing-page`：缺少对应页面
- `suggestion`：研究建议
- `confirm`：需人工确认

添加到 ReviewStore 供用户异步处理。

#### Step 5 — 增量缓存

对源文件内容计算 SHA256 哈希，与 `.llm-wiki/ingest-cache.json` 中的记录比对，内容未变则跳过摄入，节省 LLM token 和时间。

#### Step 6 — 向量嵌入（可选）

若启用了 embedding 配置，对新生成的每个 wiki 页面调用 `embedPage`：通过 OpenAI 兼容的 `/v1/embeddings` 端点获取向量表示，存入 LanceDB。

### 3.3 摄入队列（Ingest Queue）

> 串行化、持久化、可恢复的任务队列，确保 LLM 调用不并发、不丢失。

- **串行处理**：同一时间只有一个任务处于 processing 状态，避免并发 LLM 调用
- **磁盘持久化**：队列状态保存到 `.llm-wiki/ingest-queue.json`，应用崩溃或重启后通过 `restoreQueue` 恢复
- **自动重试**：失败任务最多重试 3 次（`MAX_RETRIES = 3`）
- **取消清理**：取消 processing 任务时，abort LLM 调用 + 删除已写入的半成品文件
- **项目切换握手**：`pauseQueue()` 刷盘当前队列 → 清空内存 → `restoreQueue()` 加载新项目队列
- **排空回调**：队列排空后自动触发 `sweepResolvedReviews`（审核项自动清理）

任务结构：
```typescript
interface IngestTask {
  id: string
  projectId: string    // 稳定 UUID，通过注册表查找当前路径
  sourcePath: string   // 相对于项目根目录
  folderContext: string // 文件夹路径作为 LLM 分类提示
  status: "pending" | "processing" | "done" | "failed"
  retryCount: number
  error: string | null
}
```

### 3.4 文档预处理

Rust 后端 `preprocess_file` 命令将多种格式转为纯文本：

| 格式 | 处理方式 |
|---|---|
| PDF | pdf-extract (Rust crate) |
| DOCX | docx-rs：保留 heading / bold / list / table 等结构 |
| PPTX | ZIP 解压 + XML 解析，逐页提取 |
| XLSX/XLS/ODS | calamine：保留单元格类型，输出 Markdown 表格 |
| 图片 | 原生预览（png/jpg/gif/webp/svg） |
| 网页剪藏 | Readability.js（正文提取）+ Turndown.js（HTML→Markdown） |

---

## 四、知识查询机制

### 4.1 多阶段检索管线（Retrieval Pipeline）

> **Retrieval Pipeline**：将检索过程分解为多个阶段的串行处理流水线，每阶段在前一阶段结果上增量扩展。

当用户在聊天框提问时，`ChatPanel.handleSend` 执行以下管线：

#### Phase 1 — Tokenized Search（分词搜索）

`searchWiki` 在 `wiki/` 和 `raw/sources/` 中搜索：
- 英文：whitespace tokenization + stop word removal
- 中文：CJK bigram tokenization（每个 → [每个, 个…]），兼顾单字匹配
- 评分函数（从高到低）：

| 信号 | 分值 | 说明 |
|---|---|---|
| Filename exact match | +200 | 文件名与查询完全匹配 |
| Phrase in title | +50 | 标题包含完整查询短语 |
| Phrase in content (per occ) | +20/次 | 内容中查询短语出现次数（上限 10 次） |
| Title token match | +5/token | 标题包含查询中的 token |
| Content token match | +1/token | 内容包含查询中的 token |

#### Phase 1.5 — Vector Semantic Search（向量语义搜索，可选）

> **Semantic Search**：基于语义相似度而非关键词匹配的检索方式。通过 embedding 模型将文本映射到高维向量空间，用向量距离衡量语义相似度。

若启用 embedding：
- 查询文本通过 `/v1/embeddings` 端点获取向量
- 在 LanceDB 中执行 ANN（Approximate Nearest Neighbor）检索
- 结果合并到 Phase 1 结果：已有结果 boost 分数（`score += vr.score * 5`），新结果添加到结果集
- Benchmark：启用后整体 recall 从 58.2% 提升到 71.4%

#### Phase 2 — Graph Expansion（图谱扩展）

以 Phase 1 的 top 10 搜索结果为种子节点，沿知识图谱做 1-hop 扩展：
- `buildRetrievalGraph` 构建检索图（带 `dataVersion` 缓存）
- `getRelatedNodes` 对每个种子节点取相关性 top-3 邻居
- 过滤阈值：relevance ≥ 2.0

#### Phase 3 — Budget Control（预算控制）

根据用户配置的上下文窗口大小（4K ~ 1M 字符）按比例分配：

| 分配项 | 比例 | 说明 |
|---|---|---|
| Wiki 页面内容 | 60% | 主要知识来源 |
| 聊天历史 | 20% | 对话上下文 |
| Index 页 | 5% | 目录信息 |
| 系统提示 | 15% | 指令与规则 |

单页上限：`MAX_PAGE_SIZE = min(PAGE_BUDGET * 0.3, 30K)`

#### Phase 4 — Context Assembly（上下文组装）

页面按优先级填入：
1. **P0**：Title match 页面（搜索结果中 titleMatch=true）
2. **P1**：Content match 页面
3. **P2**：Graph expansion 页面
4. **P3**：Overview 兜底（若前三级无结果）

组装格式：带编号的完整页面内容（非摘要），系统提示含 purpose.md + index.md + 语言指令。LLM 被要求用 [1], [2] 编号引用来源。

### 4.2 四信号相关性模型（4-Signal Relevance Model）

> 衡量两个 Wiki 页面相关性的加权评分系统，综合结构信息和语义信息。

| 信号 | 权重 | 计算方式 |
|---|---|---|
| Direct Link（直接链接） | ×3.0 | A→B 或 B→A 存在 `[[wikilink]]`，1 跳可达 |
| Source Overlap（来源重叠） | ×4.0 | A 和 B 的 frontmatter `sources[]` 交集大小，权重最高——来自同一源文档的页面强相关 |
| Adamic-Adar（共同邻居） | ×1.5 | 经典图论指标：`Σ 1/log(degree(z))`，z 为 A 和 B 的共同邻居。高度数邻居贡献被对数函数衰减，避免"超级节点"放大噪声 |
| Type Affinity（类型亲和） | ×1.0 | 查表获取类型对亲和系数（如 concept↔entity = 1.2，source↔source = 0.5），反映不同页面类型间的先验关联强度 |

总分 = Σ(信号值 × 权重)

---

## 五、知识图谱机制

### 5.1 图谱构建

`buildWikiGraph` 执行：

1. 遍历 `wiki/` 目录所有 `.md` 文件
2. 从 frontmatter 提取 title、type、sources；从正文提取 `[[wikilinks]]`
3. Wikilink 解析：大小写不敏感，空格↔连字符兼容（`resolveTarget`）
4. 过滤 `type: query` 节点（研究结果是中间产物，不属于知识结构）
5. 边去重（无向图，A→B 和 B→A 合并为一条边）
6. 边权重 = `calculateRelevance(A, B, graph)`
7. 运行 Louvain 社区检测

### 5.2 Louvain 社区检测

> **Louvain Algorithm**：基于模块度（modularity）优化的层次聚合社区检测算法，时间复杂度近似 O(n log n)，适合大规模图。

- 自动发现知识聚类——哪些页面在链接拓扑上自然成组
- 每个社区计算**内聚度**（cohesion）= 实际内部边数 / 理论最大边数 `n(n-1)/2`
- 内聚度 < 0.15 且成员 ≥ 3：标记为稀疏社区，表示该知识领域内部关联不足

### 5.3 Graph Insights

自动分析图谱结构，输出两类洞察：

#### Surprising Connections（惊奇连接）

检测"意外"的边——连接了结构上不应当相邻的节点：

| 信号 | 加分 | 条件 |
|---|---|---|
| Cross-community | +3 | 边跨越社区边界 |
| Cross-type | +1~2 | 边连接不同类型的节点（distant type pair 如 source↔concept 加 2） |
| Peripheral-hub | +2 | 一端 degree ≤ 2，另一端 degree ≥ maxDegree × 0.5 |
| Weak but present | +1 | edge weight < 2 但 > 0 |

综合得分 ≥ 3 显示。支持 dismiss 操作。

#### Knowledge Gaps（知识空白）

三种检测：
1. **Isolated nodes**（degree ≤ 1）：几乎无入链的页面，需要补充交叉引用
2. **Sparse communities**（cohesion < 0.15, size ≥ 3）：某知识领域内部关联不足
3. **Bridge nodes**（连接 ≥ 3 个社区）：关键枢纽节点，若内容单薄会影响知识库连通性

每种 Gap 均可一键触发 Deep Research。

---

## 六、深度研究（Deep Research）

> 自动化网络搜索 + LLM 合成 + 二次摄入的闭环研究流程。

1. **Web Search**：调用 Tavily API，支持多个查询词（来自 Review 项的 SEARCH 字段或 LLM 优化后的查询），去重合并结果
2. **LLM Synthesis**：搜索结果 + 现有 wiki/index.md 送入 LLM，流式生成带 `[[wikilink]]` 交叉引用的研究页面
3. **Save**：写入 `wiki/queries/research-{slug}-{date}.md`，frontmatter `type: query`
4. **Auto-Ingest**：对研究页面调用 `autoIngest`，从中提取实体和概念进入知识网络——实现"研究反哺知识库"

任务队列：`maxConcurrent = 3`，通过 `useResearchStore` 管理，Research Panel 实时展示流式进度。

---

## 七、审核系统（Review System）

### 7.1 生成

LLM 在 Step 2 输出 REVIEW 块，结构化标记需要人工判断的问题：
- `contradiction`：知识冲突
- `duplicate`：疑似重复
- `missing-page`：缺失页面
- `suggestion`：研究建议
- `confirm`：待确认信息

每个审核项包含：预定义操作（Create Page / Skip）、受影响页面列表、预生成的搜索查询。

### 7.2 自动清理（Sweep）

摄入队列排空后触发 `sweepResolvedReviews`：

**Stage 1 — Rule-based matching**（O(1) 查找，零 token 消耗）：
- `missing-page`：检查候选名称是否已存在于 Wiki 索引（byId / byTitle 集合查找）
- `duplicate`：检查 affectedPages 是否仍有全部存在（若有页面已被删除则自动解决）

**Stage 2 — LLM judgment**（批量判断，有限 token 消耗）：
- 对 Stage 1 未解决的剩余项，按 `JUDGE_BATCH_SIZE = 40` 分批发给 LLM
- LLM 返回 `{"resolved": ["id1", "id2"]}` JSON
- 保守策略：仅高置信度才标记为已解决；矛盾/确认类默认保留
- 上限：最多 `MAX_JUDGE_BATCHES = 5` 批，避免无限制 token 消耗

---

## 八、Lint 机制

> **Lint**：静态分析工具，自动检测内容中的结构性问题。源自 C 语言 lint 工具（1978），现广泛指代各类静态检查。

### 8.1 Structural Lint（结构化检查，纯规则，无需 LLM）

- **Orphan**（孤立页）：无入链的页面——其他页面均未引用它
- **No-outlinks**（无出链页）：页面内无 `[[wikilink]]` 引用其他页面
- **Broken-link**（断链）：`[[target]]` 指向不存在的页面（case-insensitive 匹配）

### 8.2 Semantic Lint（语义检查，LLM 驱动）

LLM 通读所有 Wiki 页面的前 500 字符摘要，输出 `---LINT---` 格式块：
- `contradiction`：跨页面矛盾
- `stale`：过时信息
- `missing-page`：高引用但无专页的概念
- `suggestion`：改进建议

---

## 九、聊天系统

- **多会话**：独立 Conversation 对象，各自的消息列表和历史记录
- **引用追踪**：每条 AI 回复保存 `references: MessageReference[]`，记录引用的 Wiki 页面标题和路径
- **历史深度控制**：`maxHistoryMessages = 10`，仅发送最近 N 条消息作为上下文
- **Regenerate**：删除最后一轮 user+assistant 消息对，重新发送
- **Save to Wiki**：将对话中 LLM 的输出保存到 `wiki/queries/`，再通过 `executeIngestWrites` 触发摄入

---

## 十、Chrome 扩展与剪藏系统

### Chrome Extension（Manifest V3）

- **Readability.js**：Mozilla 的正文提取库（Firefox 阅读模式同款），剥离广告/导航/侧边栏
- **Turndown.js**：HTML → Markdown 转换器，支持表格
- 项目选择器：支持多项目，通过本地 API 获取项目列表
- 离线预览：即使应用未运行也可查看提取结果

### Clip Server（Rust tiny_http，端口 19827）

| 端点 | 方法 | 功能 |
|---|---|---|
| `/clip` | POST | 接收网页剪藏 |
| `/clips/pending` | GET | 获取待处理剪藏列表 |
| `/project` | POST | 设置当前项目路径 |
| `/projects` | POST | 更新项目列表（供扩展项目选择器） |

### Clip Watcher（前端轮询）

每 3 秒 GET `/clips/pending`，检测到新剪藏后自动调用 `enqueueIngest`，走完整的两步摄入流程。

---

## 十一、Wikilink 丰富化（Enrichment）

> 对已有 Wiki 页面补充内部链接的后处理流程。

核心问题：直接让 LLM 重写页面添加 `[[链接]]` 会导致模型"趁机"改写内容（改写句子、翻译、添加内容），这在中小模型上尤为严重。

解决方案——**LLM 只返回替换清单，程序做安全替换**：

1. LLM 输出 JSON：`{"links": [{"term": "注意力机制", "target": "attention-mechanism"}, ...]}`
2. 程序在原文中定位 `term` 的首次出现（排除 frontmatter 区域和已有 `[[...]]` 包裹）
3. 替换为 `[[target|term]]`（若 term 与 target 大小写相同则 `[[term]]`）

保证：
- 原文内容 byte-level 不变，仅插入 `[[` 和 `]]` 等符号
- frontmatter 区域完全不受影响
- 每个 target 最多链接一次，避免重复
- 即使 LLM 输出异常，最坏结果也只是"链接未添加"，不会破坏页面内容

---

## 十二、持久化与状态管理

| 数据 | 存储位置 | 格式 | 说明 |
|---|---|---|---|
| LLM 配置 | Tauri Store | JSON | API Key、模型、上下文窗口大小等 |
| 摄入队列 | `.llm-wiki/ingest-queue.json` | JSON | pending/processing/failed 任务列表 |
| 摄入缓存 | `.llm-wiki/ingest-cache.json` | JSON | SHA256 哈希 → 已生成文件路径列表 |
| 审核项 | `.llm-wiki/review.json` | JSON | 待处理/已解决的审核项 |
| 聊天历史 | `.llm-wiki/chats/{id}.json` | JSON | 每会话独立文件，上限 100 条/会话 |
| 对话列表 | `.llm-wiki/conversations.json` | JSON | 对话元数据索引 |
| 项目身份 | `.llm-wiki/project-identity.json` | JSON | UUID → 路径映射，支持项目迁移 |
| 向量索引 | LanceDB（项目目录下） | 二进制 | embedding 向量的 ANN 索引 |

**dataVersion**：单调递增计数器，Wiki 内容变更时 bump。用于图缓存失效（`cachedGraph.dataVersion === currentDataVersion` 时复用缓存）和 UI 响应式刷新。

---

## 十三、完整数据流

```
用户导入文档 / 网页剪藏 / 手动导入
        ↓
    Ingest Queue（串行化，磁盘持久化，崩溃恢复）
        ↓
    文档预处理（Rust: PDF/DOCX/PPTX/XLSX → text）
        ↓
    SHA256 增量缓存命中 → 跳过未变文件
        ↓
    Step 1: LLM Analysis（实体/概念/矛盾/关联提取）
        ↓
    Step 2: LLM Generation（FILE 块 + REVIEW 块输出）
        ↓
    正则解析写入文件（语言守卫 + log append + source summary fallback）
        ↓
    Review 项 → ReviewStore（异步人工审核队列）
        ↓
    缓存持久化 + 可选 vector embedding（LanceDB）
        ↓
    Queue drain → sweepResolvedReviews（规则 + LLM 自动清理）
        ↓
    dataVersion++ → graph/search/UI 刷新
```

查询管线：
```
用户提问 → Tokenized Search → (optional) Vector Search → Graph Expansion → Budget Control → Context Assembly → LLM Streaming Response → Cited Pages Persistence
```

---

## 十四、关键源码索引

| 功能 | 文件路径 | 说明 |
|---|---|---|
| 两步思维链摄入 | `src/lib/ingest.ts` | 核心入口：analysis prompt → generation prompt → 文件写入 → review 解析 |
| 摄入队列 | `src/lib/ingest-queue.ts` | 串行化队列：enqueue / processNext / pause / restore / cancel |
| LLM 客户端 | `src/lib/llm-client.ts` | 流式 fetch + 15min timeout + abort 支持 |
| LLM 提供商适配 | `src/lib/llm-providers.ts` | 6 种 provider 的 URL / headers / body / stream parser 适配 |
| 知识图谱构建 | `src/lib/wiki-graph.ts` | Wiki 文件 → 节点/边 + Louvain 社区检测 + 内聚度计算 |
| 相关性模型 | `src/lib/graph-relevance.ts` | 4-signal 评分：directLink / sourceOverlap / adamicAdar / typeAffinity |
| 图谱洞察 | `src/lib/graph-insights.ts` | surprising connections + knowledge gaps 检测 |
| 搜索引擎 | `src/lib/search.ts` | tokenized search + CJK bigram + 多层评分 |
| 向量嵌入 | `src/lib/embedding.ts` | embedding API → LanceDB upsert/search（通过 Tauri invoke） |
| 深度研究 | `src/lib/deep-research.ts` | Tavily search → LLM synthesis → save → auto-ingest |
| 网络搜索 | `src/lib/web-search.ts` | Tavily API 封装 |
| 审核清理 | `src/lib/sweep-reviews.ts` | rule-based + LLM-judged 自动清理 |
| Lint 检查 | `src/lib/lint.ts` | structural lint（orphan/broken-link）+ semantic lint（LLM） |
| Wikilink 丰富 | `src/lib/enrich-wikilinks.ts` | LLM 返回 JSON 替换清单 → 安全字符串替换 |
| 剪藏监听 | `src/lib/clip-watcher.ts` | 3s 轮询 /clips/pending → enqueueIngest |
| 项目模板 | `src/lib/templates.ts` | 5 种模板的 schema + purpose + extraDirs |
| 持久化 | `src/lib/persist.ts` | review items + chat history 的序列化/反序列化 |
| Wiki 状态 | `src/stores/wiki-store.ts` | Zustand store：project / llmConfig / embeddingConfig / dataVersion |
| 聊天状态 | `src/stores/chat-store.ts` | 多会话管理 / 流式消息 / 引用追踪 |
| 审核状态 | `src/stores/review-store.ts` | 审核 CRUD + 去重合并（type + normalizedTitle） |
| 聊天面板 | `src/components/chat/chat-panel.tsx` | 查询管线完整实现：search → expand → budget → assemble → stream |
| 前端文件操作 | `src/commands/fs.ts` | Tauri invoke 封装层 |
| Rust 项目命令 | `src-tauri/src/commands/project.rs` | create_project / open_project 实现 |
| Rust 文件系统 | `src-tauri/src/commands/fs.rs` | 文件 I/O + 目录遍历 + 文档预处理 + 级联删除 |
| Rust 向量存储 | `src-tauri/src/commands/vectorstore.rs` | LanceDB upsert / search / delete / count |
| Rust 剪藏服务 | `src-tauri/src/clip_server.rs` | tiny_http HTTP server（port 19827） |
