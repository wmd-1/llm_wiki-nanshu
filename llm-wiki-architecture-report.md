# LLM Wiki 运行机制与工作原理报告

## 一、项目定位与核心理念

LLM Wiki 基于 Karpathy 的 LLM Wiki 模式，是一个**跨平台桌面应用**，核心理念是：**LLM 增量式构建并维护持久化 Wiki，而非传统 RAG 每次从零检索**。知识只编译一次，持续更新而非每次查询重推导。

三层架构：
```
Raw Sources (不可变) → Wiki (LLM 生成) → Schema (规则与配置)
```

---

## 二、技术栈与架构

| 层 | 技术 |
|---|---|
| 桌面容器 | **Tauri v2** (Rust 后端) |
| 前端 | React 19 + TypeScript + Vite |
| UI | shadcn/ui + Tailwind CSS v4 |
| 编辑器 | Milkdown (ProseMirror WYSIWYG) |
| 知识图谱 | sigma.js + graphology + ForceAtlas2 |
| 向量数据库 | LanceDB (Rust, 嵌入式, 可选) |
| 状态管理 | Zustand |
| LLM | 流式 fetch (OpenAI/Anthropic/Google/Ollama/MiniMax/Custom) |
| 网络搜索 | Tavily API |
| i18n | react-i18next |

前端通过 `@tauri-apps/api/core` 的 `invoke` 调用 Rust 后端命令（文件读写、目录遍历、PDF 提取、LanceDB 向量操作等）。Rust 后端还运行一个 HTTP 剪藏服务（`tiny_http`，端口 19827）供 Chrome 扩展推送网页内容。

---

## 三、Wiki 生成机制（核心）

### 3.1 项目创建

用户创建项目时选择模板（Research / Reading / Personal Growth / Business / General），Rust 后端 `create_project` 命令：

1. 创建目录结构：`raw/sources/`, `raw/assets/`, `wiki/entities/`, `wiki/concepts/`, `wiki/sources/`, `wiki/queries/`, `wiki/comparisons/`, `wiki/synthesis/`
2. 生成 `schema.md`（Wiki 结构规则）、`purpose.md`（项目意图）、`wiki/index.md`（目录页）、`wiki/log.md`（操作日志）、`wiki/overview.md`（全局概览）
3. 生成 `.obsidian/` 配置（Obsidian 兼容）

前端再覆盖模板的 `schema.md` 和 `purpose.md`，创建模板特有目录。

### 3.2 两步思维链摄入（Two-Step Chain-of-Thought Ingest）

这是 Wiki 生成的核心流程，由 `autoIngest` 函数（`src/lib/ingest.ts`）实现：

```
源文档 → Step 1: 分析 → Step 2: 生成 → Step 3: 写文件 → Step 4: 解析 Review → Step 5: 缓存 → Step 6: 嵌入
```

**Step 1 — 分析**：
- 读取源文档内容 + `purpose.md` + `schema.md` + `wiki/index.md` + `wiki/overview.md`
- 调用 LLM 流式生成结构化分析：关键实体、关键概念、主要论点、与现有 Wiki 的关联、矛盾与张力、建议
- `buildAnalysisPrompt` 构建 system prompt，引导 LLM 做深度分析

**Step 2 — 生成**：
- 将 Step 1 的分析结果作为上下文，再次调用 LLM
- `buildGenerationPrompt` 构建 system prompt，要求 LLM 以严格的 `---FILE: path--- ... ---END FILE---` 格式输出 wiki 文件
- 同时输出 `---REVIEW: type | title--- ... ---END REVIEW---` 格式的审核项
- LLM 被要求生成：源摘要页、实体页、概念页、更新的 index.md、log.md 条目、更新的 overview.md
- 每个文件必须包含 YAML frontmatter（type/title/created/updated/tags/related/sources）
- `sources` 字段**必须**包含原始源文件名，实现**来源可追溯**

**Step 3 — 写文件**：
- `writeFileBlocks` 用正则 `FILE_BLOCK_REGEX` 解析 LLM 输出
- 特殊处理 `log.md`：追加而非覆盖
- **语言守卫**：逐文件检测输出语言是否与用户设置的目标语言一致，不一致的文件块被丢弃
- **来源摘要兜底**：如果 LLM 没有生成 source summary 页，自动创建一个包含分析摘要的兜底页

