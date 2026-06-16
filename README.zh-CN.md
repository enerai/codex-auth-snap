# codex-auth-snap

[English](README.md) | 中文

极简, 可审计, 完全离线的 Codex ChatGPT `auth.json` 快照切换工具, 适用于编程量大的多 ChatGPT 账号 macOS, Linux 和 Windows 用户.

`codex-auth-snap` 是一个极简本地 CLI, 面向高频使用 Codex 编程, 且持有多个 ChatGPT 账号的开发者. 它用来在同一台 Mac, Linux 或 Windows 机器上切换你自己拥有或被明确授权使用的 Codex ChatGPT 账号. 它只保存和恢复本机 `auth.json` 快照. 它没有第三方运行时依赖, 不安装依赖树, 不联网, 也不会打印任何凭据内容.

本项目与 OpenAI 没有关联.

## 项目定位

Codex ChatGPT auth 可以保存在:

```text
$CODEX_HOME/auth.json
```

如果你编程量很大, 经常用 Codex 做代码生成, 重构, 调试和长时间 agentic coding, 并且在同一台 Mac, Linux 或 Windows 机器上有多个被授权使用的 ChatGPT / Codex 账号, 切换账号本质上只是一个本机文件操作: 保存当前 `auth.json`, 恢复另一个 `auth.json`, 然后重启 Codex 让它重新读取这个文件.

这个工具把这套流程做成明确, 可重复, 容易审计的 CLI.

## 适合谁

这个项目适合这些用户:

- 编程量大, 高频使用 Codex 写代码, 重构, 调试和跑 agentic coding 的开发者.
- 合法持有多个 ChatGPT 或 ChatGPT Plus 账号, 并希望按个人, 工作, 地区, 团队或账单场景切换使用的人.
- 想快速切换账号, 但不想依赖浏览器反复登录, 重型依赖工具, 后台 agent 或联网服务的人.
- 偏好极简本地 CLI, 希望一眼看懂工具行为和安全边界的人.

它不用于凭据共享, 账号池化或绕过平台策略.

## 宣传卖点

- **极简 CLI 逻辑**: bash 和 PowerShell 分开成独立脚本, 直接做本机文件操作, 没有 daemon, 没有后台服务.
- **零第三方运行时依赖**: 没有 npm 依赖树, 没有 pip 环境, 没有打包进来的传递依赖.
- **更小的供应链攻击面**: CLI 使用系统自带工具. macOS 分支使用 `plutil`, BSD `stat` 和 `shasum`; Linux 分支使用 `python3`, GNU `stat` 和 `sha256sum`; Windows 分支使用 PowerShell 自带 JSON, hash 和 ACL API.
- **设计上完全离线**: 不发网络请求, 不调用 OpenAI API, 不上传 telemetry.
- **具体可验证的安全属性**: macOS/Linux 使用严格 POSIX 文件权限, Windows 拒绝 reparse point 并 best-effort 收紧当前用户 ACL, 有界 JSON 输出, token 脱敏, 云同步目录风险提醒.
- **容易审计**: 核心行为都在小的 OS-specific 脚本里, 测试只使用临时目录.

## 搜索关键词

为了方便在 GitHub 搜到本项目, README 中保留这些中英文关键词:

```text
Codex 账号切换
Codex 登录切换
Codex auth.json 切换
Codex 多账号
ChatGPT 账号切换
ChatGPT 多账号
ChatGPT Plus 多账号
多个 ChatGPT 账号
多个 Codex 账号
编程量大 ChatGPT 账号切换
高频编程 Codex 账号切换
macOS Codex 工具
Linux Codex 工具
Windows Codex 工具
离线 CLI
无依赖 CLI
零依赖 shell 脚本
零依赖 PowerShell 脚本
供应链安全 CLI
本地优先 auth 切换工具
```

建议设置的 GitHub topics:

```text
codex
chatgpt
openai
codex-cli
codex-auth
auth-switcher
account-switcher
chatgpt-plus
macos
linux
windows
bash
powershell
cli
offline
no-dependencies
supply-chain-security
local-first
```

## 关于“绝对安全”

