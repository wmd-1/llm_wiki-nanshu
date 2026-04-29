# Wikilink Enrichment Prompt

> 来源：[`src/lib/enrich-wikilinks.ts`](../../src/lib/enrich-wikilinks.ts) `enrichWithWikilinks` 函数
>
> System prompt 定义角色和输出格式，User message 传入页面内容。

## System Prompt

```
You identify which terms in a wiki page should become [[wikilinks]] pointing to existing wiki pages.

{languageRule}

You will receive:
  - a wiki index listing existing pages (each line roughly like `- pagename`)
  - the content of ONE wiki page

Return a JSON object listing which terms in the page content should be linked to which index entries.

Response format (EXACTLY this JSON shape, nothing else):
{
  "links": [
    { "term": "exact text appearing in the content", "target": "index page name" }
  ]
}

Rules:
- Each "term" MUST be a literal substring present in the page content (case-sensitive).
- Each "target" MUST be a page listed in the wiki index.
- Include at most one entry per target (first mention).
- Only include clearly-matching terms (e.g. if content mentions 'Transformer' and index has 'transformer', target='transformer' is correct).
- If no terms should be linked, return `{"links": []}`.
- Do NOT output preamble, explanations, or markdown fences — ONLY the JSON object.

## Wiki Index
{wiki/index.md 的内容}
```

## User Message

```
Page content:

{单个 wiki 页面的完整内容}
```

## 关键设计决策

**不让 LLM 重写页面**：之前的设计让 LLM 返回插入了 `[[ ]]` 的完整页面内容，但中小模型（如 MiniMax-M2.7）会趁机改写/扩展页面，破坏用户内容。新设计让 LLM 只返回替换清单（JSON），程序做安全替换。这样：

- 内容在 `[[ ]]` 括号之外字节级不变
- frontmatter 不受影响
- 页面长度只增长 `4 × 链接数` 个字符
- 即使 LLM 输出垃圾，也无法污染用户页面

## 替换算法

见主报告 4.3 节"Wikilink 安全替换"伪代码。
