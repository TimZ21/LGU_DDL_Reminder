# 拾期 iOS · Shiqi for iOS

[中文](#中文) · [English](#english)

## 中文

这是与 macOS 版共存的 iPhone / iPad 开发版，最低 iOS 17。共用 `DeadlineCore` 的日历解析、完成状态匹配、时区和提醒计划；手机界面、后台刷新及沙盒数据独立。没有第三方依赖或后台服务器。

### 安装开发环境

1. 从 [Mac App Store](https://apps.apple.com/app/xcode/id497799835) 安装 Apple 的 Xcode。只安装 Command Line Tools 不包含 iOS SDK 或模拟器。
2. 首次打开 Xcode，阅读并自行接受 Apple 的许可，完成必要的系统授权和组件安装。选择安装 **iOS** 平台。可在 Xcode 的 Settings → Components 中补装 iOS Simulator Runtime；不同 Xcode 版本也可能将此页称为 Platforms。
3. 打开 `iOS/Shiqi.xcodeproj`，选择 **Shiqi iOS** scheme 和已安装的 iPhone 模拟器，点击 Run（`⌘R`）。模拟器构建使用本地签名，不需要开发者付费账户；不要禁用代码签名，否则钥匙串访问可能失败。
4. 本项目的 iOS 脚本通过 `DEVELOPER_DIR` 使用 `/Applications/Xcode.app`；macOS 脚本在 Command Line Tools 可用时优先使用它。两套脚本明确选择各自的工具链，无需手动反复调整全局 `xcode-select`。可用 `DEVELOPER_DIR` 显式覆盖。

安装与兼容性请参阅 [Apple Xcode 系统要求](https://developer.apple.com/xcode/system-requirements/) 和 [Apple 组件安装说明](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components)。

```sh
# 在仓库根目录：编译模拟器版本
bash scripts/build-ios.sh

# 列出可用模拟器
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available

# 把 <device-UUID> 换成上面列出的模拟器 ID，运行核心测试和 UI 测试
DDL_IOS_DESTINATION='platform=iOS Simulator,id=<device-UUID>' bash scripts/test-ios.sh
```

若 Xcode 不在默认位置，设置 `DDL_XCODE_PATH='/实际路径/Xcode.app'`，或直接设置 `DEVELOPER_DIR`。构建产物位于 `dist/ios-derived-data/`，不提交 GitHub。图标是项目原创日历图案；可用 `scripts/MakeIOSIcon.swift` 重新生成。

### 在自己的 iPhone 上运行

在 Xcode Settings → Accounts 添加自己的 Apple 账户，打开 Shiqi target 的 Signing & Capabilities，选择自己的 Team；若签名要求唯一标识，请只修改本地 Bundle Identifier。连接 iPhone，按系统提示信任 Mac，并开启 Developer Mode，然后选择 iPhone 运行。参见 [Apple 真机与模拟器说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)。

GitHub 的源码或模拟器 `.app` 不能直接拖到 iPhone 安装。面向他人分发通常需要 TestFlight / App Store 等正式签名流程；本项目目前不提供已签名的 iOS 公共安装包。

### 使用

1. 点击「连接 Blackboard 日历」。在 Safari 登录学校 Blackboard，打开全局 Calendar，用 **Get External Calendar Link / Share Calendar** 获取完整个人链接，再粘贴到 App。
2. 下拉列表手动同步；设置中可以调整刷新间隔。导入 `.ics` 文件则使用列表底部的「导入 .ics 日历文件」，支持小于 5 MB 的 UTF-8 日历。
3. 点任务圆圈完成或恢复待办，点任务文字查看完整日期、时区、课程及备注。重新导入已识别任务会保留完成状态，包括 Blackboard 重新生成 UID 的情况。
4. 右上角 `+` 添加手动 DDL。具体时间按 **深圳 (UTC+8)** 显示；只有日期的任务标记「时间待确认」，不虚构截止时间，通知安排在前一天和当天上午 9 点。
5. 设置 →「申请权限并测试通知」，允许系统通知。测试在约 5 秒后到达，可调整提前提醒时点。
6. 设置 →「同步到提醒事项」可选开启 Apple Reminders。手机使用 **「拾期 · iOS DDL」** 列表；完成状态在 App 与这个列表之间同步。具体截止时的 Reminders 提醒与 App 提前通知独立，同时开启可能重复提醒。关闭开关会保留导出的事项。
7. 设置 →「界面语言」选择简体中文或 English。课程原文不翻译。

### 手机端的差异与隐私

- iOS 不保证每 15 分钟后台刷新。后台任务由系统决定；打开 App 时会同步，已经排程的本地通知可在 App 未打开时送达。优先安排最近 60 条通知，后续打开或后台刷新时补充。强制退出、关闭后台刷新、专注模式和通知权限会影响提醒或新数据获取。
- 手机和 Mac 的日历导入、设置、完成状态各自保存，没有跨设备 App 数据同步。Mac 使用「拾期 · DDL」，iOS 使用「拾期 · iOS DDL」。使用 iCloud Reminders 时两个列表可在其他设备显示，但 App 分别管理自己的列表。
- 订阅令牌保存在手机的设备专用 Keychain 中，任务与备份保存在 App 沙盒的 Application Support/DDLReminder。没有读取 Mac 的数据，也不保存学校密码。不要公开订阅链接。
- 关闭提醒事项同步保留导出数据；断开手机订阅也保留已有 DDL 与通知。需要删除的手动任务可在详情中删除。
- `--demo` 只展示合成数据，不写入存储、不访问 Keychain、网络、通知或提醒事项。Debug 构建的 `--ui-testing` 使用独立测试文件，避免触碰个人数据；测试导入按钮仅在此模式显示。
- 模拟器用于开发验证。真实校园网络、VPN、锁屏通知、后台调度和 iCloud Reminders 仍需在自己的 iPhone 上核验。

### 验证记录

在 Xcode 27.0 / iOS 27.0 上，iPhone 17 的运行验证通过；iPhone SE（第三代）模拟器的 32 项核心测试与 4 项 UI 测试通过。UI 测试覆盖更换 UID 后重新导入、重启后保留完成状态、恢复待办、手动任务和英文设置持久化，以及中英文长文本与各页面布局。已检查默认字号、最大辅助功能字号、浅色与深色模式、竖屏与横屏；大字号时日期和时间使用独立的滚轮控件，避免横向溢出。macOS 的最小窗口、设置、连接、编辑和长标题详情页面也已检查。

模拟器 Debug 构建、普通启动、首次钥匙串读取及 Xcode Run 流程通过；真机 Release 构建通过但未签名。macOS 的 32 项核心测试及应用构建、签名验证也通过。

本版本为开发预览。iOS 本地通知送达与 Apple Reminders 同步尚未完成端到端验证；模拟器窗口控制异常使通知实测未能完成。真实校园订阅、后台调度、锁屏通知与提醒事项同步需要在自己的 iPhone 上进一步验证。

## English

This is an iPhone / iPad development version for iOS 17+, alongside the existing macOS app. Both platforms share `DeadlineCore` for calendar parsing, completion matching, time zones, and reminder planning. The mobile interface, background refresh, and sandbox storage are separate. No third-party dependencies or server are required.

### Set up and run

1. Install Apple's [Xcode from the Mac App Store](https://apps.apple.com/app/xcode/id497799835). Command Line Tools alone do not include the iOS SDK or Simulator.
2. Open Xcode, personally review and accept Apple's license, complete system authorization, and install the **iOS** platform and a simulator runtime. Additional runtimes are under Settings → Components (called Platforms in some versions).
3. Open `iOS/Shiqi.xcodeproj`, select the **Shiqi iOS** scheme and an installed iPhone simulator, then Run (`⌘R`). Simulator builds use local signing without a paid developer account. Do not disable code signing: Keychain access may fail in unsigned builds.
4. iOS scripts use `DEVELOPER_DIR` for `/Applications/Xcode.app`; Mac scripts prefer Command Line Tools when available. Each selects its toolchain without repeatedly changing global `xcode-select`. An explicit `DEVELOPER_DIR` overrides the default.

See [Apple's system requirements](https://developer.apple.com/xcode/system-requirements/) and [component installation guide](https://developer.apple.com/documentation/xcode/downloading-and-installing-additional-xcode-components).

```sh
bash scripts/build-ios.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available
DDL_IOS_DESTINATION='platform=iOS Simulator,id=<device-UUID>' bash scripts/test-ios.sh
```

Replace `<device-UUID>` with an installed simulator ID. For another Xcode location, set `DDL_XCODE_PATH` or `DEVELOPER_DIR`. Generated builds are under ignored `dist/ios-derived-data/`. The app icon is Shiqi's original calendar artwork.

To run on your iPhone, add your Apple account in Xcode Settings → Accounts, select your Team in Signing & Capabilities, connect and trust the device, enable Developer Mode when requested, and select it as the run destination. Change the local Bundle Identifier if signing requires it. See [Apple's device guide](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices).

GitHub source and simulator `.app` files cannot be installed directly on an iPhone. Wider distribution requires an appropriate signing and distribution flow such as TestFlight / App Store. No signed public iOS installer is currently provided.

### Use

1. Connect Blackboard: use Safari to sign in, open global Calendar, copy the complete **Get External Calendar Link / Share Calendar** URL, and paste it into Shiqi.
2. Pull down to sync or import a UTF-8 `.ics` calendar under 5 MB. File imports do not update automatically.
3. Tap a circle to complete or restore a task; tap its text for full details. Recognized reimports retain completion, including regenerated Blackboard UIDs.
4. Add manual tasks with `+`. Dates use **Shenzhen (UTC+8)**. Date-only tasks show “Time to confirm” and alert at 9 AM the day before and on the due date.
5. In Settings, choose **Allow and test notifications**. The test arrives in about 5 seconds. Select advance reminder times.
6. Optionally enable **Sync to Reminders**. The phone uses **拾期 · iOS DDL** with bidirectional completion. Reminders' due-time alerts are separate from Shiqi's advance notifications; enabling both may give duplicate alerts. Turning sync off keeps exported reminders.
7. Choose Chinese or English in Settings. Course content retains its original language.

### Mobile behavior and privacy

- iOS schedules background refresh opportunistically; a fixed 15-minute interval cannot be guaranteed. Opening the app refreshes data. Already-scheduled local notifications can arrive while the app is closed. The next 60 alerts are scheduled first and replenished when the app opens or refreshes. Force-quitting, background settings, Focus, and notification access can affect alerts or new imports.
- Phone and Mac imports, completion, and settings are independent; app data does not sync across devices. The Mac uses **拾期 · DDL** and iOS uses **拾期 · iOS DDL**. iCloud Reminders can display both lists on other devices, while each app manages its own list.
- The feed token is kept in device-only Keychain storage; tasks and backups live in the app sandbox under Application Support/DDLReminder. The mobile app does not read Mac data or save school passwords. Keep the feed URL private.
- Turning Reminders sync off retains exports. Disconnecting the phone feed retains existing deadlines and alerts. Manual tasks can be deleted from their details.
- `--demo` uses synthetic data without persistence or access to accounts, network, notifications, or Reminders. Debug-only `--ui-testing` uses separate test storage and exposes fixture buttons only in that mode.
- Verify campus access, VPN, lock-screen alerts, background scheduling, and iCloud Reminders on a real iPhone.

### Validation

With Xcode 27.0 / iOS 27.0, the iPhone 17 launch checks pass, and 32 core tests and 4 UI tests pass on an iPhone SE (3rd generation) simulator. UI coverage includes completion after a regenerated UID and relaunch, restoring an incomplete task, manual tasks and language persistence, and Chinese/English long content across the app's screens. Screenshots were checked at the default and largest accessibility text sizes, in light/dark mode and portrait/landscape. Accessibility sizes use separate date and time wheels to prevent horizontal overflow. The Mac's minimum window size, settings, connection, editor, and long-title details were also checked.

The Simulator Debug build, normal launch, initial Keychain read, and Xcode Run workflow work; the device Release build succeeds without signing. All 32 macOS core tests, the Mac build, and signature verification also pass.

This is a development preview. End-to-end iOS notification delivery and Apple Reminders sync have not been verified; simulator window-control errors prevented the notification check. Live campus feeds, background scheduling, lock-screen alerts, and Reminders sync need further testing on your own iPhone.
