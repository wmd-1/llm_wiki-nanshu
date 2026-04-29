# 多阶段查询管线（Query Pipeline）

> 来源：[`src/components/chat/chat-panel.tsx`](../../src/components/chat/chat-panel.tsx) `handleSend` 函数
>
> 管线编排：Phase 1（分词搜索）→ Phase 1.5（向量搜索，可选）→ Phase 2（图谱扩展）→ Phase 3（预算控制）→ Phase 4（上下文组装）

## Phase 1 — Tokenized Search（分词搜索）

`searchWiki` 在 `wiki/` 和 `raw/sources/` 中搜索：

- **英文**：whitespace tokenization + stop word removal
- **中文**：CJK bigram tokenization（"注意力机制" → ["注意力", "意力", "力机", "机制"]），兼顾单字匹配
- **评分函数**（伪代码见主报告 4.1 节）：

| 信号 | 分值 | 说明 |
|------|------|------|
| Filename exact match | +200 | 文件名与查询完全匹配 |
| Phrase in title | +50 | 标题包含完整查询短语 |
| Phrase in content (per occ) | +20/次 | 内容中查询短语出现次数（上限 10 次） |
| Title token match | +5/token | 标题包含查询中的 token |
| Content token match | +1/token | 内容包含查询中的 token |

## Phase 1.5 — Vector Semantic Search（可选）

若启用 embedding 配置：

1. 查询文本通过 `/v1/embeddings` 端点获取向量
2. 在 LanceDB 中执行 ANN（Approximate Nearest Neighbor）检索
3. 结果合并到 Phase 1 结果：已有结果 boost 分数（`score += vr.score * 5`），新结果添加到结果集

## Phase 2 — Graph Expansion（图谱扩展）

以 Phase 1 的 top 10 搜索结果为种子节点，沿知识图谱做 1-hop 扩展：

- `buildRetrievalGraph` 构建检索图（带 `dataVersion` 缓存）
- `getRelatedNodes` 对每个种子节点取相关性 top-3 邻居
- 过滤阈值：relevance ≥ 2.0

## Phase 3 — Budget Control（预算控制）

根据用户配置的上下文窗口大小（4K ~ 1M 字符）按比例分配：

| 分配项 | 比例 | 说明 |
|--------|------|------|
| Wiki 页面内容 | 60% | 主要知识来源 |
| 聊天历史 | 20% | 对话上下文 |
| Index 页 | 5% | 目录信息 |
| 系统提示 | 15% | 指令与规则 |

单页上限：`MAX_PAGE_SIZE = min(PAGE_BUDGET * 0.3, 30K)`

## Phase 4 — Context Assembly（上下文组装）

页面按优先级填入：

1. **P0**：Title match 页面（搜索结果中 titleMatch=true）
2. **P1**：Content match 页面
3. **P2**：Graph expansion 页面
4. **P3**：Overview 兜底（若前三级无结果）

组装格式：带编号的完整页面内容（非摘要），系统提示含 purpose.md + index.md + 语言指令。LLM 被要求用 [1], [2] 编号引用来源。
