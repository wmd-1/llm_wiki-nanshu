# LLM Wiki 迁移参考手册

> 本文档整理了重新实现 LLM Wiki 时可复用的全部资料：可直接搬用的配置文件模板、语言无关的核心算法原理、LLM Prompt 设计、以及本项目绑定 Rust/Tauri 的部分与可替换方案的对照。面向有计算机基础的读者。
>
> **展开内容**（完整模板文本、Prompt 全文、初始文件内容）统一存放在 [`migration-ref/`](migration-ref/) 目录下，本报告只注明路径和设计要点。

---

## 一、可直接搬用的文件

以下文件是纯文本/纯数据，与实现语言无关，可直接复制到新项目中使用。

### 1.1 schema.md — Wiki 结构规则

**来源**：[`src-tauri/src/commands/project.rs`](src-tauri/src/commands/project.rs) 中 `create_project_impl` 函数生成的默认 schema.md

**用途**：LLM 在每次摄入和查询时读取此文件，了解页面类型、命名约定、frontmatter 格式。这是 Karpathy 原始模式中 "The Schema" 层的核心文件。

**完整内容**（General 模板）：见 [`migration-ref/templates/general-schema.md`](migration-ref/templates/general-schema.md)

> **注意**：项目创建时 Rust 代码（[`project.rs`](src-tauri/src/commands/project.rs)）硬编码了一份自己的 General schema，与 TypeScript 端 [`templates.ts`](src/lib/templates.ts) 中的 General 模板有细微文字差异（例如 entity 描述 Rust 写 "Named things (models, companies, people, datasets)"，模板写 "Named things (people, tools, organizations, datasets)"）。实际运行时 Rust 版本先写入磁盘，后续摄入时 LLM 读取的是 Rust 版本。此处给出的模板文本以 TypeScript 端为准，因为它是模板系统的源头。

### 1.2 purpose.md — 项目方向意图

**来源**：同上

**用途**：LLM 在每次摄入和查询时读取此文件，了解项目目标、关键问题、研究范围。这是本项目在 Karpathy 原始设计基础上新增的。

**完整内容**（General 模板）：见 [`migration-ref/templates/general-purpose.md`](migration-ref/templates/general-purpose.md)

### 1.3 场景模板（6 种）

**来源**：[`src/lib/templates.ts`](src/lib/templates.ts) — 完整的 schema + purpose 模板定义

每种模板包含：`schema`（结构规则文本）、`purpose`（方向意图文本）、`extraDirs`（额外目录列表）。

| 模板 | 额外目录 | schema 中的额外页面类型 | purpose 中的额外字段 |
|------|----------|------------------------|---------------------|
| Research | `wiki/methodology`, `wiki/findings`, `wiki/thesis` | thesis, methodology, finding（含 confidence/status/replicated 字段） | Research Question, Hypothesis, Background, Sub-questions, Methodology, Success Criteria, Current Status |
| Reading | `wiki/characters`, `wiki/themes`, `wiki/plot-threads`, `wiki/chapters` | character, theme, plot-thread, chapter（含 first_appearance/role/chapter/pages 字段） | Book Details, Why I'm Reading, Key Themes, Questions Going In, Reading Pace |
| Personal Growth | `wiki/goals`, `wiki/habits`, `wiki/reflections`, `wiki/journal` | goal, habit, reflection, journal（含 target_date/status/progress/frequency/streak 字段） | Focus Areas, Motivation, Current Goals, Active Habits, Review Cadence, Guiding Principles |
| Business | `wiki/meetings`, `wiki/decisions`, `wiki/projects`, `wiki/stakeholders` | meeting, decision, project, stakeholder（含 date/attendees/action_items/status/deciders/owner 字段） | Business Context, Objectives, Key Projects, Key Stakeholders, Open Decisions, Metrics |
| General | 无 | 仅基础 7 种 | Goal, Key Questions, Scope, Thesis |

**完整模板内容**（每个模板的 schema.md + purpose.md 展开文本）：

| 模板 | schema | purpose |
|------|--------|---------|
| Research | [`migration-ref/templates/research-schema.md`](migration-ref/templates/research-schema.md) | [`migration-ref/templates/research-purpose.md`](migration-ref/templates/research-purpose.md) |
| Reading | [`migration-ref/templates/reading-schema.md`](migration-ref/templates/reading-schema.md) | [`migration-ref/templates/reading-purpose.md`](migration-ref/templates/reading-purpose.md) |
| Personal Growth | [`migration-ref/templates/personal-growth-schema.md`](migration-ref/templates/personal-growth-schema.md) | [`migration-ref/templates/personal-growth-purpose.md`](migration-ref/templates/personal-growth-purpose.md) |
| Business | [`migration-ref/templates/business-schema.md`](migration-ref/templates/business-schema.md) | [`migration-ref/templates/business-purpose.md`](migration-ref/templates/business-purpose.md) |
| General | [`migration-ref/templates/general-schema.md`](migration-ref/templates/general-schema.md) | [`migration-ref/templates/general-purpose.md`](migration-ref/templates/general-purpose.md) |

**迁移建议**：将 [`templates.ts`](src/lib/templates.ts) 中的 schema/purpose 字符串直接复制出来，存储为你的语言中的常量或配置文件即可。不需要翻译代码——这些就是纯文本。

### 1.4 初始文件模板

项目创建时需要生成以下文件：

