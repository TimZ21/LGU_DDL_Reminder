# 拾期 Windows 预览版 · Shiqi for Windows

Windows 版基于 macOS 1.2.0 的行为实现，使用 C#、.NET 10 和 Avalonia。代码和数据目录独立于现有 Swift macOS / iOS 工程。它不包含此前讨论的课程内容/公告抓取功能。

The Windows preview follows the behavior of macOS 1.2.0, using C#, .NET 10 and Avalonia. Its code and app data are separate from the existing Swift macOS/iOS projects. Course-content and announcement scraping are not included.

## 安装与使用 · Install and use

完整中英双语安装、连接、提醒及卸载说明见 [INSTALL.txt](INSTALL.txt)。目标是 Windows 11 x64/ARM64，Windows 10 22H2 x64 为兼容目标。ZIP 包含运行时，解压后直接运行 **Shiqi.exe**，无需另装 .NET。请保留整个应用文件夹。

See [INSTALL.txt](INSTALL.txt) for the bilingual installation, connection, reminder and removal guide. Targets Windows 11 x64/ARM64, with Windows 10 22H2 x64 as a compatibility target. Extract the ZIP and run **Shiqi.exe**; the runtime is included. Keep the entire application folder.

**预览状态 / Preview status:** 本机为 Mac。跨平台核心测试和跨编译不能代替真实 Windows 上的凭据、通知、系统托盘、勿扰、休眠恢复、启动和 DPI 测试。未签名包可能触发 SmartScreen，当前不宣称经过 Microsoft 签名或认证。Windows CI 配置已提供，只有推送后实际运行成功才代表 CI 通过。

This project was developed on a Mac. Core tests and cross-compilation do not replace real Windows tests for credentials, notifications, tray behavior, Do Not Disturb, sleep/resume, startup and DPI. The unsigned build may trigger SmartScreen. No Microsoft signing or certification is claimed. A Windows CI workflow is supplied; CI is only verified after an actual successful run.

## 功能与平台差异 · Features and platform differences

| 功能 / Feature | Windows |
| --- | --- |
| Blackboard 日历订阅 / Calendar subscription | HTTPS/webcal；默认每 15 分钟同步 / every 15 minutes by default |
| ICS、手动任务、搜索与分组 / ICS, manual tasks, search and date groups | 支持 / Supported |
| 完成状态 / Completion | 重导入及唯一匹配的 UID 变化后保留 / Preserved across reimports and uniquely matched regenerated UIDs |
| 时间 / Time | 深圳 UTC+8、IANA 时区、Windows 时区别名；UTC 时刻不变 / Shenzhen UTC+8, IANA/Windows zone aliases; preserves instants |
| 中英文与紫金配色 / Chinese-English and purple-gold UI | 支持 / Supported |
| 提醒 / Reminders | 原生通知区通知；保持程序运行；恢复时仅补发最近 5 分钟 / Native notification-area alerts; app must run; five-minute catch-up on resume |
| 登录时启动 / Start at sign-in | 用户可选，默认关闭 / Optional, off by default |
| Apple 提醒事项 / Apple Reminders | Windows 不支持 / Unavailable on Windows |
| Mac/Windows 数据同步 / Cross-device app-data sync | 无；可分别连接同一日历，完成状态各自保存 / None; both can subscribe to the same feed, completion stays local |

日历解析是 Swift `DeadlineCore` 支持子集的 C# 移植：VEVENT/VTODO、折行转义、UTC/TZID/浮动时间、仅日期、取消、DAILY/WEEKLY、EXDATE/RDATE、单次改期。复杂规则会显示提示并保留对应旧任务，而不是猜测时间。重复项展开范围为最近 30 天至未来一年，最多扫描 40000 天。

The parser ports Swift `DeadlineCore`'s conservative subset: VEVENT/VTODO, folding/escaping, UTC/TZID/floating/date-only values, cancellation, DAILY/WEEKLY recurrence, EXDATE/RDATE and individual overrides. Unsupported rules show warnings and protect corresponding existing tasks. Recurrence expands from 30 days ago through one year ahead, with a 40000-day scan limit.

## 源码构建 · Build from source

安装微软官方 [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0)。打包脚本还使用 Python 3 生成 ZIP 与校验文件；这些只是开发依赖，用户运行软件无需 Python。

Install the official [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0). Packaging also uses Python 3 for ZIP creation and checksums; these are development dependencies only.

Windows PowerShell, from the repository root:

```powershell
dotnet run --project windows/Shiqi.Tests -c Release
.\windows\build.ps1 -Runtime win-x64
# ARM64:
.\windows\build.ps1 -Runtime win-arm64
```

macOS / Linux, from the repository root:

```bash
bash scripts/test-windows.sh
bash scripts/build-windows.sh win-x64
bash scripts/build-windows.sh win-arm64
```

产物在 / Output: `dist/windows/1.2.0/`。ZIP 命名包含 `windows-preview.1`、架构和 `unsigned`；每个 ZIP 附带 SHA-256。生成时会核对 PE 架构与 .NET 运行时文件，解压校验 ZIP，并记录构建基准提交和工作区是否含未提交修改。

ZIP names include `windows-preview.1`, architecture and `unsigned`; a SHA-256 accompanies each. Packaging verifies the Windows PE architecture and runtime files, validates ZIP integrity, and records the base commit and whether the working tree has uncommitted changes.

Mac 上的隔离 UI 演示，不读取现有 Mac 应用数据、真实订阅或钥匙串，也不会发送通知：