**Step 4 — 解析 Review 项**：
- `parseReviewBlocks` 从 LLM 输出中提取 `REVIEW` 块
- 类型：contradiction / duplicate / missing-page / suggestion / confirm
- 每项包含：描述、预定义操作选项（Create Page / Skip）、受影响页面、预生成的搜索查询
- 添加到 ReviewStore 供用户异步审核

**Step 5 — 增量缓存**：
- SHA256 哈希源文件内容，如果未变则跳过摄入
- 缓存路径：`.llm-wiki/ingest-cache.json`

**Step 6 — 向量嵌入**（可选）：
- 如果启用了 embedding，对每个新生成的 wiki 页面调用 `embedPage`
- 通过 OpenAI 兼容的 `/v1/embeddings` 端点获取向量，存入 LanceDB

### 3.3 摄入队列（Ingest Queue）

`src/lib/ingest-queue.ts` 实现了一个**串行处理、持久化、可恢复**的摄入队列：

- **串行处理**：同一时间只处理一个任务，防止并发 LLM 调用
- **持久化**：队列状态保存到 `.llm-wiki/ingest-queue.json`，应用重启后恢复
- **自动重试**：失败任务最多重试 3 次
- **取消与清理**：取消任务时中止 LLM 调用 + 清理已写入的文件
- **项目切换**：`pauseQueue()` 刷盘当前项目队列 → `restoreQueue()` 加载新项目队列
- **队列排空后**：自动触发 `sweepResolvedReviews` 清理过期的审核项

### 3.4 文档预处理

Rust 后端 `preprocess_file` 命令支持多种格式的文档提取：

| 格式 | 方法 |
|---|---|
| PDF | pdf-extract (Rust) |
| DOCX | docx-rs |
| PPTX | ZIP + XML 提取 |
| XLSX/XLS/ODS | calamine |
| 图片 | 原生预览 |
| 网页剪藏 | Readability.js + Turndown.js → Markdown |

---

## 四、知识查询机制

### 4.1 多阶段检索管线

`ChatPanel`（`src/components/chat/chat-panel.tsx`）中的 `handleSend` 实现了完整的查询管线：

**Phase 1 — 分词搜索**：
- `searchWiki`（`src/lib/search.ts`）搜索 `wiki/` 和 `raw/sources/` 目录
- 英文：分词 + 停用词过滤；中文：CJK bigram 分词
- 评分：文件名精确匹配(+200) > 标题短语匹配(+50) > 内容短语出现次数(+20/次) > 标题 token(+5) > 内容 token(+1)

**Phase 1.5 — 向量语义搜索**（可选）：
- `searchByEmbedding` 通过 LanceDB 做近似最近邻检索
- 已有的搜索结果提升分数，新发现的结果添加到结果集

**Phase 2 — 图谱扩展**：
- 以搜索命中的 top 10 为种子节点
- `buildRetrievalGraph` 构建检索图
- `getRelatedNodes` 做 1 跳扩展，用四信号相关性模型计算关联度
- 过滤阈值：relevance >= 2.0

**Phase 3 — 预算控制**：
- 可配置上下文窗口（4K → 1M tokens）
- 分配比例：wiki 页面 60% / 聊天历史 20% / index 5% / 系统提示 15%
- 单页最大 30K 字符

**Phase 4 — 上下文组装**：
- 按优先级填入页面：P0 标题匹配 → P1 内容匹配 → P2 图谱扩展 → P3 概览兜底
- 系统提示包含：purpose.md、语言指令、index.md、带编号的 wiki 页面全文
- LLM 被要求用 [1], [2] 引用页面编号

### 4.2 四信号相关性模型

`src/lib/graph-relevance.ts` 中 `calculateRelevance` 计算两个节点间的相关性得分：

| 信号 | 权重 | 说明 |
|---|---|---|
| 直接链接 | ×3.0 | A→B 或 B→A 有 `[[wikilink]]` |
| 来源重叠 | ×4.0 | A 和 B 的 frontmatter `sources[]` 有交集 |
| Adamic-Adar | ×1.5 | 共同邻居的 1/log(degree) 之和 |
| 类型亲和 | ×1.0 | 同类型页面间的亲和系数 |