| 文件路径 | 完整内容 |
|----------|----------|
| `schema.md` | 由所选模板的 schema 字段生成（见 1.3） |
| `purpose.md` | 由所选模板的 purpose 字段生成（见 1.3） |
| `wiki/index.md` | [`migration-ref/initial-files/index.md`](migration-ref/initial-files/index.md)（初始为空壳，每次摄入由 LLM 更新） |
| `wiki/log.md` | `# Research Log` + 当日 `## {today}` + `- Project created` |
| `wiki/overview.md` | [`migration-ref/initial-files/overview.md`](migration-ref/initial-files/overview.md) |
| `.obsidian/app.json` | [`migration-ref/initial-files/obsidian-app.json`](migration-ref/initial-files/obsidian-app.json) |
| `.obsidian/appearance.json` | [`migration-ref/initial-files/obsidian-appearance.json`](migration-ref/initial-files/obsidian-appearance.json) |
| `.obsidian/core-plugins.json` | [`migration-ref/initial-files/obsidian-core-plugins.json`](migration-ref/initial-files/obsidian-core-plugins.json) |

---

## 二、核心算法原理（语言无关）

### 2.1 两步思维链摄入

**原理**：将 LLM 调用拆为两步——先分析再生成，分离理解与生产。

**流程**：

```
读取源文件 + schema.md + purpose.md + index.md + overview.md
        ↓
Step 1: LLM Analysis（temperature=0.1）
  输入：源文档 + purpose + index
  输出：Key Entities / Key Concepts / Main Arguments / Connections / Contradictions / Recommendations
        ↓
Step 2: LLM Generation（temperature=0.1）
  输入：Step 1 分析结果 + 源文档 + schema + purpose + index + overview
  输出：FILE 块 + REVIEW 块（严格分隔标记格式）
        ↓
Step 3: 正则解析 FILE 块 → 写文件
Step 4: 正则解析 REVIEW 块 → 加入审核队列
Step 5: SHA256 缓存 → 记录已处理文件
Step 6: 可选 embedding
```

**关键设计**：

- **temperature=0.1**：摄入需要稳定输出，不用高温度
- **源文档截断**：超过 50000 字符截断，避免超出上下文窗口
- **语言守卫**：对每个 FILE 块做语言检测，与用户设定不符的丢弃（log.md 和 sources/entities 页豁免）
- **log.md 追加模式**：检测到 `wiki/log.md` 路径时，先读原文件再追加，不覆盖
- **来源摘要兜底**：若 LLM 未生成 source summary 页，用 Step 1 分析结果自动创建

### 2.2 FILE 块解析

**正则**：`/---FILE:\s*([^\n]+?)\s*---\n([\s\S]*?)---END FILE---/g`

- 捕获组 1：文件相对路径（如 `wiki/entities/transformer.md`）
- 捕获组 2：文件完整内容（含 YAML frontmatter）
- 全局匹配，一个 LLM 回复可包含多个 FILE 块

### 2.3 REVIEW 块解析

**正则**：`/---REVIEW:\s*(\w[\w-]*)\s*\|\s*(.+?)\s*---\n([\s\S]*?)---END REVIEW---/g`

- 捕获组 1：类型（contradiction / duplicate / missing-page / suggestion，其余归为 confirm）
- 捕获组 2：标题
- 捕获组 3：正文，从中解析：
  - `OPTIONS: Create Page | Skip` → 操作选项
  - `PAGES: page1.md, page2.md` → 受影响页面
  - `SEARCH: query1 | query2 | query3` → 预生成搜索查询
  - 其余文本 → 描述

### 2.4 LINT 块解析

**正则**：`/---LINT:\s*([^\n|]+?)\s*\|\s*([^\n|]+?)\s*\|\s*([^\n-]+?)\s*---\n([\s\S]*?)---END LINT---/g`

- 捕获组 1：类型（contradiction / stale / missing-page / suggestion）
- 捕获组 2：严重度（warning / info）
- 捕获组 3：标题
- 捕获组 4：正文，含 `PAGES:` 行

---

## 三、LLM Prompt 设计

这是本项目最核心的知识产权——Prompt 的结构设计可以直接复用，只需替换具体实现中的流式调用接口。

**所有 Prompt 的完整文本**见 [`migration-ref/prompts/`](migration-ref/prompts/) 目录：

| Prompt | 文件 |
|--------|------|
| Step 1 — Analysis Prompt | [`1-analysis-prompt.md`](migration-ref/prompts/1-analysis-prompt.md) |
| Step 2 — Generation Prompt | [`2-generation-prompt.md`](migration-ref/prompts/2-generation-prompt.md) |
| Semantic Lint Prompt | [`3-semantic-lint-prompt.md`](migration-ref/prompts/3-semantic-lint-prompt.md) |
| Wikilink Enrichment Prompt | [`4-wikilink-enrichment-prompt.md`](migration-ref/prompts/4-wikilink-enrichment-prompt.md) |
| Deep Research Prompt | [`5-deep-research-prompt.md`](migration-ref/prompts/5-deep-research-prompt.md) |

以下为各 Prompt 的设计要点摘要：

**所有 Prompt 共用的语言指令**：每个 prompt 中的 `{languageRule}` 由 [`output-language.ts`](src/lib/output-language.ts) 的 `buildLanguageDirective()` 生成，格式为：

```
## ⚠️ MANDATORY OUTPUT LANGUAGE: {lang}

You MUST write your entire response (including wiki page titles, content, descriptions,
summaries, and any generated text) in **{lang}**.
The source material or wiki content may be in a different language, but this is IRRELEVANT
to your output language.
Ignore the language of any source content. Generate everything in {lang} only.
Proper nouns should use standard {lang} transliteration when appropriate.
DO NOT use any other language. This overrides all other instructions.
```

