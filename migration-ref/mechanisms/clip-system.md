# Chrome 扩展与剪藏系统

> 来源：[`extension/`](../../extension/) 目录、[`src-tauri/src/clip_server.rs`](../../src-tauri/src/clip_server.rs)、[`src/lib/clip-watcher.ts`](../../src/lib/clip-watcher.ts)

## 架构

```
Chrome Extension → Clip Server (Rust, :19827) → Clip Watcher (前端轮询) → Ingest Queue
```

## Chrome Extension（Manifest V3）

关键文件：[`extension/manifest.json`](../../extension/manifest.json)、[`extension/popup.js`](../../extension/popup.js)

- **Readability.js**：Mozilla 的正文提取库（Firefox 阅读模式同款），剥离广告/导航/侧边栏
- **Turndown.js**：HTML → Markdown 转换器，支持表格
- 项目选择器：支持多项目，通过本地 API 获取项目列表
- 离线预览：即使应用未运行也可查看提取结果

## Clip Server（Rust tiny_http，端口 19827）

| 端点 | 方法 | 功能 |
|------|------|------|
| `/clip` | POST | 接收网页剪藏（title + url + markdown content） |
| `/clips/pending` | GET | 获取待处理剪藏列表 |
| `/project` | POST | 设置当前项目路径 |
| `/project` | GET | 获取当前项目路径 |
| `/projects` | POST | 更新项目列表（供扩展项目选择器） |
| `/projects` | GET | 获取项目列表 |
| `/status` | GET | 服务健康状态 |

跨域支持：手动 CORS 头

## Clip Watcher（前端轮询）

[`src/lib/clip-watcher.ts`](../../src/lib/clip-watcher.ts)：

- 每 3 秒 GET `/clips/pending`
- 检测到新剪藏后：将内容保存到 `raw/sources/` → 调用 `enqueueIngest`
- 走完整的两步摄入流程

## 迁移替代方案

| 本项目实现 | 替代方案 |
|-----------|----------|
| Rust tiny_http | 任何语言的 HTTP 框架（Express / FastAPI / Go net/http） |
| Readability.js + Turndown.js | Python: newspaper3k / readability-lxml + markdownify |
| Chrome Extension | Firefox WebExtension / Bookmarklet / 任何推送机制 |
| 3 秒轮询 | WebSocket / SSE 推送 |

**迁移建议**：如果做 Web 应用，Clip Server 可以直接合并到后端 API，不需要独立进程。前端轮询也可以改为 WebSocket 推送。
