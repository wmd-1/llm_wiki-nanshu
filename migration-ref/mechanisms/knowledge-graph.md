# 知识图谱构建

> 来源：[`src/lib/wiki-graph.ts`](../../src/lib/wiki-graph.ts)、[`src/lib/graph-relevance.ts`](../../src/lib/graph-relevance.ts)、[`src/lib/graph-insights.ts`](../../src/lib/graph-insights.ts)

## 构建流程

`buildWikiGraph` 执行以下步骤：

### 1. 遍历 wiki/ 目录

读取所有 `.md` 文件，提取：
- **frontmatter**：title、type、sources
- **正文**：`[[wikilinks]]`

### 2. Wikilink 解析

正则：`/\[\[([^\]|]+?)(?:\|[^\]]+?)?\]\]/g`

`resolveTarget` 做大小写不敏感匹配 + 空格↔连字符兼容：
- `[[Transformer]]` 匹配 `transformer.md`
- `[[attention mechanism]]` 匹配 `attention-mechanism.md`

### 3. 过滤

过滤 `type: query` 节点（研究结果是中间产物，不属于知识结构）

### 4. 边去重

无向图：A→B 和 B→A 合并为一条边

### 5. 计算边权重

调用 `calculateRelevance(A, B, graph)`（四信号相关性模型，见主报告 4.4 节）

### 6. Louvain 社区检测

使用 graphology-communities-louvain 库，`resolution = 1`

输出每个社区的：
- **内聚度**（cohesion）= 实际内部边数 / 理论最大边数 `n(n-1)/2`
- **topNodes**：按 linkCount 排序的前 5 个节点
- 社区 ID 重新编号为 0, 1, 2, ...

## 图谱缓存

- 使用 `dataVersion` 缓存：Wiki 内容不变时复用已构建的图
- `buildRetrievalGraph(projectPath, dataVersion)` 检查版本号决定是否重新构建

## Graph Insights

详见主报告 4.5 节伪代码。两类洞察：

### Surprising Connections（惊奇连接）

| 信号 | 加分 | 条件 |
|------|------|------|
| Cross-community | +3 | 边跨越社区边界 |
| Cross-type | +1~2 | 边连接不同类型的节点（distant type pair 如 source↔concept 加 2） |
| Peripheral-hub | +2 | 一端 degree ≤ 2，另一端 degree ≥ maxDegree × 0.5 |
| Weak but present | +1 | edge weight < 2 但 > 0 |

综合得分 ≥ 3 显示。支持 dismiss 操作。

### Knowledge Gaps（知识空白）

1. **Isolated nodes**（degree ≤ 1，排除 overview）：几乎无入链的页面
2. **Sparse communities**（cohesion < 0.15, size ≥ 3）：某知识领域内部关联不足
3. **Bridge nodes**（连接 ≥ 3 个社区）：关键枢纽节点

每种 Gap 均可一键触发 Deep Research。

## 迁移替代方案

| 本项目实现 | 替代方案 |
|-----------|----------|
| graphology（JS 图库） | Python: networkx; Go: gonum/graph |
| graphology-communities-louvain | Python: python-louvain / networkx.community; Go: grazinggo/louvain |
| sigma.js（可视化） | D3.js / Cytoscape / vis.js |
