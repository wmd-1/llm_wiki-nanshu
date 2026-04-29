# 审核系统与 Sweep 自动清理

> 来源：[`src/lib/sweep-reviews.ts`](../../src/lib/sweep-reviews.ts)、[`src/stores/review-store.ts`](../../src/stores/review-store.ts)

## 审核项结构

LLM 在 Step 2 输出 REVIEW 块，解析后加入审核队列：

```typescript
interface ReviewItem {
  id: string
  type: "contradiction" | "duplicate" | "missing-page" | "suggestion" | "confirm"
  title: string
  description: string
  sourcePath: string
  affectedPages?: string[]       // 受影响的 wiki 页面路径
  searchQueries?: string[]       // 预生成的网络搜索查询
  options: { label: string; action: string }[]
  resolved: boolean
  resolvedBy?: string            // "user" | "auto-resolved" | "llm-judged"
  createdAt: number
}
```

## Sweep 自动清理

摄入队列排空后自动触发 `sweepResolvedReviews`。两阶段策略：

### Stage 1 — Rule-based Matching（零 token 消耗）

对每个未解决的审核项做 O(1) 查找：

- **missing-page**：提取候选名称（标题 + affectedPages），在 Wiki 索引（byId / byTitle 集合）中查找。若对应页面已存在，标记为 `auto-resolved`
- **duplicate**：检查 affectedPages 中的每个页面是否仍存在。**若任一页面已被删除**，则自动解决（逻辑：被指为重复的页面已不存在，审核项失去意义）

### Stage 2 — LLM Semantic Judgment（有限 token 消耗）

对 Stage 1 未解决的剩余项，按 `JUDGE_BATCH_SIZE = 40` 分批发给 LLM：

- Prompt 包含当前 wiki 页面列表 + 待审核项摘要
- LLM 返回 `{"resolved": ["id1", "id2"]}` JSON
- 保守策略：仅高置信度才标记为已解决；contradiction / confirm 类默认保留
- 上限：最多 `MAX_JUDGE_BATCHES = 5` 批，避免无限制 token 消耗
- 提前终止：若某批无任何解决项，后续批次也大概率相同，直接停止

### 安全守卫

- 项目切换 / abort 时立即停止 Sweep
- 每次 await 后重新检查 `matchesCurrentProject()`
- LLM 调用使用 `AbortController`，项目切换时取消正在进行的判断

## 迁移要点

- Stage 1 是零成本优化，**强烈建议实现**
- Stage 2 的 LLM 判断是锦上添花，初期可以不实现
- Sweep 的触发时机：摄入队列排空后，而非定时器