Isolated Mac UI preview, without touching the existing Mac app data, real subscriptions or Keychain, or sending notifications:

```bash
dotnet run --project windows/Shiqi.Desktop -- --demo
dotnet run --project windows/Shiqi.Desktop -- --demo --english
```

Windows CI 模板保存在 `.github/workflow-templates/windows.yml`，当前不自动运行。需要启用时，将它复制到 `.github/workflows/windows.yml` 并由具备工作流写入权限的账户提交。该配置在 Windows runner 上执行测试并构建两个架构的 ZIP，上传 Actions artifacts；不会自动发布 GitHub Release。测试使用合成数据，Windows 凭据测试使用随机生成的专用条目，并在结束时清理。

The inactive Windows CI template is stored at `.github/workflow-templates/windows.yml`. To enable it, copy it to `.github/workflows/windows.yml` and commit using an account with workflow-write permission. It tests and builds both architectures on a Windows runner, uploading Actions artifacts without automatically publishing a Release. Tests use synthetic data; credential tests use a unique disposable entry and clean it up.

### 已完成的验证 · Completed verification

2026-11-04：Windows 核心 **42 项测试通过**；隔离 Headless UI **12 项检查通过**，包括中英文 1120×780 / 860×620 布局、搜索、完成状态、手动任务保存及语言设置；现有 Swift 核心 **32 项测试通过**。桌面工程编译为零警告、零错误。两个 Windows 架构均完成跨编译、PE 架构核对和 ZIP 完整性验证。

On 2026-11-04: **42 Windows core tests** and **12 isolated headless UI checks** passed, covering Chinese/English at 1120×780 and 860×620, search, completion, manual task saving and language settings. The existing **32 Swift core tests** also passed. Desktop compilation completed with zero warnings/errors. Both Windows architectures were cross-compiled with PE architecture and ZIP integrity checks.

UI 图片是隔离渲染结果，不是 Windows 实机截图。真实 Windows 上的学校日历访问、凭据读写、托盘、通知、登录启动和休眠恢复仍需按照下方清单测试；尚未运行远程 Windows CI。

UI images are isolated renderings, not screenshots of a running Windows desktop. Live campus access, Credential Manager, tray/notifications, sign-in startup and sleep/resume still need the Windows smoke tests below. Remote Windows CI has not been run.

```bash
dotnet run --project windows/Shiqi.UiTests -c Release -- dist/windows-preview/headless
```

## 数据与安全 · Data and security

- 共享链接只保存在当前 Windows 用户的 Credential Manager。任务、设置和通知去重记录保存在 `%LOCALAPPDATA%\Shiqi`。同步和存储失败时保留已有数据；无法读取本地数据时停止保存。
- 仅进行日历 GET 请求；没有作业提交、考试、评分或课程内容抓取代码。跨站/跨端口及 HTTP 重定向被阻止，保留系统 HTTPS 验证。请求有超时、5 MB 和严格 UTF-8 限制。
- 不需要自建服务器；通知使用 Windows API，不执行 PowerShell 脚本或拼接日历内容到命令行。托盘关闭窗口后继续工作，真正退出后不会后台提醒。
- 预览界面仅用合成数据。真实日历、凭据、日志、缓存和打包输出均不得提交 GitHub。

- The sharing link stays in the current user's Credential Manager. Tasks/settings and reminder deduplication live under `%LOCALAPPDATA%\Shiqi`. Failures preserve existing state; unreadable local data disables saving.
- Only calendar GET requests are made. There is no submission, exam, grading or course-content scraping code. Redirects across origins/ports or to HTTP are blocked; normal HTTPS validation stays enabled. Requests enforce a timeout, 5 MB limit and strict UTF-8.
- No hosted backend is needed. Windows APIs provide notifications without PowerShell or interpolating calendar content into commands. Closing hides to tray; quitting stops reminder delivery.
- Demo previews use synthetic data. Never commit real calendars, credentials, logs, caches or build outputs.

## Windows 实机检查 · Windows smoke test

1. 解压并运行，检查 100% / 150% / 200% DPI 和最小窗口下的中英文布局。 / Extract, run and check both languages at 100%/150%/200% DPI and minimum window size.
2. 用自己的共享链接连接，核对具体时间和仅日期任务，重启确认凭据保留。 / Connect your own feed, check timed/date-only items and restart to verify saved credentials.
3. 完成一个任务，再同步/导入，确认仍完成；恢复待办后重复检查。 / Complete a task, sync/reimport and verify completion persists; repeat after reopening it.
4. 测试通知，并添加一个 2–3 分钟后的手动任务；关闭窗口确认托盘提醒。 / Test notifications, add a manual task due in 2–3 minutes and close the window to test tray delivery.
5. 检查勿扰、睡眠恢复、退出后停止通知，以及启用/关闭登录启动。 / Check Do Not Disturb, sleep/resume, no notifications after quitting, and start-at-sign-in on/off.
6. 无法访问学校或链接失效时，确认旧任务保留。 / Verify unavailable campus access or an expired link keeps existing tasks.

MIT License。依赖许可见 [THIRD-PARTY-NOTICES.txt](THIRD-PARTY-NOTICES.txt)。界面图标由项目既有原创几何绘制脚本生成；没有新增学校标志或 Apple SF Symbols 素材。

MIT License. See third-party notices. Icons come from the existing original geometry generator; no university emblem or Apple SF Symbols artwork is added.
