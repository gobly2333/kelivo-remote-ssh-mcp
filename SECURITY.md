# Security

这个项目会把 SSH 命令执行能力交给远程 MCP 客户端。若目标用户是 `root`，成功的 MCP 调用几乎等同于 root shell。

## 必须知道的风险

- Cloudflare Tunnel 只负责传输和隐藏源站 IP；未配置 Access 时，公网 hostname 仍可被任何人访问。
- 随机 MCP 路径不是可靠认证，只是降低被自动扫描发现的概率。
- LLM 可能误解指令、受到提示注入影响，或执行范围超出用户预期。
- 密码认证配置保存在 VPS 的 root-only 文件中。它不会进入 Git 或 PM2 dump，但 root 进程仍可读取。
- 不要把真实密码、Tunnel token、域名后台截图、`.env` 或生成的 `ssh-config.json` 提交到仓库。

## 建议的最低保护

1. 在 Kelivo 中启用 MCP 手动审批。
2. 为 MCP 使用专用低权限 Linux 用户，不直接使用 root。
3. 使用 `--whitelist` 或 `--blacklist` 限制命令。
4. 使用 Cloudflare Access 或其他能为 Streamable HTTP 请求添加认证头的访问控制层。
5. 定期更新 Node.js、cloudflared、supergateway 和 SSH MCP。
6. 定期检查 `pm2 logs` 和系统 SSH 日志。

## 凭据泄露处理

一旦密码或 Tunnel token 出现在聊天、截图、日志或 Git 历史中：

1. 立即轮换凭据。
2. 不要只删除最新提交；应清理 Git 历史并重新轮换，因为旧对象可能仍可访问。
3. 重启 MCP 和 Cloudflare connector，使旧凭据失效。
4. 检查 SSH 登录记录和 Cloudflare Tunnel 活动。

## 报告漏洞

请不要在公开 Issue 中粘贴真实凭据或可用的 MCP URL。使用 GitHub Security Advisory 私下报告。
