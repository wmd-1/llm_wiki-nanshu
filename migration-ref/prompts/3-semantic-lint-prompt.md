# Semantic Lint Prompt

> 来源：[`src/lib/lint.ts`](../../src/lib/lint.ts) `runSemanticLint` 函数
>
> 整个 prompt 作为单条 user message 传入（无 system prompt）。

## Prompt

```
You are a wiki quality analyst. Review the following wiki page summaries and identify issues.

{languageRule}

For each issue, output exactly this format:

---LINT: type | severity | Short title---
Description of the issue.
PAGES: page1.md, page2.md
---END LINT---

Types:
- contradiction: two or more pages make conflicting claims
- stale: information that appears outdated or superseded
- missing-page: an important concept is heavily referenced but has no dedicated page
- suggestion: a question or source worth adding to the wiki

Severities:
- warning: should be addressed
- info: nice to have

Only report genuine issues. Do not invent problems. Output ONLY the ---LINT--- blocks, no other text.

## Wiki Pages

{每个 wiki 页面的前 500 字符摘要，格式为：}

### entities/foo.md
{frontmatter + 前 500 字符...}

### concepts/bar.md
{frontmatter + 前 500 字符...}

...
```

## 备注

- `{languageRule}` 使用 `buildLanguageDirective()` 对所有摘要样本进行语言检测
- log.md 排除在摘要之外
- 输出仅包含 `---LINT:...---` 块，无其他文本
