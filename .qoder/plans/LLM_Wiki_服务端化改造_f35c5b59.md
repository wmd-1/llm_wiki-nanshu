
# LLM Wiki 服务端化改造计划

## 可行性结论：完全可行

当前架构的核心业务逻辑（摄入、搜索、图谱、LLM 交互、深度研究）全部在 TypeScript 层（`src/lib/`），且与 UI 框架（React/Tauri）的耦合点明确可控。主要耦合点有：
- 文件 I/O 通过 `src/commands/fs.ts` 统一抽象（实际调用 Tauri invoke）
- 向量存储通过 `src/lib/embedding.ts` 调用 Rust LanceDB 命令
- 状态管理通过 Zustand stores（前端专用）

这些都可以用 Python 原生方案替换。

---

## 总体架构

```
FastAPI Server (Python)
├── API 层 (FastAPI routes)     ← 对外 REST/SSE 接口
├── 服务层 (business logic)     ← 移植自 src/lib/*.ts
│   ├── ingest/                 ← 摄入管线（两步思维链）
│   ├── search/                 ← 分词搜索 + 向量搜索
│   ├── graph/                  ← 知识图谱 + 社区检测
│   ├── chat/                   ← 多阶段查询管线
│   ├── research/               ← 深度研究
│   └── llm/                    ← LLM 客户端（多供应商）
├── 存储层
│   ├── 文件系统 (wiki 目录结构) ← 保持 Obsidian 兼容
│   ├── 向量库 (LanceDB Python) ← 替代 Rust LanceDB
│   └── 元数据 (SQLite)         ← 项目/用户/任务持久化
└── 文档预处理 (Python 库)      ← 替代 Rust 命令
```

---

## Task 1: 项目脚手架搭建

**创建 `server/` 目录**，包含：
- `server/app/` — FastAPI 应用主目录
- `server/app/api/` — API 路由
- `server/app/services/` — 业务逻辑
- `server/app/models/` — Pydantic 数据模型
- `server/app/core/` — 配置、依赖注入
- `server/requirements.txt` — Python 依赖
- `server/Dockerfile` — 容器化部署

**Python 依赖**：
```
fastapi, uvicorn, httpx, pydantic, python-multipart
lancedb, graphology-like (networkx + python-louvain)
pypdf2, python-docx, openpyxl, beautifulsoup4, markdownify
openai (SDK, 兼容多供应商)
sse-starlette (流式响应)
aiosqlite / sqlalchemy (元数据)
```

---

## Task 2: 数据模型定义（Pydantic）

移植 `src/types/wiki.ts` + `src/stores/wiki-store.ts` 中的类型：

| 原始类型 | Python 对应 | 来源文件 |
|----------|------------|---------|
| `LlmConfig` | `LlmConfig` | `wiki-store.ts` L4-11 |
| `SearchApiConfig` | `SearchApiConfig` | `wiki-store.ts` L13-16 |
| `EmbeddingConfig` | `EmbeddingConfig` | `wiki-store.ts` L18-23 |
| `FileNode` | `FileNode` | `types/wiki.ts` |
| `WikiProject` | `WikiProject` | `types/wiki.ts` |
| `IngestTask` | `IngestTask` | `ingest-queue.ts` L9-21 |
| `SearchResult` | `SearchResult` | `search.ts` L5-11 |
| `GraphNode/Edge/Community` | 同名 | `wiki-graph.ts` L8-28 |
| `RetrievalNode/Graph` | 同名 | `graph-relevance.ts` L9-22 |
| `ReviewItem` | `ReviewItem` | `stores/review-store.ts` |
| `Conversation/DisplayMessage` | 同名 | `stores/chat-store.ts` |

---

## Task 3: LLM 客户端移植

**源文件**: `src/lib/llm-client.ts` + `src/lib/llm-providers.ts`

移植要点：
- 使用 `httpx` + SSE 解析替代 `fetch` + 手动 SSE 解码
- 支持 6 种供应商（openai/anthropic/google/ollama/minimax/custom）
- 保持流式输出能力（`stream=True`）
- 15 分钟超时 + AbortSignal 等价物（`asyncio.CancelledError`）
- Anthropic/Google 特殊请求体格式保持一致

Python 实现可直接使用 `openai` SDK（兼容 OpenAI/ollama/custom/minimax），Anthropic SDK，Google SDK，减少自行解析 SSE 的工作量。

---

## Task 4: 文件操作层实现

