# 拾期 · Shiqi — DDL Reminder

给龙大学子的免费开源 DDL 提醒工具，适配校园 Blackboard。提供 macOS 正式版和 Windows 预览版。

Free, open-source deadline reminders for LGU students using the campus Blackboard. Available for macOS, with a Windows preview.

**[中文说明](#zh-cn) · [English guide](#en)**

## 下载 · Downloads

| 平台 / Platform | 版本 / Version | 直接下载 / Direct download | 发布状态 / Release status |
| --- | --- | --- | --- |
| Mac · Apple Silicon（M 系列 / M-series），macOS 13+ | 1.2.0 | **[Mac ZIP][mac-zip]** | 正式版，未公证 / Stable, unnotarized |
| Windows · Intel / AMD（x64） | 1.2.0 Preview 1 | **[Windows x64 ZIP][windows-x64-zip]** | 预览版，未签名 / Preview, unsigned |
| Windows · ARM64 | 1.2.0 Preview 1 | **[Windows ARM64 ZIP][windows-arm64-zip]** | 预览版，未签名 / Preview, unsigned |

安装说明：**[Mac 中文](#mac-install-zh) · [Windows 中文](#windows-install-zh) · [Mac English](#mac-install-en) · [Windows English](#windows-install-en)**。

发布页 / Release pages：**[Mac 1.2.0][mac-release] · [Windows Preview 1][windows-release]**。安装说明文件 / Installation guides：**[Mac（中英双语 / bilingual）][mac-install-guide] · [Windows（中英双语 / bilingual）][windows-install-guide]**。SHA-256：**[Mac][mac-checksums] · [Windows][windows-checksums]**。

Mac 包仅适用于 Apple Silicon，不包含 Intel Mac 版本。Windows 建议使用 Windows 11 24H2 或以上；Windows 10 22H2 x64 为兼容目标。**Windows 预览版仍需真实 Windows 电脑验证，尤其是通知、托盘、凭据保存、登录启动和休眠恢复。**

The Mac package is for Apple Silicon only; no Intel Mac binary is provided. Windows 11 24H2 or later is recommended; Windows 10 22H2 x64 is a compatibility target. **The Windows preview still needs testing on a real Windows computer, especially notifications, tray behavior, saved credentials, sign-in startup, and sleep/resume.**

普通用户请下载上表的应用 ZIP；GitHub 自动生成的 **Source code (zip / tar.gz)** 是源码，不含可直接运行的软件。两个平台都无需自行安装开发环境。

For a ready-to-run app, use the ZIP links above. GitHub's automatic **Source code (zip / tar.gz)** downloads contain source code, not compiled apps. Neither app package requires a development environment.

iOS 开发版的环境安装、运行和使用说明见 **[iOS 中英双语指南](iOS/README.md)**。手机端与 macOS 版独立，共用核心逻辑。验证状态见该指南。

For the iOS development version, see the **[bilingual iOS guide](iOS/README.md)** for setup, usage, and validation status. Mobile and Mac versions share core logic and keep separate app data.

Windows 预览版的使用、源码构建和验证范围见 **[Windows 中英双语指南][windows-source-guide]**。Windows 源码目前位于 `v1.2.0-windows-preview.1` 标签；构建时请检出该标签，不能仅下载 `main`。Windows 使用独立的 C# / Avalonia 工程和数据目录。

For Windows usage, source builds, and validation limits, see the **[bilingual Windows guide][windows-source-guide]**. Windows source is currently on the `v1.2.0-windows-preview.1` tag; check out that tag to build it rather than downloading only `main`. It uses a separate C# / Avalonia project and data directory.

SwiftUI（macOS / iOS）· Avalonia（Windows）· 中文 / English · MIT

<a id="zh-cn"></a>

## 中文说明

拾期通过 [bb.cuhk.edu.cn](https://bb.cuhk.edu.cn) 的官方日历订阅链接读取日历事项，显示准确的截止日期、时间与倒计时，并通过系统通知提醒。运行时无需 Python、Node.js 或后台服务器。

这是独立开发的免费开源项目，非学校或 Blackboard 官方产品，未经校方背书。「龙大」是学生给位于龙岗的港中深起的非正式昵称「龙岗大学」，英文简称 **LGU（Longgang University）**；不是学校的正式名称。

下方功能、系统要求与详细使用说明以 **macOS 版**为主；Windows 用户请先阅读 **[Windows 安装与首次使用](#windows-install-zh)**，平台差异见 [Windows 指南][windows-source-guide]。

### 功能

- **自动同步**：默认每 15 分钟更新，也可手动同步；同步失败时保留已有数据，显示错误和上次同步时间。
- **清晰的日期与时间**：按日期分组，详情显示星期、时分秒和时区；支持即将截止、未来 7 天、已逾期、已完成及搜索。
- **系统提醒**：默认提前 24 小时、3 小时、30 分钟，以及到期时提醒，可在设置中调整。
- **macOS 提醒事项（1.2.0 起）**：可选同步到「拾期 · DDL」列表，保留准确的日期、时间、课程与备注；完成和恢复待办状态双向同步，重复导入不会重复创建已识别的任务。
- **补充遗漏的 DDL**：支持手动添加和 `.ics` 文件导入；文件导入后不会自动更新。
- **本地完成状态**：完成后取消相关未来提醒；再次同步、重导入或已识别事项改期时保留完成状态，只有手动恢复待办才会取消完成。来源删除或取消的事项会在同步后移除。
- **中英双语与紫金主题**：语言即时切换并自动保存，界面与后续通知使用所选语言；课程标题与备注保留来源原文。

### 系统要求

| 项目 | 要求 |
| --- | --- |
| 系统 | macOS 13 Ventura 或更新版本 |
| 当前预编译包 | Apple Silicon（`arm64`）；不是通用二进制包 |
| Intel Mac | 可尝试在 Intel Mac 上从源码构建；尚未进行 Intel 实机验证 |
| 在线同步 | 可访问学校 Blackboard，并取得个人日历共享链接 |
| 源码构建 | Apple Command Line Tools 或 Xcode，Swift 5.9+ 与匹配的 macOS SDK |

默认显示 **深圳 (UTC+8)**，底层仍使用标准的 `Asia/Shanghai` 时区。香港同为 UTC+8。城市名称和语言的变化不会改变已经保存的实际截止时刻。

<a id="mac-install-zh"></a>

### Mac 安装

#### 方式一：使用发布包

1. 下载 **[Mac 1.2.0 ZIP][mac-zip]**（Apple Silicon，macOS 13+），双击解压。
2. 将 `拾期.app` 拖入「应用程序」文件夹。
3. 从「应用程序」打开拾期，按下方说明连接 Blackboard 和启用通知。

**当前 Mac 1.2.0 使用 ad-hoc 签名，没有 Developer ID 签名，也未经过 Apple 公证。** 首次打开可能显示「Apple 无法验证是否包含恶意软件」：

1. 在提示中点击「完成」，保留应用。
2. 打开「系统设置」→「隐私与安全性」，向下找到「安全性」。
3. 在拾期被阻止的提示旁点击 **「仍要打开」**，按系统提示验证身份，再确认「打开」。

仅在确认下载来自本项目且信任该文件时操作；可用 `shasum -a 256` 检查 ZIP，与 [Mac SHA-256 文件][mac-checksums]核对。单位管理的电脑可能不提供放行选项，不要关闭系统级安全保护。参见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。

更新前先退出拾期，再用新版替换「应用程序」中的旧应用；个人任务和设置保存在独立数据目录。完整说明见 [Mac 安装指南][mac-install-guide]。

#### 方式二：从源码构建

1. 如果尚未安装 Apple Command Line Tools，在终端执行以下命令，并完成系统安装流程。已有可用 Xcode 工具链时无需重复安装。[Apple 安装说明](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/)

   ```sh
   xcode-select --install
   ```

2. 从 GitHub 下载或克隆本项目，在终端进入含 `Package.swift` 的项目根目录。
3. 执行测试和构建：

   ```sh
   bash scripts/test.sh
   bash scripts/build.sh
   ```

4. 构建成功后生成 `dist/拾期.app` 和 `dist/拾期.zip`。将应用拖入「应用程序」，或在项目目录直接打开：

   ```sh
   open "dist/拾期.app"
   ```

构建脚本直接调用 `swiftc`，无需下载第三方依赖，并按当前 Mac 的 CPU 架构生成应用。请运行打包后的 `.app`，以便系统通知识别应用身份。

安装完整 Xcode 后，macOS 脚本仍优先使用可用的 Command Line Tools；iOS 脚本独立选择 Xcode。需要改用其他工具链时，可显式设置 `DEVELOPER_DIR`。

<a id="windows-install-zh"></a>

### Windows 安装与首次使用（预览版）

1. 根据电脑架构下载 **[Windows x64 ZIP][windows-x64-zip]**（Intel / AMD）或 **[Windows ARM64 ZIP][windows-arm64-zip]**（ARM 电脑）。可在「设置」→「系统」→「系统信息」（或「关于」）查看「系统类型」。
2. 右键 ZIP，选择「全部解压」，将完整的 `Shiqi` 文件夹放到固定的用户目录。不要在 ZIP 中直接运行。
3. 打开文件夹中的 **`Shiqi.exe`**。保留旁边的 DLL 和 `Assets`，不要只移动 EXE；可为 EXE 创建快捷方式。
4. 安装包已包含 .NET 运行时，无需另装 .NET、Python、Node.js 或以管理员身份运行。

**Windows 包未进行代码签名。** 若出现未知发布者或 SmartScreen 提示，先确认来源并与 [Windows SHA-256 文件][windows-checksums]核对；PowerShell 可用 `Get-FileHash .\下载的文件.zip -Algorithm SHA256`。仅在信任文件且系统提供选项时，选择 **「更多信息」→「仍要运行」**。组织管理的电脑可能不允许放行；不要关闭 Defender 或系统级安全保护。

连接并检查提醒：

1. 点击「管理连接」→「打开 Blackboard」，在自己的浏览器中登录，进入全局 **Calendar**，选择 **Get External Calendar Link / Share Calendar**，复制完整个人日历共享链接。
2. 回到拾期粘贴链接，点击「连接并同步」。核对任务日期、具体时间和 **深圳 (UTC+8)**；不要公开共享链接中的个人访问令牌。
3. 打开「设置」，选择中文或英文、提醒时点等，再点击「保存设置」。用「发送测试通知」检查通知；Windows 通知设置和勿扰模式可能影响显示。

**Windows 提醒依赖程序保持运行。** 关闭窗口会保留系统托盘进程；点击托盘图标重新打开，右键可退出。退出、关机或睡眠期间无法准时提醒，恢复后仅补发最近 5 分钟内的提醒。「登录 Windows 时启动拾期」默认关闭。

Windows 不支持 Apple「提醒事项」同步；Mac 与 Windows 的本地任务和完成状态也不会自动跨设备同步。更新前从托盘退出，替换完整程序文件夹；数据保存在 `%LOCALAPPDATA%\Shiqi`。更多使用、卸载和实机测试步骤见 [Windows 安装指南][windows-install-guide]与 [Windows 源码指南][windows-source-guide]。

### 首次使用：连接 Blackboard（macOS）

1. 在拾期点击「连接 Blackboard」。可以在应用内登录，也可以点击「在默认浏览器打开 Blackboard」。
2. 使用自己的学校账号登录，打开**全局「日历 / Calendar」**。
3. 根据 Blackboard 界面版本，点击 **Get External Calendar Link**；或打开日历设置，在更多选项中选择 **Share Calendar**。[Blackboard 官方说明](https://help.anthology.com/blackboard/student/en/original-course-view/stay-in-the-loop/calendar.html)
4. 复制生成的**完整个人日历链接**。网站首页或 `/webapps/calendar/calendarFeed/` 这样的路径前缀不能代替完整共享链接。
5. 把链接粘贴到拾期，点击「连接并同步」。应用内登录窗口会尝试检测页面已经展示的订阅链接；未检测到时可手动粘贴。
6. 同步成功后，检查界面中的日期、时间、连接状态与上次同步时间。

**共享链接可能含个人访问令牌，可访问你的日历。不要放进公开 Issue、截图、日志或 Git 仓库。**

### 开启与调整提醒

1. 点击「开启提醒」，在 macOS 提示中允许通知。
2. 打开「提醒与设置」，点击「允许通知 / 发送测试通知」。测试通知会在约 5 秒后触发。
3. 在设置中选择提醒时点，也可调整自动同步间隔、时区及「登录 Mac 时启动拾期」。

只有日期、没有具体时间的事项会标注「时间待确认」，在前一天和当天 **09:00** 提醒，不会自动猜测截止时间为 23:59。导入时已经过去的提前提醒会跳过，仅安排剩余的未来提醒。

关闭主窗口后，拾期会继续在菜单栏运行和同步。选择「退出」会停止同步；已经排程的通知仍由 macOS 管理。电脑关机时无法提醒，睡眠、专注模式与系统通知设置也可能延迟展示。运行期间每分钟维护最多 60 条近期通知，优先安排较近的提醒。

### 同步到 macOS 提醒事项

此功能从 **1.2.0** 开始提供，默认关闭；1.1.2 安装包仍只支持拾期自身的系统通知。

1. 打开「提醒与设置」（`⌘,`），开启「同步 DDL 到提醒事项」。
2. 在 macOS 提示中允许拾期访问提醒事项。若此前拒绝，可到「系统设置」→「隐私与安全性」→「提醒事项」开启权限，再重试。
3. 打开系统「提醒事项」，找到 **「拾期 · DDL」** 专用列表。应用中的待办、逾期及已完成事项都会同步；已完成事项可在列表的「显示已完成」中查看。
4. 拾期运行时每分钟检查，也会在 DDL 导入、改期、编辑和完成后同步；可点击「立即同步到提醒事项」手动触发。

- 标题、课程、备注和截止时间以拾期为准；在任一应用完成或恢复待办会同步到另一边。双方都修改完成状态时，拾期自上次成功同步后的本地修改优先。完成状态不会提交作业或修改 Blackboard。
- 具体时间按所选时区导出，保留实际截止时刻。仅日期事项不设置虚构的午夜或 23:59 截止时间。
- 提醒事项在具体截止时间设置提醒；提前提醒仍由拾期的「发送系统通知」控制，同时启用可能出现重复通知。仅日期事项继续由拾期按原有 09:00 规则提醒。
- 删除 DDL、来源取消事项或断开 Blackboard 后，相应的托管提醒事项会在下次成功同步时移除。在提醒事项里直接删除但在拾期仍存在的任务，会在下次同步重新创建。拾期不会操作其他列表或专用列表里你手动添加的事项。
- 关闭同步会保留已导出的事项；退出拾期后停止双向同步。列表使用系统默认提醒事项账户，如果该账户是 iCloud，导出的课程内容会通过你的 iCloud 同步到其他设备。

### 日常操作

| 操作 | 使用方法 |
| --- | --- |
| 切换语言 | 「提醒与设置」→「语言 / Language」→ 简体中文或 English；即时生效并保存 |
| 添加截止日期 | 点击「添加 DDL」；填写任务、课程、日期、时间和备注 |
| 查看详情 | 点击任务行，查看完整时间与备注 |
| 标记完成 | 点击任务左侧圆圈，或在详情中标记完成；开启提醒事项同步后，状态也会同步到该列表 |
| 导入日历文件 | 点击主窗口右上角导入图标，选择小于 5 MB 的 UTF-8 `.ics` 文件 |
| 手动同步 | 点击「立即同步」，或使用菜单栏的同步按钮 |
| 管理订阅 | 点击「管理连接」；更换链接或断开连接 |

断开 Blackboard 会移除订阅链接、同步的 Blackboard 事项和相应提醒；手动添加和文件导入的事项会保留。

| 快捷键 | 功能 |
| --- | --- |
| `⌘N` | 添加截止日期 |
| `⌘R` | 同步 Blackboard |
| `⌘,` | 打开提醒设置 |

### 数据范围与隐私

- 拾期读取 Blackboard 日历订阅中的全部事项，可能包括作业、考试、上课时间与个人事件。仅写在公告、PDF、邮件或课程说明中的 DDL，需要手动补充。
- 订阅链接保存在 **macOS 钥匙串**。软件不读取或保存学校密码；应用内登录使用临时 WebKit 会话，不持久化登录 cookie。
- 任务、完成状态和设置保存在 `~/Library/Application Support/DDLReminder/deadlines.json`；上一次保存的内容备份为同目录下的 `deadlines.backup.json`。备份课程数据时也应保护这些文件。
- 应用直接向日历服务器发起请求，不使用自建云端服务。HTTPS 重定向仅允许同一主机。
- 提醒事项同步默认关闭，开启时才申请访问权限。仅管理「拾期 · DDL」列表中由拾期创建的事项，不导出日历订阅链接或学校密码。使用 iCloud 提醒事项账户时，导出的任务数据受你的 Apple 账户同步设置管理。

支持 UTC、IANA 时区、无时区日期、仅日期事项、VEVENT/VTODO、折行与转义、取消事件、每日/每周重复、EXDATE、RDATE 和单次重复事件改期。不支持的复杂重复规则或自定义 VTIMEZONE 会明确提示；请核对提示并手动补充，不保证支持所有 iCalendar 扩展。

### 常见问题

| 问题 | 处理方法 |
| --- | --- |
| 连接失败或 HTTP 401/403 | 确认使用完整的日历共享链接；必要时重新生成。检查校园网/VPN 是否可以访问 Blackboard。 |
| 应用内登录页面无法加载 | 在默认浏览器登录、获取共享链接，再粘贴到拾期。 |
| 没有看到某门课的作业 | 先核对 Blackboard 全局日历是否包含它；只在公告或附件里写出的 DDL 需手动添加。 |
| 没有收到通知 | 检查「系统设置」→「通知」→「拾期」、应用内「发送系统通知」与提醒时点，调整专注模式，并发送测试通知。 |
| 提醒事项没有同步 | 使用 1.2.0 或更高版本；检查同步开关和提醒事项访问权限，先在系统提醒事项中设置可用的本机或 iCloud 账户，再点「立即同步到提醒事项」。 |
| 重新构建后出现钥匙串提示 | 确认运行的是自己构建或可信来源的拾期，在 macOS 系统提示中批准访问；不要把 Mac 密码发给项目维护者。 |
| 构建提示 SDK 与编译器不匹配 | 使用匹配的 Apple 工具链与 SDK，或通过下方的 `DDL_SDK_PATH` 显式选择。 |

### 开发与贡献

```text
Sources/DeadlineCore/       日历解析、数据模型、合并、提醒计划与语言
Sources/DDLReminder/        SwiftUI 界面、同步、钥匙串、通知和本地存储
Tests/DeadlineCoreTests/    核心逻辑回归测试
Resources/                 Info.plist、品牌素材与示例日历
scripts/                   构建、测试、图标生成与网络诊断
```

测试使用 XCTest；仅有 Command Line Tools、无法使用 XCTest 时，脚本使用仓库内的轻量测试运行器。当前 32 项测试覆盖日期转换、夏令时、全天事项、重复例外、提醒计划、同步合并、UID 变化后的完成状态、跨来源重导入、旧版数据迁移、提醒事项同步与语言设置。

1.1.1 修复了部分日历每次导出生成新 UID，导致已完成事项变回待办的问题。优先按日历身份匹配；UID 改变时，仅在标题、课程、实际截止时刻和时间类型均一致且双方唯一时匹配，避免误把其他任务标记完成。文件导入与在线同步共享这套规则；重复事件的各次事项分别保存完成状态。

也提供标准 Swift Package；工具链匹配时可执行 `swift build` / `swift test`。完整可运行应用仍需通过 `bash scripts/build.sh` 打包资源和应用身份。

在项目目录可使用不连接账号、不保存示例数据、不发送通知的演示模式：

```sh
open -n "dist/拾期.app" --args --demo
```

`Resources/sample.ics` 是合成示例，不包含真实个人日历。示例日期可能已经过去，导入后请同时查看「已逾期」。真实账号端到端同步需自行使用个人共享链接验证。

如需手动指定 SDK，将示例路径替换为自己已安装且与编译器兼容的 SDK：

```sh
DDL_SDK_PATH="/path/to/compatible/MacOSX.sdk" bash scripts/test.sh
DDL_SDK_PATH="/path/to/compatible/MacOSX.sdk" bash scripts/build.sh
```

欢迎通过 Issue 或 Pull Request 提交改进。报告问题时请提供 macOS 版本、Mac 架构、复现步骤及脱敏的错误代码，使用合成日历复现解析问题。

#### 网络兼容配置

2026-10-09 在本地使用 Apple `nscurl --ats-diagnostics` 检查时，`bb.cuhk.edu.cn` 需要放宽前向保密要求才能连接。因此 `Resources/Info.plist` 仅对该确切域名设置 `NSExceptionRequiresForwardSecrecy = false`，最低 TLS 1.2、证书验证与禁止 HTTP 的限制仍保留，不应用于子域名。此设置放宽 PFS 及相关密钥长度检查；非 PFS 会话在服务器私钥未来泄露时可能暴露已记录流量。服务器配置升级后应重新验证并移除例外。[Apple 配置说明](https://developer.apple.com/documentation/bundleresources/information-property-list/nsexceptionrequiresforwardsecrecy)

#### GitHub 发布

源码、测试、脚本和文档提交到仓库；`dist/`、构建缓存、日志和个人日历数据由 `.gitignore` 排除。不要把整个工作目录打包后当作源码发布。未公证的候选安装包只放在草稿中；完成下面的签名、公证和验证流程后，再公开正式下载。

#### 维护者：Developer ID 签名与 Apple 公证

需要已加入 [Apple Developer Program](https://developer.apple.com/programs/enroll/) 的账户。免费 Personal Team 不能签署面向公众分发的 Developer ID 应用。账户持有人可在 Xcode 的 Settings → Accounts → Manage Certificates 创建 **Developer ID Application** 证书，或依照 [Apple 证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) 从开发者网站创建并导入。证书及其私钥必须同时在本机钥匙串中。ZIP 分发无需 Developer ID Installer 证书。

1. 在终端确认可用身份：

   ```sh
   security find-identity -v -p codesigning
   ```

2. 创建 Apple 账户的 App 专用密码，然后在自己的终端交互式保存公证凭据。按提示输入 Apple 账户、Team ID 和 App 专用密码；不要把密码写入仓库、命令行参数或聊天。

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcrun notarytool store-credentials shiqi-notary
   ```

3. 提交待发布源码，确认工作区干净后运行：

   ```sh
   DDL_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
   DDL_NOTARY_PROFILE='shiqi-notary' \
     bash scripts/release-macos.sh
   ```

脚本依次执行核心测试、Developer ID 签名、Hardened Runtime 与安全时间戳、公证提交、等待 **Accepted**、向应用附加公证票据、Gatekeeper 验证、重新打包与解压验证。任一步失败都会停止；不会降级为 ad-hoc 正式发布包。输出位于 `dist/releases/<版本>/`，包含 `Shiqi-<版本>-macOS-<架构>.zip`、`SHA256SUMS.txt` 和可追溯源码提交的 `BUILD-INFO.txt`。只将这些成功验证的文件上传到相同版本的 GitHub Release。

Hardened Runtime 的 EventKit 资源权限保留可选提醒事项同步；没有打开 App Sandbox，也没有放宽网络证书验证。初次启动时用户仍可能看到正常的互联网下载确认，以及通知、钥匙串和提醒事项权限提示。建议在另一台 Mac 上再次验证下载、解压、拖入「应用程序」及首次打开。公证日志位于忽略提交的 `dist/macos-notary.*`。[Apple 公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

### 许可证与品牌素材

项目代码、原创图标与文档采用 [MIT License](LICENSE)。1.1.2 已移除学校校徽、校名标志和相关图片，使用拾期自身的日历图标。命名、素材和独立项目说明见 [Resources/Branding.md](Resources/Branding.md)。

---

<a id="en"></a>

## English guide

Shiqi reads calendar events from the official subscription feed on [bb.cuhk.edu.cn](https://bb.cuhk.edu.cn), displays exact deadlines and countdowns, and sends system notifications. No Python, Node.js, or background server is required at runtime.

This is an independently developed, free and open-source project, not an official or university-endorsed product or an official Blackboard product. Students call CUHK-Shenzhen “龙大”, short for the informal nickname “龙岗大学” (**Longgang University, LGU**), because the campus is in Longgang. This is not the university's official name.

The features, requirements, and detailed usage below primarily describe the **macOS app**. Windows users should start with **[Windows installation and first use](#windows-install-en)**; see the [Windows guide][windows-source-guide] for platform differences.

### Features

- **Automatic sync:** updates every 15 minutes by default, with manual refresh available. Failed syncs keep existing data and show the error and last successful sync time.
- **Clear dates and times:** events grouped by date; details include the weekday, seconds, and time zone. Filter upcoming, next 7 days, overdue, or completed items, and search your tasks.
- **System reminders:** alerts 24 hours, 3 hours, and 30 minutes before a deadline, and at the deadline, with configurable reminder times.
- **macOS Reminders (1.2.0+):** optionally sync to the dedicated 拾期 · DDL list with exact dates and times, courses, and notes. Completion and reopening sync both ways; reimporting recognized tasks does not create duplicates.
- **Add missing deadlines:** create tasks manually or import `.ics` files. File imports do not update automatically.
- **Local completion status:** completing a task removes its future reminders. Syncs, reimports, and reschedules of recognized tasks preserve completion until you mark them incomplete yourself. Deleted or cancelled source items are removed on sync.
- **Chinese/English and purple/gold styling:** language changes apply immediately and persist, including subsequent notifications. Original course titles and notes are preserved.

### Requirements

| Item | Requirement |
| --- | --- |
| Operating system | macOS 13 Ventura or later |
| Current prebuilt app | Apple Silicon (`arm64`); not a universal binary |
| Intel Macs | Build from source on an Intel Mac; physical Intel hardware has not been tested |
| Online sync | Access to the university's Blackboard and your personal calendar sharing link |
| Source build | Apple Command Line Tools or Xcode, Swift 5.9+, and a matching macOS SDK |

The default display zone is **Shenzhen (UTC+8)**, using the standard `Asia/Shanghai` identifier internally. Hong Kong also uses UTC+8. Changing the city label or interface language does not shift stored deadline instants.

<a id="mac-install-en"></a>

### Mac installation

#### Option 1: A release package

1. Download the **[Mac 1.2.0 ZIP][mac-zip]** (Apple Silicon, macOS 13+) and double-click to extract it.
2. Drag `拾期.app` into **Applications**.
3. Open Shiqi from Applications, then connect Blackboard and enable notifications as described below.

**The current Mac 1.2.0 package is ad-hoc signed, without Developer ID signing or Apple notarization.** If macOS says Apple cannot verify whether it contains malware on first launch:

1. Click **Done** and keep the app.
2. Open **System Settings → Privacy & Security**, then scroll to **Security**.
3. Click **Open Anyway** beside the blocked Shiqi app, authenticate if prompted, and confirm **Open**.

Proceed only if you trust the file and downloaded it from this project. You can check the ZIP with `shasum -a 256` against the [Mac SHA-256 file][mac-checksums]. Managed Macs may not offer an override; do not disable system-wide security protections. See [Apple's instructions](https://support.apple.com/en-us/102445).

To update, quit Shiqi before replacing the app in Applications. Tasks and preferences are stored separately. See the [Mac installation guide][mac-install-guide] for the full instructions.

#### Option 2: Build from source

1. If you do not already have Apple Command Line Tools or a working Xcode toolchain, run the following command in Terminal and complete the system installation. [Apple installation guide](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/)

   ```sh
   xcode-select --install
   ```

2. Download or clone this project from GitHub. In Terminal, enter the project root containing `Package.swift`.
3. Run the tests and build:

   ```sh
   bash scripts/test.sh
   bash scripts/build.sh
   ```

4. The build produces `dist/拾期.app` and `dist/拾期.zip`. Move the app to Applications, or open it directly from the project root:

   ```sh
   open "dist/拾期.app"
   ```

The script invokes `swiftc` directly, downloads no third-party dependencies, and builds for the host Mac's architecture. Run the packaged `.app` so macOS notifications can identify the application.

After installing full Xcode, Mac scripts still prefer available Command Line Tools; iOS scripts select Xcode separately. Set `DEVELOPER_DIR` explicitly to choose another toolchain.

<a id="windows-install-en"></a>

### Windows installation and first use (preview)

1. Download the **[Windows x64 ZIP][windows-x64-zip]** for Intel/AMD PCs, or the **[Windows ARM64 ZIP][windows-arm64-zip]** for ARM PCs. Check **System type** in **Settings → System → About** if unsure.
2. Right-click the ZIP and choose **Extract All**. Keep the complete `Shiqi` folder in a permanent user-owned location. Do not run it from inside the ZIP.
3. Open **`Shiqi.exe`** inside the folder. Keep the DLLs and `Assets` alongside it; do not move just the EXE. You can create a shortcut to the EXE.
4. The .NET runtime is included. No separate .NET, Python, Node.js, or administrator access is needed.

**The Windows packages are not code-signed.** If an unknown-publisher or SmartScreen warning appears, verify the source and the [Windows SHA-256 file][windows-checksums] first; in PowerShell, use `Get-FileHash .\downloaded-file.zip -Algorithm SHA256`. Only if you trust the file and Windows offers the option, choose **More info → Run anyway**. Managed computers may disallow this; do not disable Defender or system-wide security protections.

Connect and check reminders:

1. Choose **Connection → Open Blackboard**, sign in using your own browser, open the global **Calendar**, and choose **Get External Calendar Link / Share Calendar**. Copy the complete personal calendar sharing URL.
2. Paste it into Shiqi and choose **Connect & sync**. Check task dates, exact times, and **Shenzhen (UTC+8)**. Keep the private access token in the sharing URL out of public posts.
3. Open **Settings**, choose Chinese or English and your reminder preferences, then click **Save settings**. Use **Send test notification** to check alerts; Windows notification settings and Do Not Disturb can suppress them.

**Windows reminders require the app to keep running.** Closing the window keeps it in the system tray; click the tray icon to reopen, or right-click to quit. Quit, shutdown, or sleep can prevent timely alerts; on resume, only reminders due within the last five minutes are caught up. **Start at Windows sign-in** is off by default.

Apple Reminders sync is unavailable on Windows. Local tasks and completion states do not automatically sync between Mac and Windows. To update, quit from the tray before replacing the complete app folder; data stays in `%LOCALAPPDATA%\Shiqi`. See the [Windows installation guide][windows-install-guide] and [Windows source guide][windows-source-guide] for more usage, removal, and real-device testing steps.

### First use: Connect Blackboard (macOS)

1. Click **Connect Blackboard**. Sign in inside the app, or choose **Open Blackboard in your browser**.
2. Sign in with your university account and open the **global Calendar**.
3. Depending on the Blackboard interface, choose **Get External Calendar Link**, or open Calendar Settings and choose **Share Calendar** from the additional options. [Official Blackboard instructions](https://help.anthology.com/blackboard/student/en/original-course-view/stay-in-the-loop/calendar.html)
4. Copy the **complete personal calendar link**. The homepage or a path prefix such as `/webapps/calendar/calendarFeed/` is not a complete sharing link.
5. Paste it into Shiqi and click **Connect & sync**. The embedded sign-in window attempts to detect a subscription link already displayed on the page; you can paste it manually if detection fails.
6. After sync, check the dates, times, connection status, and last sync time.

**The sharing link may contain a private access token that grants access to your calendar. Keep it out of public issues, screenshots, logs, and Git repositories.**

### Enable and configure reminders

1. Click **Enable reminders** and allow notifications in the macOS prompt.
2. Open **Reminders & settings** and click **Allow / test notifications**. The test notification triggers after approximately 5 seconds.
3. Select reminder times in settings. You can also change the sync interval, time zone, and **Launch Shiqi at login** preference.

Date-only items are marked **Time to confirm** and receive reminders at **09:00** on the previous day and the due date. Shiqi does not assume a deadline time of 23:59. Reminder times that have already passed at import are skipped; remaining future reminders are scheduled.

Closing the main window keeps Shiqi running and syncing in the menu bar. **Quit** stops sync; macOS still manages notifications already scheduled. Alerts cannot appear while the Mac is shut down, and sleep, Focus, or notification settings may delay them. While running, Shiqi maintains up to 60 upcoming notifications each minute, prioritizing the nearest alerts.

### Sync to macOS Reminders

Available from **1.2.0**, off by default. The 1.1.2 package supports only Shiqi's own system notifications.

1. Open **Reminders & settings** (`⌘,`) and enable **Sync deadlines to Reminders**.
2. Allow Reminders access in the macOS prompt. If previously denied, enable access in **System Settings → Privacy & Security → Reminders**, then retry.
3. Open Apple's **Reminders** app and find the dedicated **拾期 · DDL** list. Pending, overdue, and completed tasks are synced; use **Show Completed** to view completed tasks.
4. Shiqi checks every minute while running and syncs after importing, rescheduling, editing, or completing deadlines. **Sync to Reminders now** triggers a manual check.

- Titles, courses, notes, and deadlines come from Shiqi. Completing or reopening in either app syncs to the other. If both change completion, local Shiqi changes since the last successful sync take precedence. Completion never submits work or changes Blackboard.
- Timed items retain the actual deadline instant in the selected zone. Date-only items have no invented midnight or 23:59 deadline.
- Reminders supplies an alert at the exact due time. Advance alerts remain controlled by Shiqi's **Send system notifications** setting; enabling both may duplicate alerts. Date-only items keep Shiqi's existing 09:00 notification rule.
- Removing a deadline, a source cancellation, or disconnecting Blackboard removes the corresponding managed reminder at the next successful sync. Deleting an exported reminder while keeping its deadline in Shiqi recreates it on the next sync. Other lists and tasks you manually add to the dedicated list are unaffected.
- Turning sync off keeps exported tasks. Quitting Shiqi stops two-way sync. The list uses your default Reminders account; an iCloud account syncs exported course content to your other devices through your Apple account.

### Everyday use

| Action | How |
| --- | --- |
| Change language | **Reminders & settings → 语言 / Language → 简体中文 / English**; applies immediately and persists |
| Add a deadline | Click **Add deadline**; enter the task, course, date, time, and notes |
| View details | Click a task row to see its full time and notes |
| Mark complete | Click the circle beside a task or mark it complete in details; when Reminders sync is enabled, completion also syncs to that list |
| Import a calendar | Use the import icon at the top right; choose a UTF-8 `.ics` file smaller than 5 MB |
| Refresh manually | Click **Sync now** or the menu bar's sync button |
| Manage a subscription | Click **Manage connection** to replace the link or disconnect |

Disconnecting removes the subscription, synced Blackboard events, and associated reminders. Manual tasks and file-imported events are kept.

| Shortcut | Action |
| --- | --- |
| `⌘N` | Add a deadline |
| `⌘R` | Sync Blackboard |
| `⌘,` | Open reminder settings |

### Coverage and privacy

- Shiqi imports all events in the Blackboard calendar feed, which may include assignments, exams, classes, and personal events. Deadlines mentioned only in announcements, PDFs, emails, or course documents must be added manually.
- The subscription link is stored in **macOS Keychain**. Shiqi does not read or store your university password. Embedded sign-in uses a temporary WebKit session without persistent login cookies.
- Tasks, completion status, and preferences are stored in `~/Library/Application Support/DDLReminder/deadlines.json`. The previous saved version is kept as `deadlines.backup.json` in the same directory. Treat these files as private when backing up course data.
- The app requests the calendar directly from its server, without a project-operated cloud service. HTTPS redirects are allowed only to the same host.
- Reminders sync is off by default and requests access only when enabled. It manages only Shiqi-created tasks in the 拾期 · DDL list and never exports the subscription link or your university password. An iCloud Reminders account syncs exported task data according to your Apple account settings.

The parser supports UTC, IANA zones, floating times, date-only events, VEVENT/VTODO, line folding and escaping, cancellations, daily/weekly recurrence, EXDATE, RDATE, and individual recurrence overrides. Unsupported complex recurrence rules or custom VTIMEZONE definitions produce warnings. Review those warnings and add missing items manually; full support for every iCalendar extension is not claimed.

### Troubleshooting

| Problem | What to check |
| --- | --- |
| Connection fails or returns HTTP 401/403 | Use the complete calendar sharing link, regenerate it if necessary, and check campus network/VPN access. |
| Embedded sign-in fails to load | Obtain the sharing link in your default browser and paste it into Shiqi. |
| An assignment is missing | Check whether it appears in Blackboard's global Calendar. Add deadlines from announcements or attachments manually. |
| Notifications do not appear | Check **System Settings → Notifications → 拾期**, **Send system notifications**, and the selected reminder times. Review Focus settings and send a test notification. |
| Reminders do not sync | Use version 1.2.0 or later. Check the sync toggle and Reminders access, set up a local or iCloud Reminders account, then click **Sync to Reminders now**. |
| A Keychain prompt appears after rebuilding | Verify that you are running your own build or a trusted Shiqi build, then approve access in the macOS prompt. Never send your Mac password to maintainers. |
| Compiler and SDK versions do not match | Use a matching Apple toolchain and SDK, or choose an SDK explicitly with `DDL_SDK_PATH` below. |

### Development and contributions

```text
Sources/DeadlineCore/       Parsing, models, merging, reminder planning, languages
Sources/DDLReminder/        SwiftUI, sync, Keychain, notifications, local storage
Tests/DeadlineCoreTests/    Core regression tests
Resources/                 Info.plist, branding assets, sample calendar
scripts/                   Build, tests, icon generation, network diagnostics
```

Tests use XCTest. When only Command Line Tools are available and XCTest is missing, the script uses the repository's lightweight test runner. The current 32 cases cover date conversion, daylight saving, date-only events, recurrence exceptions, reminder planning, sync merging, completion with changing UIDs, cross-source reimports, legacy data migration, Reminders sync, and language settings.

Version 1.1.1 fixes completed items becoming pending when a calendar generates new UIDs on each export. Calendar identity matches take priority. When a UID changes, matching requires an identical title, course, deadline instant, and time kind that uniquely identify an item in both sets. This avoids completing a different task by mistake. File imports and subscription sync share these rules; recurring occurrences retain separate completion states.

A standard Swift Package is also provided: `swift build` / `swift test` work with a matching toolchain. Use `bash scripts/build.sh` to package resources and application identity into a complete app.

Run demo mode from the project root to preview synthetic tasks without connecting an account, saving sample data, or sending notifications:

```sh
open -n "dist/拾期.app" --args --demo
```

`Resources/sample.ics` is synthetic and contains no real personal calendar. Its dates may be in the past; check the **Overdue** filter after importing it. Real account sync must be verified with your own private sharing link.

To choose an SDK explicitly, replace the example path with an installed SDK compatible with your compiler:

```sh
DDL_SDK_PATH="/path/to/compatible/MacOSX.sdk" bash scripts/test.sh
DDL_SDK_PATH="/path/to/compatible/MacOSX.sdk" bash scripts/build.sh
```

Issues and pull requests are welcome. Include your macOS version, Mac architecture, reproduction steps, and redacted error codes. Use a synthetic calendar to demonstrate parser problems.

#### Network compatibility

A local Apple `nscurl --ats-diagnostics` check on 2026-10-09 found that `bb.cuhk.edu.cn` required relaxing the forward secrecy requirement. `Resources/Info.plist` therefore sets `NSExceptionRequiresForwardSecrecy = false` only for that exact domain, retaining TLS 1.2 minimum, certificate validation, and the HTTP prohibition, without including subdomains. This relaxes PFS and related key-length checks; recorded non-PFS traffic may be exposed if the server's private key is later compromised. Revalidate and remove the exception when the server configuration improves. [Apple configuration reference](https://developer.apple.com/documentation/bundleresources/information-property-list/nsexceptionrequiresforwardsecrecy)

#### Publishing on GitHub

Commit source, tests, scripts, and documentation. `.gitignore` excludes `dist/`, build caches, logs, and personal calendar data. Do not publish a ZIP of the entire working directory as source. Keep unnotarized candidate packages in a draft, and publish downloads after the signing, notarization, and verification process below succeeds.

#### Maintainers: Developer ID signing and Apple notarization

Use an account enrolled in the [Apple Developer Program](https://developer.apple.com/programs/enroll/). A free Personal Team cannot sign Developer ID apps for public distribution. The Account Holder can create a **Developer ID Application** certificate using Xcode Settings → Accounts → Manage Certificates, or follow [Apple's certificate instructions](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) to create and import one. Both the certificate and its private key must be in the local Keychain. ZIP distribution does not need a Developer ID Installer certificate.

1. List available signing identities:

   ```sh
   security find-identity -v -p codesigning
   ```

2. Create an app-specific password for the Apple account, then save notarization credentials interactively in your own terminal. Enter your Apple account, Team ID, and app-specific password at the prompts. Keep passwords out of source files, command-line arguments, and chat.

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcrun notarytool store-credentials shiqi-notary
   ```

3. Commit the release source, ensure the working tree is clean, and run:

   ```sh
   DDL_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
   DDL_NOTARY_PROFILE='shiqi-notary' \
     bash scripts/release-macos.sh
   ```

The script runs core tests, signs with Developer ID using Hardened Runtime and a secure timestamp, submits for notarization, waits for **Accepted**, staples the ticket to the app, checks Gatekeeper, repackages, and verifies the extracted archive. It stops on failure and never falls back to an ad-hoc public package. Successful output is in `dist/releases/<version>/`: `Shiqi-<version>-macOS-<architecture>.zip`, `SHA256SUMS.txt`, and `BUILD-INFO.txt` recording the exact source commit. Upload only these successfully verified files to the matching GitHub Release.

The Hardened Runtime EventKit resource entitlement preserves optional Reminders access. App Sandbox is not enabled and network certificate validation is not weakened. Users may still see the normal first-download confirmation and notification, Keychain, and Reminders permission prompts. Verify downloading, extracting, moving to Applications, and first launch on another Mac before distribution. Notarization logs stay in ignored `dist/macos-notary.*` directories. [Apple notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

### License and branding

Project code, original icons, and documentation are licensed under the [MIT License](LICENSE). Version 1.1.2 removes the university emblem, official wordmark, and related images, using Shiqi’s own calendar icon. See [Resources/Branding.md](Resources/Branding.md) for naming, assets, and independent-project disclosures.

[mac-release]: https://github.com/TimZ21/LGU_DDL_Reminder/releases/tag/v1.2.0
[mac-zip]: https://github.com/TimZ21/LGU_DDL_Reminder/releases/download/v1.2.0/Shiqi-1.2.0-macOS-arm64-unnotarized.zip
[mac-install-guide]: https://github.com/TimZ21/LGU_DDL_Reminder/releases/download/v1.2.0/INSTALL.txt
[mac-checksums]: https://github.com/TimZ21/LGU_DDL_Reminder/releases/download/v1.2.0/SHA256SUMS.txt
[windows-release]: https://github.com/TimZ21/LGU_DDL_Reminder/releases/tag/v1.2.0-windows-preview.1
[windows-x64-zip]: https://github.com/TimZ21/LGU_DDL_Reminder/releases/download/v1.2.0-windows-preview.1/Shiqi-1.2.0-windows-preview.1-win-x64-unsigned.zip
[windows-arm64-zip]: https://github.com/TimZ21/LGU_DDL_Reminder/releases/download/v1.2.0-windows-preview.1/Shiqi-1.2.0-windows-preview.1-win-arm64-unsigned.zip
[windows-install-guide]: https://github.com/TimZ21/LGU_DDL_Reminder/releases/download/v1.2.0-windows-preview.1/INSTALL-Windows-zh-en.txt
[windows-checksums]: https://github.com/TimZ21/LGU_DDL_Reminder/releases/download/v1.2.0-windows-preview.1/SHA256SUMS-Windows.txt
[windows-source-guide]: https://github.com/TimZ21/LGU_DDL_Reminder/blob/v1.2.0-windows-preview.1/windows/README.md