任何 CLI 都不能诚实承诺能防住恶意软件, 已被攻破的本机用户账号, 或用户手动分享凭据.

`codex-auth-snap` 承诺的是更窄, 但可验证的安全边界:

- 绝对不联网.
- 绝对不调用 `codex logout`.
- 绝对不刷新 token.
- 绝对不解析 JWT.
- 绝对不打印 `access_token`, `refresh_token`, `id_token`, 或完整 `auth.json`.
- 拒绝 symlink auth 路径和 state 文件.
- 在 macOS 和 Linux 上, state 目录写成 `700` 权限.
- 在 macOS 和 Linux 上, auth 快照和 state 文件写成 `600` 权限.
- 在 Windows 上, 拒绝 reparse point, 并 best-effort 收紧当前用户 ACL.

请把每一个 `auth.json` 和 `*.auth.json` 都当成密码处理.

## 它会做什么

- 把当前 active Codex ChatGPT `auth.json` 保存成一个本地命名快照.
- 把已保存的快照恢复到 `$CODEX_HOME/auth.json`.
- 提供添加另一个账号时使用的安全登录流程.
- 保持快照和 state 文件权限足够严格.
- 提供 `doctor` 命令做本地诊断.
- 提供 `--json` 输出, 方便自动化和 agent-friendly 工具调用.

## 它不会做什么

- 不共享, 池化, 售卖或代理账号.
- 不绕过用量限制, ban, rate limit 或 policy enforcement.
- 不自动轮换账号.
- 不调用 OpenAI API 或任何网络服务.
- 不解析, 导出或打印 token 值.

只把这个工具用于你自己拥有或被明确授权使用的账号.

## 平台支持

支持的平台:

- macOS 和 Linux 使用 `./codex-auth-snap`
- Windows 使用 `.\codex-auth-snap.ps1`
- macOS/Linux 上的 bash
- Windows PowerShell 5+ 或 PowerShell 7+
- Codex 已配置为 file-backed ChatGPT auth

平台相关的系统组件分开处理:

- macOS: `plutil`, BSD `stat`, `shasum`
- Linux: `python3`, GNU `stat`, `sha256sum`
- Windows: PowerShell `ConvertFrom-Json`, `Get-FileHash`, `Get-Acl`, `Set-Acl`

## 安装

在仓库根目录执行:

```bash
./codex-auth-snap install
```

Windows 使用 PowerShell 脚本:

```powershell
powershell -ExecutionPolicy Bypass -File .\codex-auth-snap.ps1 install
```

默认安装路径是:

```text
macOS/Linux: $HOME/.local/bin/codex-auth-snap
Windows:     $HOME/.local/bin/codex-auth-snap.ps1
```

如果 `~/.local/bin` 已在 `PATH` 中, 可以直接运行:

```bash
codex-auth-snap version
```

Windows:

```powershell
codex-auth-snap.ps1 version
```

也可以安装到自定义位置:

```bash
./codex-auth-snap install --bin-dir "$HOME/bin"
./codex-auth-snap install --prefix "$HOME/.local"
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\codex-auth-snap.ps1 install --bin-dir "$HOME\bin"
powershell -ExecutionPolicy Bypass -File .\codex-auth-snap.ps1 install --prefix "$HOME\.local"
```

`install` 会复制当前脚本. 仓库升级后, 重新运行 `install` 即可更新已安装副本.

## 快速开始

初始化 Codex file-backed auth:

```bash
codex-auth-snap init --fix
codex-auth-snap --json doctor
```

保存当前已经登录的账号:

```bash
codex login
codex-auth-snap save personal
```

添加另一个账号:

```bash
codex-auth-snap begin-login work
codex login
codex-auth-snap finish-login
```

切换账号:

```bash
codex-auth-snap use personal
# 重启 Codex CLI 或 Codex App, 让它读取恢复后的 auth.json.

codex-auth-snap use work
# 再次重启 Codex CLI 或 Codex App.
```

查看已保存快照:

```bash
codex-auth-snap list
codex-auth-snap current
```