**源文件**: `src/commands/fs.ts`（12 个 Tauri invoke）

用 Python `pathlib` + `aiofiles` 替代所有 Tauri invoke：
- `read_file` / `write_file` → `aiofiles`
- `list_directory` → `pathlib.rglob`
- `create_directory` → `pathlib.mkdir(parents=True)`
- `file_exists` → `pathlib.exists()`
- `delete_file` → `pathlib.unlink()`
- `copy_file` → `shutil.copy2`

---

## Task 5: 文档预处理模块

**源文件**: `src-tauri/src/commands/` (Rust)

用 Python 库替代 Rust 命令：
| 格式 | Rust 原实现 | Python 替代 |
|------|-----------|------------|
| PDF | pdf-extract | `pypdf2` / `pdfplumber` |
| DOCX | docx-rs | `python-docx` |
| PPTX | ZIP+XML | `python-pptx` |
| XLSX | calamine | `openpyxl` |
| HTML | Readability.js + Turndown.js | `beautifulsoup4` + `markdownify` |
| 纯文本 | 直接读取 | 直接读取 |

---

## Task 6: 摄入管线移植（核心，最复杂）

**源文件**:
- `src/lib/ingest.ts` (307 行) — 两步思维链主逻辑
- `src/lib/ingest-queue.ts` (533 行) — 串行队列
- `src/lib/ingest-cache.ts` — SHA256 增量缓存
- `src/lib/templates.ts` — 5 种场景模板
- `migration-ref/prompts/` — 5 个 prompt 模板

移植要点：
1. **两步思维链**: 分析 → 生成，保持 FILE/REVIEW 块解析逻辑
2. **摄入队列**: 用 `asyncio.Queue` + 数据库持久化替代内存+JSON
3. **增量缓存**: SHA256 哈希比对逻辑不变
4. **Prompt 模板**: 从 `migration-ref/prompts/` 迁移为 Python f-string / Jinja2
5. **语言守卫**: `output-language.ts` 移植

---

## Task 7: 搜索系统移植

**源文件**: `src/lib/search.ts` (339 行)

移植要点：
1. **分词引擎**: 英文 whitespace + stop word → Python `re`；中文 CJK bigram → 保持相同逻辑
2. **评分函数**: 文件名精确匹配(200) / 标题短语(50) / 内容短语(20) / token 权重(5/1)
3. **向量搜索合并**: LanceDB Python SDK 的 ANN 检索结果与词法搜索融合

---

## Task 8: 知识图谱移植

**源文件**:
- `src/lib/wiki-graph.ts` (305 行) — 图构建 + Louvain
- `src/lib/graph-relevance.ts` (313 行) — 四信号相关性
- `src/lib/graph-insights.ts` — 惊奇连接/知识空白

移植要点：
1. **图构建**: wikilink 解析 + 节点/边提取
2. **Louvain 社区检测**: `python-louvain` / `community` 库（networkx 生态）
3. **四信号相关性**: 直接链接(3.0) / 来源重叠(4.0) / Adamic-Adar(1.5) / 类型亲和(1.0)
4. **Graph Insights**: Surprising Connections + Knowledge Gaps 检测

---

## Task 9: 查询管线移植（Chat）

**源文件**: `src/components/chat/chat-panel.tsx` L159-374 (`handleSend`)

这是 4 阶段检索管线的编排逻辑，与 UI 解耦后移植：
1. **Phase 1**: Tokenized Search → top 10 结果
2. **Phase 2**: Graph 1-level expansion → 相关节点
3. **Phase 3**: Page budget control → 优先级排序（P0 标题匹配 > P1 内容匹配 > P2 图扩展 > P3 overview 兜底）
4. **Phase 4**: Context assembly → LLM 流式回答

---

## Task 10: 深度研究移植

**源文件**: `src/lib/deep-research.ts` (244 行)

移植要点：
- 多查询并发搜索 → 结果去重合并
- LLM 综合生成 wiki 页面
- 自动保存 + auto-ingest
- 任务队列（`research-store` 逻辑用 Python asyncio 替代）

---

## Task 11: 向量嵌入移植

**源文件**: `src/lib/embedding.ts` (207 行)

用 Python LanceDB SDK 直接操作，无需 Tauri invoke：
- `embedPage` → fetch embedding + upsert to LanceDB
- `embedAllPages` → 批量嵌入
- `searchByEmbedding` → ANN 检索
- 嵌入 API 调用可用 `openai` SDK 或 `httpx` 直接请求