其中 `{lang}` 的取值逻辑：用户显式设置了 `outputLanguage` 则用之；否则（auto）对传入的文本样本做语言检测，取检测结果。

### 3.1 Step 1 — Analysis Prompt

**角色**：research analyst

**消息结构**：两条消息——
- **System prompt**：角色设定 + 输出要求 + `{languageRule}` + purpose.md + index.md
- **User message**：文件名 + 文件夹上下文（可选）+ 截断后的源文档内容

**嵌入位置**：purpose.md 和 index.md 嵌入在 **system prompt 末尾**（而非 user message），源文档内容嵌入在 **user message** 中。schema.md 和 overview.md 在 Analysis 阶段不嵌入。

**输出要求**（6 个结构化节）：Key Entities / Key Concepts / Main Arguments & Findings / Connections to Existing Wiki / Contradictions & Tensions / Recommendations

**关键细节**：
- 包含 `purpose` 和 `index` 作为上下文——让 LLM 知道 Wiki 的方向和已有内容
- 如果提供了 `folderContext`（文件夹路径），作为分类提示

### 3.2 Step 2 — Generation Prompt

**角色**：wiki maintainer

**消息结构**：两条消息——
- **System prompt**：角色设定 + `{languageRule}`（**出现两次**：开头一次，末尾 `---` 分隔后再重复一次） + 源文件名 + 生成要求 + Frontmatter 规则 + REVIEW 类型说明 + purpose.md + schema.md + index.md + overview.md + 输出格式约束 + 末尾重复 `{languageRule}`
- **User message**：Step 1 分析结果 + 截断后的源文档 + 格式提醒

**嵌入位置**：全部四个配置文件嵌入在 **system prompt** 中（purpose/schema/index/overview），Step 1 分析结果和源文档嵌入在 **user message** 中。

**输出要求**（6 个必须生成的文件 + 可选 REVIEW 块）：

1. `wiki/sources/{sourceBaseName}.md` — 来源摘要页（必须使用此路径）
2. `wiki/entities/` 下的实体页
3. `wiki/concepts/` 下的概念页
4. 更新 `wiki/index.md`（保留所有已有条目，添加新的）
5. `wiki/log.md` 日志条目（格式 `## [YYYY-MM-DD] ingest | Title`）
6. 更新 `wiki/overview.md`

**输出格式约束**（极其严格，放在 prompt 末尾）：

- 第一个字符必须是 `-`（`---FILE:` 的开头）
- 禁止任何前言、分析散文、markdown 表格
- 只输出 FILE 块和 REVIEW 块，块之间只用空行
- 每个 FILE 块的内容必须使用目标语言
- 如果不是以 `---FILE:` 开头，整个回复将被丢弃

**为什么严格**：中小模型（如 MiniMax-M2.7）极易在格式约束上漂移。prompt 末尾重复强调格式和语言指令——模型对最近的指令权重最高。

### 3.3 Semantic Lint Prompt

**角色**：wiki quality analyst

**输入**：所有 Wiki 页面的前 500 字符摘要

**输出格式**：`---LINT: type | severity | Short title---` 块

**类型**：contradiction / stale / missing-page / suggestion

### 3.4 Wikilink Enrichment Prompt

**角色**：wikilink identifier

**输入**：wiki/index.md + 单个 Wiki 页面内容

**输出格式**：JSON `{"links": [{"term": "...", "target": "..."}]}`

**关键设计决策**：不让 LLM 重写页面添加链接（中小模型会趁机改写内容），而是只返回替换清单，程序做安全替换。这是经过实际测试验证的反模式。

### 3.5 Deep Research Prompt

**角色**：research assistant

**消息结构**：两条消息——
- **System prompt**：角色设定 + `{languageRule}` + Cross-referencing 规则 + 写作规则 + wiki/index.md
- **User message**：研究主题 + 网络搜索结果 + 合成指令

**前置步骤**（从 Graph Insights 知识空白触发时）：当用户从知识空白一键触发 Deep Research 时，先执行 [`optimize-research-topic.ts`](src/lib/optimize-research-topic.ts)——用 LLM 根据知识空白描述 + wiki purpose/overview 生成优化后的研究主题和 3 条搜索查询词，再进入主流程。

**主流程**：网络搜索（多个查询去重合并）→ LLM 综合 → 保存为 `wiki/queries/research-{slug}-{date}.md` → 自动摄入（`autoIngest`）

**关键设计**：综合结果中必须用 `[[wikilink]]` 链接已有 wiki 页面，将新研究与已有知识图谱连接

---

## 四、核心算法（伪代码）

### 4.1 分词搜索

```
function tokenizeQuery(query):
  rawTokens = split(query, whitespace+punctuation)
  tokens = []
  for token in rawTokens:
    if containsCJK(token) and length > 2:
      // CJK bigram: "注意力机制" → ["注意力", "意力", "力机", "机制"]
      for i in 0..chars.length-2:
        tokens.add(chars[i] + chars[i+1])
      for ch in chars:
        if ch not in STOP_WORDS: tokens.add(ch)
      tokens.add(token)  // 保留原词用于精确短语匹配
    else:
      tokens.add(token)
  return deduplicate(tokens)

function scoreFile(file, query, tokens):
  score = 0
  if filename_stem == query_lower:          score += 200
  if title contains query_phrase:            score += 50
  score += min(countOccurrences(content, query), 10) * 20
  score += countMatchingTokens(title, tokens) * 5
  score += countMatchingTokens(content, tokens) * 1
  return score
```

