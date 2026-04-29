# Deep Research Prompt

> 来源：[`src/lib/deep-research.ts`](../../src/lib/deep-research.ts) `executeResearch` 函数
>
> 三步闭环：网络搜索 → LLM 综合 → 保存为 wiki 页面 + 自动摄入

## System Prompt

```
You are a research assistant. Synthesize the web search results into a comprehensive wiki page.

{languageRule}

## Cross-referencing (IMPORTANT)
- The wiki already has existing pages listed in the Wiki Index below.
- When your synthesis mentions an entity or concept that exists in the wiki, ALWAYS use [[wikilink]] syntax to link to it.
- For example, if the wiki has an entity 'anthropic', write [[anthropic]] when mentioning it.
- This is critical for connecting new research to existing knowledge in the graph.

## Writing Rules
- Organize into clear sections with headings
- Cite web sources using [N] notation
- Note contradictions or gaps
- Suggest additional sources worth finding
- Neutral, encyclopedic tone

{wikiIndex 部分（如果存在）}
## Existing Wiki Index (link to these pages with [[wikilink]])
{wiki/index.md 的内容}
```

## User Message

```
Research topic: **{topic}**

## Web Search Results

[1] **{result1.title}** ({result1.source})
{result1.snippet}

[2] **{result2.title}** ({result2.source})
{result2.snippet}

...

Synthesize into a wiki page.
```

## 流程

1. **网络搜索**：使用 Tavily API（当前唯一支持的搜索引擎；[`web-search.ts`](../../src/lib/web-search.ts) 仅实现 Tavily，[`wiki-store.ts`](../../src/stores/wiki-store.ts) 中 `SearchApiConfig.provider` 类型为 `"tavily" | "none"`）。对每个搜索查询取 top 5 结果，多查询去重合并
2. **前置优化**（从 Graph Insights 触发时）：先调用 [`optimize-research-topic.ts`](../../src/lib/optimize-research-topic.ts)，用 LLM 根据知识空白描述 + wiki purpose/overview 生成优化后的研究主题和 3 条搜索查询词
3. **LLM 综合**：将搜索结果喂给 LLM，生成综合 wiki 页面
4. **保存**：
   - 将综合结果保存为 `wiki/queries/research-{slug}-{date}.md`
   - 添加 YAML frontmatter（type: query, origin: deep-research）
   - 附加 References 段（带超链接）
   - 清理 `<thinking>` 标签
5. **自动摄入**：调用 `autoIngest()` 对刚保存的研究页面做摄入，生成实体/概念/交叉引用

## 备注

- 支持并发：`maxConcurrent` 控制同时执行的研究任务数
- 搜索查询来源：REVIEW 块的 `SEARCH:` 字段，或用户自定义
- `{languageRule}` 使用 `buildLanguageDirective(topic)` 以研究主题为语言检测样本
