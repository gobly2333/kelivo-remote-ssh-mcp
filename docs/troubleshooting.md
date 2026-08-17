# Troubleshooting

## 先判断哪一层坏了

在运行 MCP 的 VPS 上依次检查：

```bash
pm2 status
curl http://127.0.0.1:3000/healthz
sudo systemctl is-active cloudflared
curl -i --max-time 15 \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"curl-test","version":"1.0"}}}' \
  "https://你的域名/你的随机路径/mcp"
```

正常结果：

- PM2 状态为 `online`。
- healthz 返回 `ok`。
- cloudflared 返回 `active`。
- 公网 MCP 初始化请求返回 HTTP 200，并在响应中包含 JSON-RPC 初始化结果。

公网测试的常见结果：

- `404`：随机路径错误，必须使用安装器输出的完整 `/随机路径/mcp` 地址。
- `502`：Cloudflare connector 无法访问 VPS 的 `localhost:3000`。
- `403`：请求被 Cloudflare Access、WAF 或其他访问规则拦截。
- HTTP 200，但 Kelivo 连接失败：检查 Kelivo 是否选择了 **HTTP** 传输，而不是 SSE。

## Cloudflare 返回 502

502 表示 Cloudflare hostname 和 Tunnel 已经存在，但 connector 无法访问配置的源站 `http://localhost:3000`。

常见原因：

- supergateway 前台进程随 SSH/Termius 断开而结束。
- PM2 进程不断崩溃重启。
- Cloudflare connector 安装在 A 服务器，而 supergateway 运行在 B 服务器；此时 `localhost` 指向 A。
- Published application 的 Service URL 端口填错。

查看：

```bash
pm2 logs kelivo-remote-ssh-mcp --lines 50 --nostream
curl http://127.0.0.1:3000/healthz
```

## All configured authentication methods failed

这不是 MCP 断线，而是 SSH MCP 已收到工具调用，但 SSH 认证失败。

密码认证测试：

```bash
ssh -o PubkeyAuthentication=no \
  -o PreferredAuthentications=password \
  用户名@目标Host
```

如果目标 Host 是 `127.0.0.1`，该测试必须在运行 MCP 的同一台 VPS 上执行。

密码中包含 `$`、`*`、`!`、空格等字符时，不要直接拼进多层 shell 命令。本项目通过 JSON 配置文件保存密码，避免 shell 展开造成密码被截断或改变。

## PM2 显示 online，但端口拒绝连接

PM2 可能刚启动进程，而程序随后立即崩溃。查看重启次数和日志：

```bash
pm2 status
pm2 describe kelivo-remote-ssh-mcp
pm2 logs kelivo-remote-ssh-mcp --lines 100 --nostream
```

## Kelivo 能连接，但模型不调用工具

- 确认四个 MCP 工具已出现。
- 在助手配置或输入框工具面板中勾选该 MCP。
- 使用明确提示词要求“立即调用 execute-command，不要让我手动执行”。
- 确认当前模型/API 支持 Tool Calls。

## 旧版 SSE 配置偶发断线

旧版项目使用长期保持的 HTTP+SSE 连接。手机切后台或切换网络后，如果 Kelivo 没有及时重建连接，可能出现服务端正常但工具暂时不可用。

当前版本默认使用 Streamable HTTP。更新仓库并重新运行安装器后，在 Kelivo 中选择 **HTTP**，填写安装器新输出的 `/随机路径/mcp` 地址。重新安装会生成新路径，旧 SSE 地址不再使用。

## `127.0.0.1` 到底是谁

`127.0.0.1` 永远指“当前发起连接的那台机器”。本架构中 SSH MCP 运行在 VPS 上，因此它连接 `127.0.0.1:22`，就是连接同一台 VPS 的 sshd。Kelivo 在手机上并不会改变这一点。