### 4.2 Structural Lint

```
function runStructuralLint(wikiDir):
  pages = readAllMarkdownFiles(wikiDir)
  slugMap = buildCaseInsensitiveSlugMap(pages)  // [[Transformer]] → transformer.md
  
  inboundCounts = {}  // slug → 入链计数
  for page in pages:
    for link in extractWikilinks(page.content):
      target = resolveSlug(link, slugMap)
      inboundCounts[target] += 1
  
  results = []
  for page in pages:
    if inboundCounts[page.slug] == 0:
      results.add({type: "orphan", page: page.path})
    if page.outlinks.length == 0:
      results.add({type: "no-outlinks", page: page.path})
    for link in page.outlinks:
      if not slugMap.contains(link.lowercased()):
        results.add({type: "broken-link", page: page.path, detail: link})
  return results
```

### 4.3 Wikilink 安全替换

```
function enrichWithWikilinks(content, links):
  frontmatter, body = splitAtFrontmatter(content)  // 不碰 frontmatter
  linkedTargets = Set()
  
  for {term, target} in links:
    if linkedTargets.contains(target.lower): continue
    
    idx = findFirstUnlinkedOccurrence(body, term)  // 跳过已在 [[...]] 中的
    if idx == -1: continue
    
    replacement = (term.lower == target.lower)
      ? "[[${term}]]"                // 显示文本与目标相同
      : "[[${target}|${term}]]"      // 不同时用 [[target|display]]
    
    body = body[0..idx] + replacement + body[idx+term.length..]
    linkedTargets.add(target.lower)  // 每个 target 最多链接一次
  
  return frontmatter + body
```

### 4.4 四信号相关性模型

```
function calculateRelevance(nodeA, nodeB, graph):
  score = 0
  
  // 信号 1: 直接链接（×3.0）
  if nodeA.linksTo(nodeB) or nodeB.linksTo(nodeA):
    score += 3.0
  
  // 信号 2: 来源重叠（×4.0）
  overlap = |nodeA.sources ∩ nodeB.sources|  // frontmatter 的 sources[] 字段
  score += overlap * 4.0
  
  // 信号 3: Adamic-Adar 共同邻居（×1.5）
  commonNeighbors = neighbors(nodeA) ∩ neighbors(nodeB)
  for z in commonNeighbors:
    score += 1.0 / log(degree(z)) * 1.5
  
  // 信号 4: 类型亲和（×1.0）
  score += TYPE_AFFINITY[nodeA.type][nodeB.type] * 1.0
  
  return score

// 类型亲和系数查表（来源：src/lib/graph-relevance.ts TYPE_AFFINITY 常量）
TYPE_AFFINITY = {
  // entity 行
  entity↔concept: 1.2,  entity↔entity: 0.8,  entity↔source: 1.0,
  entity↔synthesis: 1.0, entity↔query: 0.8,
  // concept 行
  concept↔entity: 1.2,  concept↔concept: 0.8,  concept↔source: 1.0,
  concept↔synthesis: 1.2, concept↔query: 1.0,
  // source 行
  source↔entity: 1.0,  source↔concept: 1.0,  source↔source: 0.5,
  source↔query: 0.8,  source↔synthesis: 1.0,
  // query 行
  query↔concept: 1.0,  query↔entity: 0.8,  query↔source: 0.8,
  query↔synthesis: 1.0, query↔query: 0.5,
  // synthesis 行
  synthesis↔concept: 1.2, synthesis↔entity: 1.0, synthesis↔source: 1.0,
  synthesis↔query: 1.0,  synthesis↔synthesis: 0.8,
  // 未列出的类型对默认值: 0.5
}
```

### 4.5 Graph Insights

```
function findSurprisingConnections(nodes, edges, communities):
  results = []
  for edge in edges:
    score = 0
    if communityOf(edge.source) != communityOf(edge.target):  score += 3  // 跨社区
    if typeOf(edge.source) != typeOf(edge.target):
      score += (isDistantTypePair(source, target)) ? 2 : 1                  // 跨类型
    if (degree(source) ≤ 2 and degree(target) ≥ maxDegree*0.5)
    or (degree(target) ≤ 2 and degree(source) ≥ maxDegree*0.5):  score += 2  // 边缘-枢纽
    if edge.weight < 2 and edge.weight > 0:                    score += 1  // 弱连接
    if score >= 3: results.add(edge)
  return results

function detectKnowledgeGaps(nodes, edges, communities):
  gaps = []
  gaps.addAll(nodes.filter(n => n.degree ≤ 1 and n.type != "overview"))  // 孤立节点
  gaps.addAll(communities.filter(c => c.cohesion < 0.15 and c.size ≥ 3)) // 稀疏社区
  gaps.addAll(nodes.filter(n => n.connectedCommunities ≥ 3))              // 桥接枢纽
  return gaps
```

---

## 五、关键运行机制

以下子系统是将 LLM Wiki 从"单次演示"变为"可靠产品"的关键。每个机制的完整设计见 [`migration-ref/mechanisms/`](migration-ref/mechanisms/) 目录。

### 5.1 摄入队列（Ingest Queue）

**来源**：[`src/lib/ingest-queue.ts`](src/lib/ingest-queue.ts) | **完整设计**：[`migration-ref/mechanisms/ingest-queue.md`](migration-ref/mechanisms/ingest-queue.md)

