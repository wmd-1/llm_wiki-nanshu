# 持久化与状态管理

> 来源：[`src/stores/wiki-store.ts`](../../src/stores/wiki-store.ts)、[`src/stores/review-store.ts`](../../src/stores/review-store.ts)、[`src/stores/chat-store.ts`](../../src/stores/chat-store.ts)

## 数据存储总览

| 数据 | 存储位置 | 格式 | 说明 |
|------|----------|------|------|
| LLM 配置 | Tauri Store | JSON | API Key、模型、上下文窗口大小等 |
| 摄入队列 | `.llm-wiki/ingest-queue.json` | JSON | pending/processing/failed 任务列表 |
| 摄入缓存 | `.llm-wiki/ingest-cache.json` | JSON | `{entries: {fileName: {hash, timestamp, filesWritten}}}` |
| 审核项 | `.llm-wiki/review.json` | JSON | 待处理/已解决的审核项 |
| 聊天历史 | `.llm-wiki/chats/{id}.json` | JSON | 每会话独立文件，上限 100 条/会话 |
| 对话列表 | `.llm-wiki/conversations.json` | JSON | 对话元数据索引 |
| 项目身份 | `.llm-wiki/project.json` | JSON | `{id: "uuid", createdAt: ms}`（全局注册表在 Tauri Store 的 `app-state.json` 中，存 `{id, path, name, lastOpened}`） |
| 向量索引 | LanceDB（项目目录下） | 二进制 | embedding 向量的 ANN 索引 |

## dataVersion 机制

- **单调递增计数器**：Wiki 内容变更时 bump（`useWikiStore.getState().bumpDataVersion()`）
- **用途**：
  1. **图缓存失效**：`cachedGraph.dataVersion === currentDataVersion` 时复用缓存，否则重新构建
  2. **UI 响应式刷新**：React 组件订阅 dataVersion，变更时自动重渲染
- **比文件监听更可靠**：文件监听有平台兼容性问题、延迟、遗漏；dataVersion 是应用级精确控制

## 聊天系统

- **多会话**：独立 Conversation 对象，各自的消息列表和历史记录
- **引用追踪**：每条 AI 回复保存 `references: MessageReference[]`，记录引用的 Wiki 页面标题和路径
- **历史深度控制**：`maxHistoryMessages = 10`，仅发送最近 N 条消息作为上下文
- **Regenerate**：删除最后一轮 user+assistant 消息对，重新发送
- **Save to Wiki**：将对话中 LLM 的输出保存到 `wiki/queries/`，更新 index.md 和 log.md，再通过 `autoIngest()` 触发两步思维链摄入（注意：不是 `executeIngestWrites`，后者是 Chat 流式回复的单步直接写入路径）
- **自动保存**：review 和 chat 均有防抖自动保存（review 1秒、chat 2秒），见 [`auto-save.ts`](../../src/lib/auto-save.ts)
