# 拾期 · Shiqi — DDL Reminder

给龙大学子的免费开源软件：轻量原生 macOS 截止日期提醒工具，适配校园 Blackboard。

Free, open-source software for Longda students: a lightweight native macOS deadline reminder for the campus Blackboard.

**[中文说明](#zh-cn) · [English guide](#en)**

SwiftUI · macOS 13+ · 中文 / English · MIT

<a id="zh-cn"></a>

## 中文说明

拾期通过 [bb.cuhk.edu.cn](https://bb.cuhk.edu.cn) 的官方日历订阅链接读取日历事项，显示准确的截止日期、时间与倒计时，并通过 macOS 系统通知提醒。运行时无需 Python、Node.js 或后台服务器。

这是独立开发的免费开源项目，非学校或 Blackboard 官方产品，未经校方背书。「龙大」仅作为目标学生群体的非正式昵称。

### 功能

- **自动同步**：默认每 15 分钟更新，也可手动同步；同步失败时保留已有数据，显示错误和上次同步时间。
- **清晰的日期与时间**：按日期分组，详情显示星期、时分秒和时区；支持即将截止、未来 7 天、已逾期、已完成及搜索。
- **系统提醒**：默认提前 24 小时、3 小时、30 分钟，以及到期时提醒，可在设置中调整。
- **补充遗漏的 DDL**：支持手动添加和 `.ics` 文件导入；文件导入后不会自动更新。
- **Outlook 邮件候选**：可导入从 Outlook 下载的 `.eml` 邮件，在本机提取候选 DDL，核对后再添加；拥有 Microsoft Entra 应用注册权限时，也可用 Microsoft Graph 只读授权扫描最近 180 天的收件箱。
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

### 安装

#### 方式一：使用发布包

如果仓库的 **Releases** 页面提供安装包：

1. 下载适合自己 Mac 架构的 `拾期.zip` 并解压。
2. 将 `拾期.app` 拖入「应用程序」文件夹。
3. 从「应用程序」打开拾期，按下方说明连接 Blackboard 和启用通知。

当前构建脚本使用本地 **ad-hoc 签名**，不包含 Developer ID 签名或 Apple 公证。下载到另一台 Mac 后可能被系统阻止打开；如没有已签名、公证的发布包，可按方式二自行构建。源码仓库忽略 `dist/`，下载源码 ZIP 不会附带已编译的应用。

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

### 首次使用：连接 Blackboard

1. 在拾期点击「连接 Blackboard」。可以在应用内登录，也可以点击「在默认浏览器打开 Blackboard」。
2. 使用自己的学校账号登录，打开**全局「日历 / Calendar」**。
3. 根据 Blackboard 界面版本，点击 **Get External Calendar Link**；或打开日历设置，在更多选项中选择 **Share Calendar**。[Blackboard 官方说明](https://help.anthology.com/blackboard/student/en/original-course-view/stay-in-the-loop/calendar.html)
4. 复制生成的**完整个人日历链接**。网站首页或 `/webapps/calendar/calendarFeed/` 这样的路径前缀不能代替完整共享链接。
5. 把链接粘贴到拾期，点击「连接并同步」。应用内登录窗口会尝试检测页面已经展示的订阅链接；未检测到时可手动粘贴。
6. 同步成功后，检查界面中的日期、时间、连接状态与上次同步时间。

**共享链接可能含个人访问令牌，可访问你的日历。不要放进公开 Issue、截图、日志或 Git 仓库。**

### 从 Outlook 邮件补充 DDL

**无需管理员权限的方式：**在 Outlook 网页版打开相关邮件，点击邮件右上角「更多操作 → 下载」，取得 `.eml` 文件（若下载为 `.msg`，该格式目前不支持）。在拾期点击信封图标或侧栏「Outlook 邮件」，选择「导入 Outlook 邮件文件（.eml）」。应用会在本机解析邮件并列出候选日期；逐条核对课程、日期和时刻，再勾选添加。[微软的邮件下载说明](https://support.microsoft.com/en-us/outlook/mail/save-an-outlook-message-as-a-eml-file-a-pdf-file-or-as-a-draft)

**可选的直接扫描：**若学校允许你在 Microsoft Entra 注册应用，创建公共客户端应用，启用 **Allow public client flows**，添加 Microsoft Graph 的 **Mail.Read（Delegated）** 权限。把 **Application (client) ID** 填到拾期的 Outlook 窗口；可选填 **Directory (tenant) ID**。点击「获取微软授权码」，在微软登录页面输入代码并完成授权，然后点击「扫描收件箱」。学校可能禁用应用注册或要求管理员批准；此时使用 `.eml` 导入即可。不要把 Client Secret、邮箱密码或授权令牌粘贴到应用中。[微软的应用注册说明](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)

扫描只在点击时执行，不会后台持续读取。拾期最多查看最近 180 天、前 300 封收件箱邮件，不读取附件，也不发送或修改邮件。候选内容在本机分析，只有选中的 DDL 会保存；授权令牌保存在 macOS 钥匙串。日期未写具体时刻时标注「时间待确认」。邮件正文中的日期识别可能遗漏或误判，添加前请核对原文。

### 开启与调整提醒

1. 点击「开启提醒」，在 macOS 提示中允许通知。
2. 打开「提醒与设置」，点击「允许通知 / 发送测试通知」。测试通知会在约 5 秒后触发。
3. 在设置中选择提醒时点，也可调整自动同步间隔、时区及「登录 Mac 时启动拾期」。

只有日期、没有具体时间的事项会标注「时间待确认」，在前一天和当天 **09:00** 提醒，不会自动猜测截止时间为 23:59。导入时已经过去的提前提醒会跳过，仅安排剩余的未来提醒。

关闭主窗口后，拾期会继续在菜单栏运行和同步。选择「退出」会停止同步；已经排程的通知仍由 macOS 管理。电脑关机时无法提醒，睡眠、专注模式与系统通知设置也可能延迟展示。运行期间每分钟维护最多 60 条近期通知，优先安排较近的提醒。

### 日常操作

| 操作 | 使用方法 |
| --- | --- |
| 切换语言 | 「提醒与设置」→「语言 / Language」→ 简体中文或 English；即时生效并保存 |
| 添加截止日期 | 点击「添加 DDL」；填写任务、课程、日期、时间和备注 |
| 查看详情 | 点击任务行，查看完整时间与备注 |
| 补填课程 | 日历未提供课程时，点击任务行 →「设置课程」；课程标注保存在本机，同步后保留 |
| 标记完成 | 点击任务左侧圆圈，或在详情中标记完成；状态仅保存在本机 |
| 导入日历文件 | 点击主窗口右上角导入图标，选择小于 5 MB 的 UTF-8 `.ics` 文件 |
| 导入 Outlook 邮件 | 点击信封图标 → 导入 `.eml`；确认候选后添加 |
| 手动同步 | 点击「立即同步」，或使用菜单栏的同步按钮 |
| 管理订阅 | 点击「管理连接」；更换链接或断开连接 |

断开 Blackboard 会移除订阅链接、同步的 Blackboard 事项和相应提醒；手动添加和文件导入的事项会保留。

| 快捷键 | 功能 |
| --- | --- |
| `⌘N` | 添加截止日期 |
| `⌘R` | 同步 Blackboard |
| `⌘,` | 打开提醒设置 |

### 数据范围与隐私

- 拾期读取 Blackboard 日历订阅中的全部事项，可能包括作业、考试、上课时间与个人事件。仅写在公告、PDF 或课程说明中的 DDL，需要手动补充；邮件中的日期可通过 Outlook 邮件窗口导入并核对。
- 订阅链接保存在 **macOS 钥匙串**。软件不读取或保存学校密码；应用内登录使用临时 WebKit 会话，不持久化登录 cookie。
- 任务、完成状态和设置保存在 `~/Library/Application Support/DDLReminder/deadlines.json`；上一次保存的内容备份为同目录下的 `deadlines.backup.json`。备份课程数据时也应保护这些文件。
- 应用直接向日历服务器发起请求，不使用自建云端服务。HTTPS 重定向仅允许同一主机。
- Outlook 直接扫描使用微软登录与 Microsoft Graph；拾期不获取学校密码，不将邮件正文上传到项目服务器。ChatGPT/Codex 的 Outlook 连接与拾期的 Graph 授权彼此独立，不能共用令牌。

支持 UTC、IANA 时区、无时区日期、仅日期事项、VEVENT/VTODO、折行与转义、取消事件、每日/每周重复、EXDATE、RDATE 和单次重复事件改期。不支持的复杂重复规则或自定义 VTIMEZONE 会明确提示；请核对提示并手动补充，不保证支持所有 iCalendar 扩展。

### 常见问题

| 问题 | 处理方法 |
| --- | --- |
| 连接失败或 HTTP 401/403 | 确认使用完整的日历共享链接；必要时重新生成。检查校园网/VPN 是否可以访问 Blackboard。 |
| 应用内登录页面无法加载 | 在默认浏览器登录、获取共享链接，再粘贴到拾期。 |
| 没有看到某门课的作业 | 先核对 Blackboard 全局日历是否包含它；只在公告或附件里写出的 DDL 需手动添加。 |
| 没有收到通知 | 检查「系统设置」→「通知」→「拾期」、应用内「发送系统通知」与提醒时点，调整专注模式，并发送测试通知。 |
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

测试使用 XCTest；仅有 Command Line Tools、无法使用 XCTest 时，脚本使用仓库内的轻量测试运行器。当前 25 项测试覆盖日期转换、夏令时、全天事项、重复例外、提醒计划、同步合并、UID 变化后的完成状态、跨来源重导入、旧版数据迁移和语言设置。

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

源码、测试、脚本和文档提交到仓库；`dist/`、构建缓存、日志和个人日历数据由 `.gitignore` 排除。可将构建出的 `dist/拾期.zip` 单独上传到 GitHub Release，并注明版本、架构与签名/公证状态。不要把整个工作目录打包后当作源码发布。面向其他 Mac 分发时，建议采用 Developer ID 签名和 Apple 公证；当前脚本不会自动执行这两步。

### 许可证与品牌素材

项目代码、原创图标与文档采用 [MIT License](LICENSE)。1.1.2 已移除学校校徽、校名标志和相关图片，使用拾期自身的日历图标。命名、素材和独立项目说明见 [Resources/Branding.md](Resources/Branding.md)。

---

<a id="en"></a>

## English guide

Shiqi reads calendar events from the official subscription feed on [bb.cuhk.edu.cn](https://bb.cuhk.edu.cn), displays exact deadlines and countdowns, and sends macOS notifications. No Python, Node.js, or background server is required at runtime.

This is an independently developed, free and open-source project, not an official or university-endorsed product or an official Blackboard product. “Longda” is an informal nickname for the intended student community.

### Features

- **Automatic sync:** updates every 15 minutes by default, with manual refresh available. Failed syncs keep existing data and show the error and last successful sync time.
- **Clear dates and times:** events grouped by date; details include the weekday, seconds, and time zone. Filter upcoming, next 7 days, overdue, or completed items, and search your tasks.
- **System reminders:** alerts 24 hours, 3 hours, and 30 minutes before a deadline, and at the deadline, with configurable reminder times.
- **Add missing deadlines:** create tasks manually or import `.ics` files. File imports do not update automatically.
- **Outlook mail candidates:** import downloaded `.eml` messages for local deadline extraction and review. If your school permits an Entra app registration, you can also grant read-only Microsoft Graph access to scan recent inbox mail.
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

### Installation

#### Option 1: A release package

If an app package is available on the repository's **Releases** page:

1. Download `拾期.zip` for your Mac's architecture and extract it.
2. Drag `拾期.app` into **Applications**.
3. Open Shiqi from Applications, then connect Blackboard and enable notifications as described below.

The current build script uses a local **ad-hoc signature**, without Developer ID signing or Apple notarization. A downloaded build may be blocked on another Mac. If a signed, notarized release is unavailable, build from source using Option 2. The source repository ignores `dist/`; downloading its source ZIP does not include a compiled app.

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

### First use: Connect Blackboard

1. Click **Connect Blackboard**. Sign in inside the app, or choose **Open Blackboard in your browser**.
2. Sign in with your university account and open the **global Calendar**.
3. Depending on the Blackboard interface, choose **Get External Calendar Link**, or open Calendar Settings and choose **Share Calendar** from the additional options. [Official Blackboard instructions](https://help.anthology.com/blackboard/student/en/original-course-view/stay-in-the-loop/calendar.html)
4. Copy the **complete personal calendar link**. The homepage or a path prefix such as `/webapps/calendar/calendarFeed/` is not a complete sharing link.
5. Paste it into Shiqi and click **Connect & sync**. The embedded sign-in window attempts to detect a subscription link already displayed on the page; you can paste it manually if detection fails.
6. After sync, check the dates, times, connection status, and last sync time.

**The sharing link may contain a private access token that grants access to your calendar. Keep it out of public issues, screenshots, logs, and Git repositories.**

### Add deadlines from Outlook mail

**Without admin access:** open a message in Outlook on the web and choose **More actions → Download**. In Shiqi, open **Outlook mail** and import the downloaded `.eml` file. Review each candidate before adding it. `.msg` files are not supported. [Microsoft's download instructions](https://support.microsoft.com/en-us/outlook/mail/save-an-outlook-message-as-a-eml-file-a-pdf-file-or-as-a-draft)

**Optional direct scan:** register a public client app in Microsoft Entra, enable **Allow public client flows**, add delegated Microsoft Graph **Mail.Read**, then enter the **Application (client) ID** in Shiqi. A **Directory (tenant) ID** is optional. Complete Microsoft's device-code sign-in and choose **Scan inbox**. Your school may block app registrations or require administrator consent; use `.eml` import in that case. Never enter a Client Secret, mailbox password, or token in Shiqi. [Microsoft's registration guide](https://learn.microsoft.com/en-us/entra/identity-platform/quickstart-register-app)

Scanning runs only when requested, reads at most 300 inbox messages from the last 180 days, and does not read attachments, send, or change messages. Candidate analysis is local; only selected deadlines are saved. Tokens are held in macOS Keychain. Confirm dates against the original message because extraction can miss or misread them.

### Enable and configure reminders

1. Click **Enable reminders** and allow notifications in the macOS prompt.
2. Open **Reminders & settings** and click **Allow / test notifications**. The test notification triggers after approximately 5 seconds.
3. Select reminder times in settings. You can also change the sync interval, time zone, and **Launch Shiqi at login** preference.

Date-only items are marked **Time to confirm** and receive reminders at **09:00** on the previous day and the due date. Shiqi does not assume a deadline time of 23:59. Reminder times that have already passed at import are skipped; remaining future reminders are scheduled.

Closing the main window keeps Shiqi running and syncing in the menu bar. **Quit** stops sync; macOS still manages notifications already scheduled. Alerts cannot appear while the Mac is shut down, and sleep, Focus, or notification settings may delay them. While running, Shiqi maintains up to 60 upcoming notifications each minute, prioritizing the nearest alerts.

### Everyday use

| Action | How |
| --- | --- |
| Change language | **Reminders & settings → 语言 / Language → 简体中文 / English**; applies immediately and persists |
| Add a deadline | Click **Add deadline**; enter the task, course, date, time, and notes |
| View details | Click a task row to see its full time and notes |
| Label a course | If the calendar omits it, open the task and choose **Set course**; the local label remains after sync |
| Mark complete | Click the circle beside a task, or mark it complete in details; completion is stored locally |
| Import a calendar | Use the import icon at the top right; choose a UTF-8 `.ics` file smaller than 5 MB |
| Import Outlook mail | Use the envelope icon to import `.eml` files; review candidates before adding |
| Refresh manually | Click **Sync now** or the menu bar's sync button |
| Manage a subscription | Click **Manage connection** to replace the link or disconnect |

Disconnecting removes the subscription, synced Blackboard events, and associated reminders. Manual tasks and file-imported events are kept.

| Shortcut | Action |
| --- | --- |
| `⌘N` | Add a deadline |
| `⌘R` | Sync Blackboard |
| `⌘,` | Open reminder settings |

### Coverage and privacy

- Shiqi imports all events in the Blackboard calendar feed, which may include assignments, exams, classes, and personal events. Deadlines mentioned only in announcements, PDFs, or course documents must be added manually; mail dates can be imported and reviewed in the Outlook window.
- The subscription link is stored in **macOS Keychain**. Shiqi does not read or store your university password. Embedded sign-in uses a temporary WebKit session without persistent login cookies.
- Tasks, completion status, and preferences are stored in `~/Library/Application Support/DDLReminder/deadlines.json`. The previous saved version is kept as `deadlines.backup.json` in the same directory. Treat these files as private when backing up course data.
- The app requests the calendar directly from its server, without a project-operated cloud service. HTTPS redirects are allowed only to the same host.
- Direct Outlook scanning uses Microsoft sign-in and Microsoft Graph. Shiqi never receives your school password or uploads email bodies to a project server. ChatGPT/Codex Outlook connections have separate authorization that a standalone Shiqi app cannot reuse.

The parser supports UTC, IANA zones, floating times, date-only events, VEVENT/VTODO, line folding and escaping, cancellations, daily/weekly recurrence, EXDATE, RDATE, and individual recurrence overrides. Unsupported complex recurrence rules or custom VTIMEZONE definitions produce warnings. Review those warnings and add missing items manually; full support for every iCalendar extension is not claimed.

### Troubleshooting

| Problem | What to check |
| --- | --- |
| Connection fails or returns HTTP 401/403 | Use the complete calendar sharing link, regenerate it if necessary, and check campus network/VPN access. |
| Embedded sign-in fails to load | Obtain the sharing link in your default browser and paste it into Shiqi. |
| An assignment is missing | Check whether it appears in Blackboard's global Calendar. Add deadlines from announcements or attachments manually. |
| Notifications do not appear | Check **System Settings → Notifications → 拾期**, **Send system notifications**, and the selected reminder times. Review Focus settings and send a test notification. |
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

Tests use XCTest. When only Command Line Tools are available and XCTest is missing, the script uses the repository's lightweight test runner. The current 25 cases cover date conversion, daylight saving, date-only events, recurrence exceptions, reminder planning, sync merging, completion with changing UIDs, cross-source reimports, legacy data migration, and language settings.

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

Commit source, tests, scripts, and documentation. `.gitignore` excludes `dist/`, build caches, logs, and personal calendar data. Upload the generated `dist/拾期.zip` separately as a GitHub Release asset, stating its version, architecture, and signing/notarization status. Do not publish a ZIP of the entire working directory as source. Developer ID signing and Apple notarization are recommended for distributing to other Macs; the current script performs neither automatically.

### License and branding

Project code, original icons, and documentation are licensed under the [MIT License](LICENSE). Version 1.1.2 removes the university emblem, official wordmark, and related images, using Shiqi’s own calendar icon. See [Resources/Branding.md](Resources/Branding.md) for naming, assets, and independent-project disclosures.