串行化、持久化、可恢复的任务队列，确保 LLM 调用不并发、不丢失。

核心机制：

| 机制 | 说明 |
|------|------|
| 串行处理 | 同一时间只有一个 `processing` 任务，`processNext()` 递归调度 |
| 磁盘持久化 | `.llm-wiki/ingest-queue.json`，崩溃/重启后 `restoreQueue()` 恢复 |
| 自动重试 | 失败任务最多重试 3 次，超过标记为 `failed` |
| 取消清理 | abort LLM 调用 + 删除已写入的半成品文件 |
| 项目切换握手 | `pauseQueue()` 刷盘 → 清内存 → `restoreQueue()` 加载新项目 |
| 排空回调 | 队列排空后自动触发 `sweepResolvedReviews` |
| 上下文守卫 | 每次异步操作后检查 `currentProjectId`，防止写入错误项目 |

任务状态：`pending` → `processing` → `done`（移除）/ `failed`（重试或停留）

### 5.2 多阶段查询管线（Query Pipeline）

**来源**：[`src/components/chat/chat-panel.tsx`](src/components/chat/chat-panel.tsx) `handleSend` | **完整设计**：[`migration-ref/mechanisms/query-pipeline.md`](migration-ref/mechanisms/query-pipeline.md)

用户提问时执行 4 阶段管线：

```
用户提问
  ↓ Phase 1: Tokenized Search（分词搜索 + 评分）
  ↓ Phase 1.5: Vector Semantic Search（可选，LanceDB ANN）
  ↓ Phase 2: Graph Expansion（top-10 种子节点 + 1-hop 扩展，relevance ≥ 2.0）
  ↓ Phase 3: Budget Control（按上下文窗口大小分配：INDEX 5% + WIKI PAGE 60%，单页上限 min(30K, PAGE_BUDGET×0.3)；聊天历史不按字符占比分配，而是按条数截断最近 N 条）
  ↓ Phase 4: Context Assembly（P0 title match → P1 content match → P2 graph → P3 overview 兜底）
  ↓ LLM Streaming Response → Cited Pages Persistence
```

关键设计：
- Phase 1 的 CJK bigram 分词使中文搜索可用（见 4.1 节伪代码）
- Phase 1.5 是可选插件，不影响核心管线
- Phase 2 的图谱扩展将搜索从"关键词匹配"提升为"语义关联发现"
- Phase 3 的预算控制适配 4K ~ 1M 字符的不同模型

### 5.3 审核系统与 Sweep 自动清理

**来源**：[`src/lib/sweep-reviews.ts`](src/lib/sweep-reviews.ts) | **完整设计**：[`migration-ref/mechanisms/review-sweep.md`](migration-ref/mechanisms/review-sweep.md)

LLM 在摄入 Step 2 输出 REVIEW 块，解析后加入审核队列。5 种类型：contradiction / duplicate / missing-page / suggestion / confirm。

摄入队列排空后自动触发 Sweep，两阶段策略：

| 阶段 | 方法 | 成本 | 说明 |
|------|------|------|------|
| Stage 1 | 规则匹配 | 零 token | missing-page: 检查页面是否已存在；duplicate: 检查 affectedPages 中每个页面是否仍存在，**若任一已被删除则自动解决** |
| Stage 2 | LLM 语义判断 | 有限 token | 40 条/批，最多 5 批，保守策略（contradiction/confirm 默认保留） |

**迁移建议**：Stage 1 是零成本优化，强烈建议实现；Stage 2 锦上添花，初期可不实现。

### 5.4 知识图谱构建

**来源**：[`src/lib/wiki-graph.ts`](src/lib/wiki-graph.ts) | **完整设计**：[`migration-ref/mechanisms/knowledge-graph.md`](migration-ref/mechanisms/knowledge-graph.md)

`buildWikiGraph` 构建流程：

1. 遍历 `wiki/` 目录所有 `.md` 文件，提取 frontmatter（title/type/sources）+ 正文 `[[wikilinks]]`
2. Wikilink 解析：大小写不敏感 + 空格↔连字符兼容（`[[Transformer]]` 匹配 `transformer.md`）
3. 过滤 `type: query` 节点
4. 边去重（无向图）
5. 计算边权重（四信号相关性模型，见 4.4 节）
6. 运行 Louvain 社区检测（`graphology-communities-louvain`，`resolution = 1`）
7. 计算社区内聚度（cohesion = 实际内部边数 / n(n-1)/2）

图谱缓存：`dataVersion` 不变时复用已构建的图。

Graph Insights（见 4.5 节伪代码）：Surprising Connections（跨社区/跨类型/边缘-枢纽/弱连接）+ Knowledge Gaps（孤立节点/稀疏社区/桥接枢纽）。

### 5.5 Chrome 扩展与剪藏系统

**来源**：[`extension/`](extension/) 目录 | **完整设计**：[`migration-ref/mechanisms/clip-system.md`](migration-ref/mechanisms/clip-system.md)

```
Chrome Extension → Clip Server (Rust, :19827) → Clip Watcher (3秒轮询) → Ingest Queue
```

- Chrome Extension：Readability.js（正文提取）+ Turndown.js（HTML→Markdown）+ 项目选择器
- Clip Server：7 个 REST 端点——
  - 写入：POST /clip（接收剪藏）、POST /project（设置当前项目路径）、POST /projects（更新项目列表）
  - 读取：GET /clips/pending（获取待处理剪藏）、GET /status（服务状态）、GET /project（当前项目路径）、GET /projects（项目列表）