---

## 五、知识图谱机制

### 5.1 图谱构建

`buildWikiGraph`（`src/lib/wiki-graph.ts`）：

1. 遍历 `wiki/` 目录所有 `.md` 文件
2. 从 frontmatter 提取 title、type、sources
3. 从正文提取 `[[wikilinks]]`，解析目标（大小写不敏感、空格↔连字符）
4. 过滤掉 query 类型节点
5. 边去重（无向）
6. 用 `calculateRelevance` 计算边权重
7. 运行 Louvain 社区检测

### 5.2 Louvain 社区检测

- 使用 `graphology-communities-louvain` 算法
- 自动发现知识聚类
- 每个社区计算**内聚度** = 实际内部边数 / 可能边数
- 低内聚度(< 0.15) 社区标记为稀疏

### 5.3 Graph Insights

`src/lib/graph-insights.ts` 自动分析图谱结构：

**惊奇连接**（Surprising Connections）：
- 跨社区边 (+3)、跨类型边 (+1~2)、外围-枢纽耦合 (+2)、弱连接 (+1)
- 综合得分 ≥ 3 才显示

**知识空白**（Knowledge Gaps）：
- 孤立页面（degree ≤ 1）
- 稀疏社区（内聚度 < 0.15，≥ 3 个节点）
- 桥节点（连接 ≥ 3 个社区的关键枢纽）

每种 insight 都可以一键触发 Deep Research。

---

## 六、深度研究机制

`src/lib/deep-research.ts`：

1. **Web 搜索**：Tavily API，支持多个查询，去重合并
2. **LLM 合成**：将搜索结果 + wiki index 送入 LLM，流式生成带 `[[wikilink]]` 交叉引用的研究页面
3. **保存**：写入 `wiki/queries/research-{slug}-{date}.md`，type=query
4. **自动摄入**：对研究页面再次调用 `autoIngest`，提取实体和概念进入知识网络

任务队列支持 3 个并发任务，有 Research Panel 实时展示进度。

---

## 七、审核系统（Review System）

### 7.1 生成阶段

LLM 在 Step 2 生成时输出 REVIEW 块，包含：
- 类型（contradiction/duplicate/missing-page/suggestion/confirm）
- 预定义操作（仅允许 Create Page / Skip，防止 LLM 幻觉自定义操作）
- 预生成的搜索查询（用于 Deep Research）

### 7.2 自动清理

`src/lib/sweep-reviews.ts` 在摄入队列排空后触发：

- **Stage 1 — 规则匹配**：missing-page 类型项检查对应页面是否已存在；duplicate 类型项检查引用页面是否已被删除
- **Stage 2 — LLM 语义判断**：对剩余待审核项，批量发给 LLM 判断是否已解决，保守策略避免误删

---

## 八、Lint 机制

`src/lib/lint.ts` 提供两种 Lint：

**结构化 Lint**（无需 LLM）：
- 孤立页面（无入链）
- 无出链页面
- 断链（`[[wikilink]]` 指向不存在的页面）

**语义 Lint**（LLM 驱动）：
- 矛盾、过时信息、缺失页面、改进建议
- LLM 输出 `---LINT---` 格式块

---

## 九、聊天系统

`src/stores/chat-store.ts`：
- 多对话支持：创建/重命名/删除独立会话
- 每条回复保存引用的 wiki 页面列表（`references` 字段）
- 可配置历史深度（默认 10 条）
- 重新生成、保存到 Wiki（调用 `executeIngestWrites`）

---

## 十、Chrome 扩展与剪藏

**Chrome 扩展**（Manifest V3）：
- `popup.js` 使用 Readability.js 提取文章 + Turndown.js 转 Markdown
- 通过本地 HTTP API (port 19827) 推送到应用

**Clip Server**（Rust `tiny_http`）：
- 端点：`POST /clip`（接收剪藏）、`GET /clips/pending`（获取待处理）、`POST /project`（设置当前项目）、`POST /projects`（更新项目列表）

**Clip Watcher**（前端 3 秒轮询）：
- `src/lib/clip-watcher.ts` 每 3 秒检查待处理剪藏
- 新剪藏自动入队 `enqueueIngest`，走完整两步摄入流程

---

## 十一、Wikilink 丰富化