---

## Task 12: 持久化与状态管理

**源文件**:
- `src/lib/persist.ts` — review/chat 持久化
- `src/stores/*.ts` — 5 个 Zustand store

服务端方案：
- 用 SQLite（`aiosqlite`）替代 JSON 文件存储元数据
- 保持 wiki 目录结构（`.llm-wiki/` 下文件不变）以保证 Obsidian 兼容
- Review/Chat/Queue 状态存入数据库，支持多项目并发
- 项目配置（LLM/Embedding/Search）存入 `projects` 表

---

## Task 13: FastAPI 路由设计

```
POST   /api/projects                     — 创建项目
GET    /api/projects                     — 列出项目
GET    /api/projects/{id}                — 获取项目详情
DELETE /api/projects/{id}                — 删除项目

POST   /api/projects/{id}/ingest         — 上传文档并摄入
GET    /api/projects/{id}/ingest/tasks   — 查看摄入队列
POST   /api/projects/{id}/ingest/{task}/retry  — 重试失败任务
DELETE /api/projects/{id}/ingest/{task}  — 取消任务

POST   /api/projects/{id}/chat           — 对话查询（SSE 流式）
GET    /api/projects/{id}/chat/history   — 对话历史

POST   /api/projects/{id}/search         — 搜索 wiki
GET    /api/projects/{id}/wiki/{path}    — 读取 wiki 页面
GET    /api/projects/{id}/wiki/tree      — 文件树

GET    /api/projects/{id}/graph          — 知识图谱数据
GET    /api/projects/{id}/graph/insights — 图谱洞察

POST   /api/projects/{id}/research       — 启动深度研究
GET    /api/projects/{id}/research/tasks — 研究任务列表

GET    /api/projects/{id}/reviews        — 审核列表
POST   /api/projects/{id}/reviews/{id}   — 处理审核项

PUT    /api/projects/{id}/config         — 更新项目配置（LLM/Embedding/Search）
```

---

## Task 14: Web Clipper 适配

**源文件**: `extension/` + `src-tauri/src/clip_server.rs`

Chrome 扩展的 `popup.js` 当前发送到 `http://localhost:3456`（Rust clip server）。
改造方案：
- FastAPI 新增 `POST /api/clip` 端点，接收 JSON 格式剪藏内容
- 保持与 Chrome 扩展的协议兼容（或提供适配层）

---

## Task 15: 配置与部署

- `server/.env` 环境变量配置（默认 LLM/API keys/端口等）
- `server/Dockerfile` 多阶段构建
- `docker-compose.yml` 添加 server 服务
- API Key 认证中间件（可选，`X-API-Key` header）

---

## 工作量估算

| 模块 | 估算代码行 | 优先级 |
|------|-----------|--------|
| 项目脚手架 + 数据模型 | ~300 行 | P0 |
| LLM 客户端 | ~200 行 | P0 |
| 文件操作 + 文档预处理 | ~250 行 | P0 |
| 摄入管线 + 队列 + 缓存 | ~600 行 | P0 |
| 搜索系统 | ~300 行 | P0 |
| 查询管线 (Chat) | ~250 行 | P0 |
| 知识图谱 | ~350 行 | P1 |
| 向量嵌入 | ~150 行 | P1 |
| 深度研究 | ~200 行 | P1 |
| 持久化 (SQLite) | ~200 行 | P0 |
| API 路由 | ~400 行 | P0 |
| Web Clipper 适配 | ~50 行 | P2 |
| 配置与部署 | ~100 行 | P1 |
| **总计** | **~3,350 行** | |

---

## 关键风险与对策

| 风险 | 对策 |
|------|------|
| Python Louvain 与 JS graphology-louvain 结果不一致 | 使用 `python-louvain`（同一算法的 Python 实现），社区 ID 可能不同但语义等价 |
| 文档预处理质量差异（Rust vs Python） | 用 `pdfplumber` 替代 `pypdf2` 以提高 PDF 提取质量；逐格式验证 |
| 流式 SSE 兼容性 | 使用 `sse-starlette` 库，与前端 EventSource 协议一致 |
| 多项目并发安全 | SQLite WAL 模式 + 项目级文件锁；摄入队列保持串行语义 |
| Prompt 模板迁移格式偏差 | 直接复制 `migration-ref/prompts/` 原文，用 Jinja2 变量替换 |