- Clip Watcher：检测新剪藏后保存到 `raw/sources/` → 调用 `enqueueIngest`

**迁移建议**：做 Web 应用时 Clip Server 可合并到后端 API；轮询可改为 WebSocket。

### 5.6 持久化与聊天系统

**来源**：[`src/stores/wiki-store.ts`](src/stores/wiki-store.ts) | **完整设计**：[`migration-ref/mechanisms/persistence-and-chat.md`](migration-ref/mechanisms/persistence-and-chat.md)

**dataVersion 机制**：单调递增计数器，Wiki 内容变更时 bump。用于图缓存失效和 UI 响应式刷新。比文件监听更可靠。

**聊天系统**：多会话、引用追踪（`references: MessageReference[]`）、历史深度控制（最近 10 条）、Regenerate、Save to Wiki（保存到 `wiki/queries/` → 更新 index.md 和 log.md → 调用 `autoIngest` 触发两步思维链摄入）。

**聊天持久化**：每个对话保存为 `.llm-wiki/chats/{convId}.json`（独立文件，上限 100 条/会话），对话列表索引保存在 `.llm-wiki/conversations.json`。review 和 chat 均有自动保存机制（review 1秒防抖、chat 2秒防抖，见 [`auto-save.ts`](src/lib/auto-save.ts)）。

---

## 六、Rust 绑定部分 vs. 语言无关替代方案

以下标注了哪些功能是 Rust 特有的（需要重新实现），哪些可以直接用其他语言/库替代。

### 6.1 文档预处理（Rust 特有）

| 功能 | 本项目 Rust 实现 | 替代方案 |
|------|-----------------|----------|
| PDF 文本提取 | pdf-extract crate | Python: PyPDF2 / pdfplumber; Node: pdf-parse; Go: unidoc/unipdf |
| DOCX 解析 | docx-rs | Python: python-docx; Node: mammoth; Go: unioffice |
| PPTX 解析 | ZIP + XML 手工解析 | Python: python-pptx; Node: pptx-parser |
| XLSX 解析 | calamine | Python: openpyxl; Node: xlsx; Go: excelize |
| 文件系统操作 | Tauri FS commands | 任何语言的 fs 模块 |

**迁移建议**：如果你的项目不需要桌面应用，这部分可以完全用 Python 库替代，且 Python 的文档处理生态更成熟。如果做 Web 应用，可以拆为独立的预处理微服务。

### 6.2 Clip Server（Rust 特有）

| 组件 | Rust 实现 | 替代方案 |
|------|----------|----------|
| HTTP 服务器 | tiny_http（端口 19827） | 任何语言的 HTTP 框架（Express / FastAPI / Go net/http） |
| Chrome 扩展通信 | POST /clip + GET /clips/pending | 同上，REST API 即可 |
| 跨域支持 | 手动 CORS 头 | 框架中间件 |

### 6.3 Tauri 桌面框架（Rust 特有）

| 功能 | Tauri 实现 | 替代方案 |
|------|-----------|----------|
| 窗口管理 | Tauri Window | Electron / WebView / 纯 Web |
| 文件系统桥接 | Tauri FS commands | Node fs / Python pathlib / 浏览器 File API |
| 原生菜单 | Tauri Menu | Electron Menu / Web UI |
| 系统托盘 | Tauri Tray | Electron Tray |

### 6.4 语言无关的核心逻辑

以下功能全部在 TypeScript 前端实现，与 Rust 无关，可以直接移植到任何语言：

| 功能 | 本项目实现 | 迁移方式 |
|------|-----------|----------|
| 两步摄入 Prompt 构建 | `ingest.ts` 的 `buildAnalysisPrompt` / `buildGenerationPrompt` | 复制 prompt 字符串，改写 LLM 调用接口 |
| FILE/REVIEW/LINT 块解析 | 3 个正则表达式 | 直接复制正则，任何语言都支持 |
| 分词搜索 + 评分 | `search.ts` 的 `tokenizeQuery` / `scoreFile` | 移植算法逻辑 |
| Structural Lint | `lint.ts` 的 `runStructuralLint` | 移植算法逻辑 |
| Semantic Lint | `lint.ts` 的 `runSemanticLint` | 复制 prompt + 块解析正则 |
| Wikilink 安全替换 | `enrich-wikilinks.ts` 的 `applyLinks` | 移植算法逻辑 |
| 四信号相关性 | `graph-relevance.ts` 的 `calculateRelevance` | 移植算法逻辑 |
| Louvain 社区检测 | graphology-communities-louvain（JS 库） | Python: python-louvain / networkx; Go: grazinggo/louvain |
| 图谱可视化 | sigma.js + graphology | D3.js / Cytoscape / 任何图可视化库 |
| 向量搜索 | LanceDB | ChromaDB / Qdrant / Milvus / pgvector |
| 增量缓存 | SHA256 哈希比对 | 任何语言的 crypto 库 |
| 搜索引擎 | Tavily API（[`web-search.ts`](src/lib/web-search.ts)） | SearXNG / SerpAPI / 任何搜索 API |
| LLM 调用 | OpenAI 兼容接口（[`llm-providers.ts`](src/lib/llm-providers.ts)） | 支持 openai / openrouter / anthropic / deepseek / gemini / minimax |
| Deep Research 主题优化 | [`optimize-research-topic.ts`](src/lib/optimize-research-topic.ts) | 移植算法逻辑（LLM 生成优化主题 + 3 条查询词） |
| Chat 式摄入 | [`ingest.ts`](src/lib/ingest.ts) 的 `startIngest` / `executeIngestWrites` | Save to Wiki 走 `autoIngest`（两步 CoT），Chat 面板流式回复走 `startIngest`（单步直接写入） |

