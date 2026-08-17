# Kelivo Remote SSH MCP

把一台 Ubuntu/Debian VPS 通过 Cloudflare Tunnel 暴露为远程 SSE MCP，让 Kelivo 中支持工具调用的模型执行 SSH 命令、上传和下载文件。

本项目不是新的 SSH MCP 实现，而是一个可复用的部署套件，组合了：

- [`@fangjunjie/ssh-mcp-server`](https://github.com/classfang/ssh-mcp-server)：提供 `execute-command`、`upload`、`download`、`list-servers` 四个 MCP 工具。
- [`supergateway`](https://github.com/supercorp-ai/supergateway)：把 stdio MCP 转换为 Kelivo 可连接的 SSE 服务。
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/)：把 VPS 上的 `localhost:3000` 映射到 HTTPS 域名。
- [PM2](https://pm2.keymetrics.io/)：让网关在 SSH 断线后继续运行。

## 工作原理

```text
Kelivo / LLM
     │ HTTPS + SSE
     ▼
Cloudflare Tunnel
     │ http://localhost:3000
     ▼
supergateway
     │ stdio MCP
     ▼
ssh-mcp-server
     │ SSH
     ▼
目标 VPS
```

如果 MCP 和目标 SSH 服务在同一台 VPS 上，SSH Host 使用 `127.0.0.1` 是正确的：这里的 `127.0.0.1` 指 VPS 自己，不是手机。

## 开始前需要什么

- 一台 Ubuntu 或 Debian VPS，并拥有 `root` 或 `sudo` 权限。
- VPS 的 SSH 服务可用；密码认证或私钥认证任选其一。
- 一个已经托管到 Cloudflare、状态为 Active 的域名。
- Cloudflare Tunnel connector 安装在运行 MCP 的同一台 VPS 上。
- Node.js 20+、npm、PM2、curl、openssl。
- Kelivo 1.2.0 或更新版本。
- 一个支持函数/工具调用的模型，例如 DeepSeek API 中支持 Tool Calls 的模型。

不需要把域名的 A 记录指向 VPS，也不需要开放公网 `3000` 端口。

## 1. 创建 Cloudflare Tunnel

1. 打开 Cloudflare 主控制台的 **Networking → Tunnels**。
2. 选择 **Create a tunnel**，填写名称并创建。
3. Ubuntu 用户选择 **Debian / 64-bit**。
4. 在 VPS 执行页面给出的 connector 安装命令，等待状态变成 `Healthy`。
5. 进入该 Tunnel 的 **Routes → Add route → Published application**。
6. 填写：

```text
Hostname: mcp.example.com
Service URL: http://localhost:3000
```

保存后 Cloudflare 会为这个 hostname 创建对应的 Tunnel DNS 路由。

## 2. 安装环境

检查现有版本：

```bash
node -v
npm -v
pm2 -v
cloudflared --version
```

如果 Node.js 或 PM2 尚未安装，请先安装 Node.js 20+，然后执行：

```bash
npm install -g pm2
```

Cloudflare Tunnel 页面会针对你的系统给出当前版本的 `cloudflared` 安装命令，优先使用该命令。

## 3. 一键部署 MCP

克隆仓库：

```bash
git clone https://github.com/gobly2333/kelivo-remote-ssh-mcp.git
cd kelivo-remote-ssh-mcp
```

运行安装器：

```bash
sudo bash scripts/install.sh
```

安装器会询问：

- MCP 公网域名，例如 `mcp.example.com`。
- SSH Host；MCP 与目标 VPS 是同一台机器时保持 `127.0.0.1`。
- SSH 端口和用户名。
- 使用密码还是私钥认证。
- 是否配置危险命令黑名单。

密码输入不会回显。配置保存到：

```text
/etc/kelivo-remote-ssh-mcp/ssh-config.json
/etc/kelivo-remote-ssh-mcp/runtime.env
```

两个文件权限均为 `600`，不会进入 Git 仓库或 PM2 参数。密码认证仍意味着拥有 VPS root 权限的进程可以读取凭据，请根据自己的威胁模型选择认证方式。

完成后安装器会显示一条带随机路径的 Kelivo SSE URL，例如：

```text
https://mcp.example.com/4df2.../sse
```

随机路径只能降低被扫描发现的概率，**不等于身份认证**。真正公开使用时请阅读 [SECURITY.md](SECURITY.md)。

## 4. Kelivo 配置

在 Kelivo 的 MCP 设置中添加：

```text
名称：VPS SSH
传输类型：SSE
服务器地址：使用安装器输出的完整 SSE URL
```

连接成功后应显示四个工具：

- `execute-command`
- `upload`
- `download`
- `list-servers`

还需要把这个 MCP 勾选给当前助手。建议打开 Kelivo 的 MCP 手动审批，至少对写文件、删除、重启和系统管理命令逐次确认。

测试提示词：

```text
立即调用 execute-command 工具执行：
hostname && curl -4 ifconfig.me && whoami && pwd
不要让我手动运行。
```

## 5. 常用管理命令

```bash
pm2 status
pm2 logs kelivo-remote-ssh-mcp --lines 50 --nostream
curl http://127.0.0.1:3000/healthz
sudo systemctl status cloudflared --no-pager
```

修改配置后重启：

```bash
pm2 restart kelivo-remote-ssh-mcp
pm2 save
```

设置 PM2 开机启动：

```bash
pm2 startup
```

PM2 会打印一条需要以 root 执行的命令。执行那条命令后再运行：

```bash
pm2 save
```

## 排错

详见 [docs/troubleshooting.md](docs/troubleshooting.md)。最常见的判断：

- Cloudflare `502`：Tunnel 到 `localhost:3000` 不通，通常是 MCP 进程停止或 Tunnel 装在了另一台服务器。
- `All configured authentication methods failed`：MCP 正常，但 SSH 用户名、密码、私钥或 sshd 认证策略有问题。
- 能看到工具但模型不调用：MCP 已连接，不代表已分配给当前助手；检查 Kelivo 的助手工具选择。
- SSH 断开后服务消失：检查是否由 PM2 启动，而不是在 Termius 前台直接运行。

## 上游项目与许可

本仓库不复制或重新发布上游源码。运行时通过 npm 获取：

- `supergateway`，MIT License。
- `@fangjunjie/ssh-mcp-server`，ISC License。

本部署套件自身使用 MIT License。
