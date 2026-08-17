# Kelivo Remote SSH MCP

把一台 Ubuntu/Debian VPS 通过 Cloudflare Tunnel 暴露为远程 Streamable HTTP MCP，让 Kelivo 中支持工具调用的模型执行 SSH 命令、上传和下载文件。

本项目不是新的 SSH MCP 实现，而是一个可复用的部署套件，组合了：

- [`@fangjunjie/ssh-mcp-server`](https://github.com/classfang/ssh-mcp-server)：提供 `execute-command`、`upload`、`download`、`list-servers` 四个 MCP 工具。
- [`supergateway`](https://github.com/supercorp-ai/supergateway)：把 stdio MCP 转换为 Kelivo 可连接的 Streamable HTTP 服务。
- [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/get-started/create-remote-tunnel/)：把 VPS 上的 `localhost:3000` 映射到 HTTPS 域名。
- [PM2](https://pm2.keymetrics.io/)：让网关在 SSH 断线后继续运行。

## 工作原理

```text
Kelivo / LLM
     │ HTTPS + Streamable HTTP
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

## 首次部署时，人类和模型分别能做什么

如果你目前只有 Kelivo 里的普通 LLM，没有 Codex、Claude Code 或其他已经连接 VPS 的 Agent，**首次部署必须由人类通过 SSH 手动完成**。

在 MCP 连接成功之前，模型只能根据你粘贴回来的终端输出提供下一条命令，不能直接操作 VPS。你需要亲自完成：

- 使用 Termius、系统终端等 SSH 客户端登录 VPS。
- 在 Cloudflare 网页创建 Tunnel，并把页面生成的 connector 安装命令粘贴到 VPS。
- 在 VPS 中安装基础环境、克隆本仓库并运行安装器。
- 把安装器输出的 HTTP MCP 地址填入 Kelivo，并将 MCP 分配给助手。

完成这些步骤以后，只要所用模型 API 支持 Tool Calls，它就能通过 Kelivo 调用 `execute-command`、`upload`、`download` 和 `list-servers`，不要求模型本身是 Codex。

## 1. 登录 VPS 并安装基础环境

下面的命令需要由人类在 VPS 的 SSH 终端中执行。Ubuntu 用户使用具有 `sudo` 权限的账号；直接以 `root` 登录时可以省略 `sudo`。

先更新软件索引并安装基础工具：

```bash
sudo apt update
sudo apt install -y ca-certificates curl git openssl
```

检查 Node.js 版本：

```bash
node -v
```

如果提示找不到命令，或者主版本低于 20，可使用 NodeSource 为 Ubuntu/Debian 安装系统级 Node.js 22：

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x -o /tmp/nodesource_setup.sh
sudo -E bash /tmp/nodesource_setup.sh
sudo apt install -y nodejs
```

安装 PM2：

```bash
sudo npm install -g pm2@latest
```

逐项验证环境：

```bash
git --version
node -v
npm -v
pm2 -v
curl --version | head -n 1
openssl version
```

其中 Node.js 必须为 `v20` 或更高版本。安装器会在 PM2 缺失时尝试自动安装 PM2，但不会替你安装 Node.js、npm、Git、curl 或 openssl，因此建议先完成本节。

## 2. 创建 Cloudflare Tunnel

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

页面会根据当前 Tunnel 生成带有专属 Token 的 `cloudflared` 安装命令，优先使用页面显示的命令，不要把 Token 写进公开教程、截图或 Git 仓库。

安装 connector 后可在 VPS 检查：

```bash
cloudflared --version
sudo systemctl status cloudflared --no-pager
```

## 3. 部署 MCP

`git clone` 只会把项目文件下载到 VPS，出于安全原因不会自动执行任何安装脚本。首次部署时，需要由人类在 SSH 终端中依次运行下面三条命令：

```bash
git clone https://github.com/gobly2333/kelivo-remote-ssh-mcp.git
cd kelivo-remote-ssh-mcp
sudo bash scripts/install.sh
```

如果仓库此前已经克隆完成，只需进入目录并运行安装器：

```bash
cd kelivo-remote-ssh-mcp
sudo bash scripts/install.sh
```

直接以 `root` 登录 VPS 时，可以省略 `sudo`：

```bash
cd kelivo-remote-ssh-mcp
bash scripts/install.sh
```

安装器启动后会依次询问以下内容。方括号中的值是默认值，想使用默认值时直接按回车：

1. `Public MCP domain`：填写前面在 Cloudflare 创建的完整主机名，例如 `mcp.example.com`。不要填写 `https://`，也不要添加 `/mcp`。
2. `SSH host [127.0.0.1]`：如果 MCP 与要操作的 SSH 服务位于同一台 VPS，直接回车。
3. `SSH port [22]`：SSH 没有修改过端口时直接回车。
4. `SSH username [root]`：使用 root 登录时直接回车；否则填写实际 SSH 用户名。
5. `Authentication`：输入 `1` 使用密码，输入 `2` 使用私钥；直接回车默认选择密码。
6. `SSH password` 或 `Absolute private key path`：输入对应凭据。输入密码时终端不会显示字符，这是正常现象，输完按回车即可。
7. `Local MCP port [3000]`：Cloudflare Service URL 使用 `http://localhost:3000` 时直接回车。

例如，同一台 VPS、root 用户、22 端口、密码认证的填写方式是：

```text
Public MCP domain (example: mcp.example.com): mcp.example.com
SSH host [127.0.0.1]:              # 直接回车
SSH port [22]:                     # 直接回车
SSH username [root]:               # 直接回车
Authentication:
  1) Password
  2) Private key
Choose [1]:                         # 直接回车
SSH password:                       # 输入密码，屏幕不会显示
Local MCP port [3000]:              # 直接回车
```

安装器随后会自动：

- 生成随机的 MCP 路径。
- 把 SSH 和运行配置保存到仅 root 可读的配置文件。
- 使用 PM2 启动 `supergateway` 和 SSH MCP Server。
- 保存 PM2 进程列表。
- 检查 `http://127.0.0.1:3000/healthz` 是否正常。

密码输入不会回显。配置保存到：

```text
/etc/kelivo-remote-ssh-mcp/ssh-config.json
/etc/kelivo-remote-ssh-mcp/runtime.env
```

两个文件权限均为 `600`，不会进入 Git 仓库或 PM2 参数。密码认证仍意味着拥有 VPS root 权限的进程可以读取凭据，请根据自己的威胁模型选择认证方式。

完成后安装器会显示一条带随机路径的 Kelivo Streamable HTTP URL，例如：

```console
MCP is healthy.
Kelivo transport: HTTP (Streamable HTTP)
Kelivo URL: https://mcp.example.com/4df2.../mcp
```

复制 `Kelivo URL:` 后面的**完整地址**。不要只填写域名，也不要自行把它改成固定的 `/mcp`。

如果没有看到 `MCP is healthy.`，安装器会给出日志检查命令。也可以手动运行：

```bash
pm2 logs kelivo-remote-ssh-mcp --lines 100 --nostream
curl http://127.0.0.1:3000/healthz
```

随机路径只能降低被扫描发现的概率，**不等于身份认证**。真正公开使用时请阅读 [SECURITY.md](SECURITY.md)。

重新运行安装器会替换现有 PM2 进程并生成新的随机路径，因此 Kelivo 中原来的 MCP 地址也需要更新。

## 4. Kelivo 配置

在 Kelivo 的 MCP 设置中添加：

```text
名称：VPS SSH
传输类型：HTTP
服务器地址：使用安装器输出的完整 MCP URL
```

这里的 HTTP 指 MCP 的 **Streamable HTTP** 传输。它使用单一 `/mcp` 端点，不依赖旧式 HTTP+SSE 的长期连接，更适合手机切后台、切换网络后重新发起工具调用。

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