---

## 七、数据格式约定

### 7.1 项目目录结构

```
project/
├── raw/sources/          ← 原始文档（不可变）
├── raw/assets/           ← 本地图片等资源
├── wiki/entities/        ← 实体页
├── wiki/concepts/        ← 概念页
├── wiki/sources/         ← 来源摘要页
├── wiki/queries/         ← 研究页
├── wiki/comparisons/     ← 对比页
├── wiki/synthesis/       ← 综合页
├── wiki/index.md         ← 内容目录
├── wiki/log.md           ← 操作日志
├── wiki/overview.md      ← 全局概览
├── schema.md             ← 结构规则
├── purpose.md            ← 方向意图
├── .obsidian/            ← Obsidian 兼容（可选）
└── .llm-wiki/            ← 应用内部状态
    ├── ingest-queue.json
    ├── ingest-cache.json
    ├── review.json
    ├── chats/
    │   ├── {convId}.json    ← 每会话独立文件
    │   └── ...
    ├── conversations.json   ← 对话元数据索引
    └── project.json         ← 项目身份（UUID + createdAt）
```

### 7.2 Wiki 页面格式

每个 Wiki 页面遵循统一格式：

```markdown
---
type: entity | concept | source | query | comparison | synthesis | overview
title: "Human-readable Title"
created: 2026-04-22
updated: 2026-04-22
tags: [tag1, tag2]
related: [other-page-slug]
sources: [original-source-filename.pdf]  ← 必须包含，实现来源追溯
---

# Page Title

Content with [[wikilinks]] to other pages.
```

### 7.3 内部状态文件格式

| 文件 | 格式 | 说明 |
|------|------|------|
| `ingest-queue.json` | `{tasks: [{id, projectId, sourcePath, folderContext, status, addedAt, retryCount, error}]}` | 摄入队列（只持久化 pending/failed） |
| `ingest-cache.json` | `{entries: {fileName: {hash: sha256, timestamp: ms, filesWritten: [paths]}}}` | 增量缓存 |
| `review.json` | `{items: [{id, type, title, description, resolved, ...}]}` | 审核队列 |
| `project.json` | `{id: "uuid", createdAt: ms}` | 项目身份（全局注册表 `app-state.json` 中存 `{id, path, name, lastOpened}`） |
| `conversations.json` | `[{id, title, createdAt, lastMessageAt}]` | 对话元数据索引 |
| `chats/{id}.json` | `{messages: [{role, content, references}]}` | 每会话独立消息文件 |

---

## 八、关键决策记录

以下是本项目在实现过程中做出的关键设计决策，供你重新实现时参考：

| 决策 | 原因 | 是否建议沿用 |
|------|------|-------------|
| 两步摄入而非一步 | 单步调用中 LLM 分析不充分，生成质量下降 | 是，这是核心创新 |
| FILE/REVIEW 分隔标记格式 | 让解析器可靠提取 LLM 输出中的结构化数据 | 是，比 JSON 输出更抗 LLM 格式漂移 |
| Wikilink 安全替换（JSON 清单而非重写） | 中小模型会趁机改写内容 | 是，实测验证的反模式 |
| 摄入队列串行化 | 并发 LLM 调用导致状态冲突 | 是，除非你的架构无状态 |
| purpose.md 与 schema.md 分离 | 结构规则与方向意图是不同维度 | 是，比原始设计更清晰 |
| 语言守卫 | LLM 偶尔输出错误语言的页面 | 是，特别是支持多语言时 |
| log.md 追加模式 + 语言豁免 | 日志不应被覆盖，且天然含跨语言名词 | 是 |
| 来源于摘要兜底 | LLM 偶尔遗漏 source summary 页 | 是，成本低收益高 |
| 操作选项白名单（Create Page / Skip） | 防止 LLM 幻觉自定义操作 | 是 |
| prompt 末尾重复格式/语言指令 | 模型对最近指令权重最高 | 是，中小模型尤其需要 |
| 向量搜索可选插件 | 不是所有用户都有 embedding API | 是，降低使用门槛 |
| dataVersion 单调递增 | 驱动缓存失效和 UI 刷新 | 是，比文件监听更可靠 |
| 两种摄入路径并存 | `autoIngest` 走两步 CoT（Save to Wiki），`startIngest` 走单步直接写入（Chat 流式回复） | 是，不同场景需要不同的质量控制级别 |

---

## 九、最小可行实现路线

如果要快速实现一个可用的 LLM Wiki，建议按以下顺序：

**Phase 1 — 核心闭环**（约 3-5 天）：
1. 项目创建：生成目录结构 + schema.md + purpose.md + index.md + log.md + overview.md
2. 摄入流程：两步 CoT + FILE 块解析 + 写文件
3. 查询流程：分词搜索 + 上下文组装 + LLM 流式回复
4. 基础 UI：聊天界面 + 文件预览

**Phase 2 — 可靠性**（约 2-3 天）：
5. 摄入队列：串行化 + 持久化 + 重试
6. 增量缓存：SHA256 哈希比对
7. REVIEW 块：解析 + 审核队列
8. Structural Lint：orphan + broken-link + no-outlinks