完整步骤见 [docs/quickstart.zh-CN.md](docs/quickstart.zh-CN.md).

## 路径

默认 Codex auth 路径:

```text
CODEX_HOME=${CODEX_HOME:-$HOME/.codex}
AUTH_FILE=$CODEX_HOME/auth.json
```

默认 snapshot state 路径:

```text
CODEX_AUTH_SNAP_HOME=${CODEX_AUTH_SNAP_HOME:-$HOME/.codex-auth-snap}
```

state 目录结构:

```text
$CODEX_AUTH_SNAP_HOME/
├── accounts/
├── meta/
├── before-login/
├── current
├── pending-login
└── lock/
```

权限规则:

```text
directories: 700
auth.json / *.auth.json / meta / current / pending-login: 600
```

Windows PowerShell 脚本不使用 POSIX `600`/`700` mode, 它会拒绝 reparse point, 并 best-effort 收紧当前用户 ACL.

`CODEX_AUTH_SWITCH_HOME` 和 `CODEX_SWAP_HOME` 仍然作为迁移用旧环境变量兼容. 如果多个变量同时存在, `CODEX_AUTH_SNAP_HOME` 优先.

## 命令

```text
codex-auth-snap [--json] init [--fix] [--force]
codex-auth-snap [--json] save <name> [--force]
codex-auth-snap [--json] use <name> [--force]
codex-auth-snap [--json] begin-login <name> [--force]
codex-auth-snap [--json] finish-login [name] [--force]
codex-auth-snap [--json] abort-login [--force]
codex-auth-snap [--json] install [--prefix <dir>|--bin-dir <dir>] [--force]
codex-auth-snap [--json] list
codex-auth-snap [--json] current
codex-auth-snap [--json] remove <name> [--active-too]
codex-auth-snap [--json] doctor
codex-auth-snap [--json] paths
codex-auth-snap [--json] version
```

Windows 使用同一组命令, 入口换成 `codex-auth-snap.ps1`.

账号别名可以使用 ASCII 字母, 数字, 点, 下划线和连字符.

## JSON 输出

所有命令都支持 `--json`. JSON 模式下, stdout 只输出一个 envelope:

```json
{
  "content": [{"type": "text", "text": "short summary"}],
  "structuredContent": {"result": {}},
  "isError": false
}
```

业务失败会返回非 0 exit code:

```json
{
  "content": [{"type": "text", "text": "short error"}],
  "structuredContent": {
    "error": {
      "code": "stable_error_code",
      "message": "what failed",
      "retryable": false,
      "field_errors": [],
      "suggested_fix": "what to do next"
    }
  },
  "isError": true
}
```

JSON 输出刻意保持有界. `list` 只展示账号别名, 保存时间, current 标记和短 hash.

## 安全使用

- 不要提交 auth 快照.
- 不要分享 auth 快照.
- 不要把 auth 快照复制到另一台机器.
- 不要把 snapshot state 放进 iCloud, Dropbox, Google Drive, OneDrive 或其他云同步目录.
- 不要让多个 Codex session 并发使用同一个账号快照.
- 切换账号后重启 Codex CLI 或 Codex App.

更多说明见 [SECURITY.md](SECURITY.md) 和 [docs/security-model.md](docs/security-model.md).

## 排障

运行:

```bash
codex-auth-snap --json doctor
```

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\codex-auth-snap.ps1 --json doctor
```

`doctor` 会检查本地路径, file-backed auth 配置, state 权限, symlink 风险, invalid JSON, pending login state, 已安装副本 drift, 云同步路径风险和正在运行的 Codex 进程.

排障说明见 [docs/troubleshooting.md](docs/troubleshooting.md).

## 测试

测试只使用临时目录, 不会触碰真实 `~/.codex`:

```bash
bash tests/test_codex_auth_snap.sh
bash tests/test_codex_auth_snap_windows_contract.sh
```

Windows contract 测试在没有 PowerShell 时只做静态检查. 如果当前环境存在 `pwsh` 或 `powershell`, 它还会用临时目录跑 JSON/init/save/list smoke tests.

## 许可证

MIT. 见 [LICENSE](LICENSE).