`src/lib/enrich-wikilinks.ts`：
- 轻量级后处理：LLM 只返回 `{term, target}` 替换列表（JSON），不重写页面
- 代码做精确字符串替换（首次出现），插入 `[[target|term]]`
- 不触碰 frontmatter、不触碰已有 wikilink
- 防止模型重写/翻译/扩展用户内容

---

## 十二、持久化与状态管理

| 数据 | 存储位置 | 格式 |
|---|---|---|
| LLM 配置 | Tauri Store | JSON |
| 摄入队列 | `.llm-wiki/ingest-queue.json` | JSON |
| 摄入缓存 | `.llm-wiki/ingest-cache.json` | JSON (SHA256) |
| 审核项 | `.llm-wiki/review.json` | JSON |
| 聊天历史 | `.llm-wiki/chats/{id}.json` | JSON (每会话独立) |
| 对话列表 | `.llm-wiki/conversations.json` | JSON |
| 项目身份 | `.llm-wiki/project-identity.json` | JSON (UUID → 路径映射) |
| 向量索引 | LanceDB (项目目录下) | 二进制 |

`dataVersion` 计数器在 wiki 内容变更时递增，用于图缓存失效和 UI 刷新。

---

## 十三、完整数据流总结

```
用户导入文档/PDF/网页剪藏
        ↓
    摄入队列 (持久化, 串行处理, 崩溃恢复)
        ↓
    文档预处理 (Rust: PDF/DOCX/PPTX/XLSX → 文本)
        ↓
    SHA256 增量缓存检查 → 跳过未变文件
        ↓
    Step 1: LLM 分析源文档 (实体/概念/矛盾/关联)
        ↓
    Step 2: LLM 生成 Wiki 文件 + 审核项 (FILE/REVIEW 块)
        ↓
    解析并写入文件 (语言守卫, log 追加, 来源摘要兜底)
        ↓
    解析 Review 项 → ReviewStore (供用户异步审核)
        ↓
    保存缓存 + 可选向量嵌入 (LanceDB)
        ↓
    队列排空 → 自动清理过期审核项 (规则 + LLM 判断)
        ↓
    dataVersion++ → 图谱/搜索/UI 自动刷新
```

查询时：
```
用户提问 → 分词搜索 → (可选)向量搜索 → 图谱扩展 → 预算控制 → 上下文组装 → LLM 流式回答 → 引用页面持久化
```

---

## 十四、关键源码文件索引

| 功能 | 文件路径 |
|---|---|
| 两步思维链摄入 | `src/lib/ingest.ts` |
| 摄入队列 | `src/lib/ingest-queue.ts` |
| LLM 客户端 | `src/lib/llm-client.ts` |
| LLM 提供商配置 | `src/lib/llm-providers.ts` |
| 知识图谱构建 | `src/lib/wiki-graph.ts` |
| 图谱相关性模型 | `src/lib/graph-relevance.ts` |
| 图谱洞察 | `src/lib/graph-insights.ts` |
| 搜索引擎 | `src/lib/search.ts` |
| 向量嵌入 | `src/lib/embedding.ts` |
| 深度研究 | `src/lib/deep-research.ts` |
| 网络搜索 | `src/lib/web-search.ts` |
| 审核清理 | `src/lib/sweep-reviews.ts` |
| Lint 检查 | `src/lib/lint.ts` |
| Wikilink 丰富 | `src/lib/enrich-wikilinks.ts` |
| 剪藏监听 | `src/lib/clip-watcher.ts` |
| 项目模板 | `src/lib/templates.ts` |
| 持久化 | `src/lib/persist.ts` |
| Wiki 状态 | `src/stores/wiki-store.ts` |
| 聊天状态 | `src/stores/chat-store.ts` |
| 审核状态 | `src/stores/review-store.ts` |
| 聊天面板(查询管线) | `src/components/chat/chat-panel.tsx` |
| 前端文件操作 | `src/commands/fs.ts` |
| Rust 项目命令 | `src-tauri/src/commands/project.rs` |
| Rust 文件系统命令 | `src-tauri/src/commands/fs.rs` |
| Rust 向量存储 | `src-tauri/src/commands/vectorstore.rs` |
| Rust 剪藏服务 | `src-tauri/src/clip_server.rs` |
