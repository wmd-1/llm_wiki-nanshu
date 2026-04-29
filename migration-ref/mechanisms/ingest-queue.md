# 摄入队列（Ingest Queue）

> 来源：[`src/lib/ingest-queue.ts`](../../src/lib/ingest-queue.ts)

## 设计目标

串行化、持久化、可恢复的任务队列，确保 LLM 调用不并发、不丢失。

## 任务结构

```typescript
interface IngestTask {
  id: string                    // "ingest-{timestamp}-{random}"
  projectId: string             // 稳定 UUID（通过 project-identity 注册表查找当前路径）
  sourcePath: string            // 相对于项目根目录，如 "raw/sources/paper.pdf"
  folderContext: string         // 文件夹路径作为 LLM 分类提示，如 "AI-Research > papers"
  status: "pending" | "processing" | "done" | "failed"
  addedAt: number               // Date.now()
  error: string | null
  retryCount: number
}
```

## 核心机制

### 串行处理

- 同一时间只有一个任务处于 `processing` 状态
- `processNext()` 递归调用：当前任务完成 → 检查下一个 pending → 继续处理
- 避免并发 LLM 调用导致状态冲突

### 磁盘持久化

- 队列状态保存到 `.llm-wiki/ingest-queue.json`
- 只持久化 pending/failed 任务（done 任务从队列中移除）
- 应用崩溃或重启后通过 `restoreQueue()` 恢复

### 自动重试

- 失败任务最多重试 **3 次**（`MAX_RETRIES = 3`）
- 超过重试上限标记为 `failed`，不再自动处理
- 用户可手动调用 `retryTask()` 重新入队

### 取消清理

- 取消 `processing` 任务时：abort LLM 调用（`AbortController`）+ 删除已写入的半成品文件
- 追踪 `lastWrittenFiles`，取消时逐一删除

### 项目切换握手

```
pauseQueue()
  → abort 正在进行的 LLM 调用 + Sweep 调用
  → 将 processing 任务回退为 pending
  → 刷盘当前项目的队列到 .llm-wiki/ingest-queue.json
  → 清空内存状态

restoreQueue(projectId, projectPath)
  → 从磁盘加载队列
  → 过滤跨项目污染
  → 将 processing 任务回退为 pending（应用中断时）
  → 启动 processNext()
```

### 排空回调

- 队列排空后触发 `sweepResolvedReviews`（审核项自动清理）
- 用 `processedSinceDrain` 标志避免空队列时反复触发

### 上下文守卫

- 每次关键操作前后检查 `currentProjectId !== projectId`
- 防止异步回调（LLM 返回、文件 I/O）在项目切换后写入错误的项目

## 状态机

```
                    enqueueIngest()
                         ↓
                    ┌──────────┐
         ┌─────────│  pending  │←──── retryTask()
         │         └─────┬─────┘
         │               ↓ processNext()
         │         ┌───────────┐
   3次失败  │         │ processing │──── cancelTask() → 删除 + 清理半成品
         │         └─────┬─────┘
         │          成功 ↓    │ 失败
         │         ┌──────┐   ↓
         │         │ done │  retryCount < 3 → pending
         │         │(移除)│  retryCount ≥ 3 → failed
         │         └──────┘
         ↓
    ┌──────────┐
    │  failed  │──→ retryTask() → pending
    └──────────┘
```