**Phase 3 — 增强**（约 3-5 天）：
9. 知识图谱：wikilink 解析 + 相关性计算 + 图可视化
10. Graph Insights：惊奇连接 + 知识空白
11. Wikilink 丰富化：安全替换
12. 答案回写：Save to Wiki + 自动摄入

**Phase 4 — 可选扩展**：
13. Semantic Lint（LLM 驱动）
14. Deep Research（网络搜索闭环）
15. 向量语义搜索
16. 场景模板系统
17. Chrome 扩展 / 剪藏系统
18. Louvain 社区检测

---

## 十、源文件速查表

| 你想了解的 | 看这个文件 |
|-----------|----------|
| 项目创建时生成哪些文件、内容是什么 | [`src-tauri/src/commands/project.rs`](src-tauri/src/commands/project.rs) |
| 5 种模板的 schema + purpose 完整文本 | [`src/lib/templates.ts`](src/lib/templates.ts) |
| 摄入流程的完整逻辑 + Prompt 设计 | [`src/lib/ingest.ts`](src/lib/ingest.ts) |
| FILE/REVIEW 块解析正则 | [`src/lib/ingest.ts`](src/lib/ingest.ts) L16, L341 |
| 分词搜索算法 + 评分函数 | [`src/lib/search.ts`](src/lib/search.ts) |
| 四信号相关性模型算法 | [`src/lib/graph-relevance.ts`](src/lib/graph-relevance.ts) |
| 知识图谱构建 + Louvain | [`src/lib/wiki-graph.ts`](src/lib/wiki-graph.ts) |
| Graph Insights 算法 | [`src/lib/graph-insights.ts`](src/lib/graph-insights.ts) |
| Structural + Semantic Lint | [`src/lib/lint.ts`](src/lib/lint.ts) |
| Wikilink 安全替换算法 | [`src/lib/enrich-wikilinks.ts`](src/lib/enrich-wikilinks.ts) |
| Deep Research 闭环流程 | [`src/lib/deep-research.ts`](src/lib/deep-research.ts) |
| 摄入队列状态机 | [`src/lib/ingest-queue.ts`](src/lib/ingest-queue.ts) |
| 审核自动清理（Sweep） | [`src/lib/sweep-reviews.ts`](src/lib/sweep-reviews.ts) |
| 向量嵌入 + LanceDB 操作 | [`src/lib/embedding.ts`](src/lib/embedding.ts) |
| 查询管线编排（Phase 1-4） | [`src/components/chat/chat-panel.tsx`](src/components/chat/chat-panel.tsx) `handleSend` |
| 答案回写逻辑 | [`src/components/chat/chat-message.tsx`](src/components/chat/chat-message.tsx) `handleSave` |
| 剪藏轮询 | [`src/lib/clip-watcher.ts`](src/lib/clip-watcher.ts) |
| Chrome 扩展 | [`extension/`](extension/) 目录 |
| Karpathy 原始理念 | [`llm-wiki.md`](llm-wiki.md) |
| 语言守卫指令生成 | [`src/lib/output-language.ts`](src/lib/output-language.ts) |
| Deep Research 主题优化 | [`src/lib/optimize-research-topic.ts`](src/lib/optimize-research-topic.ts) |
| LLM 调用 + 提供商配置 | [`src/lib/llm-providers.ts`](src/lib/llm-providers.ts) |
| 搜索引擎集成 | [`src/lib/web-search.ts`](src/lib/web-search.ts)（仅 Tavily） |
| 自动保存机制 | [`src/lib/auto-save.ts`](src/lib/auto-save.ts)（review 1s / chat 2s 防抖） |
| 项目身份 + 全局注册表 | [`src/lib/project-identity.ts`](src/lib/project-identity.ts) |

---

## 十一、migration-ref/ 目录索引

展开内容统一存放在项目根目录的 [`migration-ref/`](migration-ref/) 下，结构如下：

```
migration-ref/
├── templates/                          ← 6 种场景模板的完整文本
│   ├── general-schema.md               ← General 模板（基础 7 种类型，无额外目录）
│   ├── general-purpose.md
│   ├── research-schema.md
│   ├── research-purpose.md
│   ├── reading-schema.md
│   ├── reading-purpose.md
│   ├── personal-growth-schema.md
│   ├── personal-growth-purpose.md
│   ├── business-schema.md
│   └── business-purpose.md
├── prompts/                            ← 5 个 LLM Prompt 完整文本
│   ├── 1-analysis-prompt.md
│   ├── 2-generation-prompt.md
│   ├── 3-semantic-lint-prompt.md
│   ├── 4-wikilink-enrichment-prompt.md
│   └── 5-deep-research-prompt.md
├── mechanisms/                         ← 关键运行机制完整设计
│   ├── ingest-queue.md                 ← 摄入队列（串行化/持久化/重试/项目切换）
│   ├── query-pipeline.md               ← 多阶段查询管线（Phase 1-4）
│   ├── review-sweep.md                 ← 审核系统与 Sweep 自动清理
│   ├── knowledge-graph.md              ← 知识图谱构建 + Louvain + Insights
│   ├── clip-system.md                  ← Chrome 扩展与剪藏系统
│   └── persistence-and-chat.md         ← 持久化/dataVersion/聊天系统
├── initial-files/                      ← 项目创建时生成的初始文件
│   ├── index.md                        ← 初始为空壳，摄入时由 LLM 更新
│   ├── overview.md                     ← 初始近空，摄入时由 LLM 覆盖为 2-5 段概览
│   ├── obsidian-app.json
│   ├── obsidian-appearance.json
│   └── obsidian-core-plugins.json
```
