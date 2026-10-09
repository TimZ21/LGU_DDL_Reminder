import SwiftUI
import WebKit
import DeadlineCore

struct ConnectionView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var browserVisible = false
    @State private var foundLink: String?
    @State private var browserError: String?
    @State private var confirmDisconnect = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.t("连接 Blackboard", "Connect Blackboard")).font(.system(size: 23, weight: .semibold))
                    Text(store.t("bb.cuhk.edu.cn · 龙大校园日历", "bb.cuhk.edu.cn · Longda campus calendar")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.t("完成", "Done")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text(store.t("1. 登录 Blackboard，打开全局「日历 / Calendar」。", "1. Sign in to Blackboard and open the global Calendar."))
                Text(store.t("2. 点击「Get External Calendar Link」；新版在设置中选「Share Calendar」。", "2. Choose Get External Calendar Link, or Share Calendar in Calendar Settings."))
                Text(store.t("3. 复制完整链接，粘贴到下方。连接后会自动更新全部课程的日历事项。", "3. Paste the full link below. Calendar items from all courses will update automatically."))
            }.font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                SecureField(store.t("粘贴 HTTPS / webcal 日历订阅链接", "Paste an HTTPS / webcal calendar subscription link"), text: $link).textFieldStyle(.roundedBorder)
                    .onSubmit { connect() }
                Button { connect() } label: {
                    if store.isSyncing { ProgressView().controlSize(.small) } else { Text(store.t("连接并同步", "Connect & sync")) }
                }.buttonStyle(PrimaryButtonStyle()).disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || store.isSyncing || store.isDemo)
            }
            if let error = store.errorMessage {
                Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
            }
            HStack {
                Button(browserVisible ? store.t("收起登录窗口", "Hide sign-in window") : store.t("在应用内登录并获取链接", "Sign in here to get the link")) { browserVisible.toggle() }.disabled(store.isDemo)
                Button(store.t("在默认浏览器打开 Blackboard", "Open Blackboard in your browser")) {
                    if let url = URL(string: store.preferences.siteURL) { NSWorkspace.shared.open(url) }
                }
                Spacer()
                if store.isConnected {
                    Button(store.t("断开连接", "Disconnect"), role: .destructive) { confirmDisconnect = true }.disabled(store.isSyncing)
                }
            }.font(.system(size: 12))
            if browserVisible {
                if let found = foundLink {
                    HStack {
                        Label(store.t("检测到日历订阅链接", "Calendar subscription link found"), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                        Spacer()
                        Button(store.t("使用此链接", "Use this link")) { link = found; connect() }.buttonStyle(PrimaryButtonStyle()).disabled(store.isSyncing)
                    }.font(.callout)
                }
                if let error = browserError { Text(error).font(.caption).foregroundStyle(.orange) }
                BlackboardBrowser(siteURL: URL(string: store.preferences.siteURL)!, language: store.language, onFeed: { foundLink = $0 }, onError: { browserError = $0 })
                    .frame(height: 430).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            Text(store.t("登录信息由 Blackboard 页面处理。拾期只保存日历订阅链接到系统钥匙串；链接可访问你的日历，请勿公开。", "Blackboard handles sign-in. Shiqi stores only the subscription link in Keychain. Keep this link private: it grants access to your calendar."))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(26).frame(width: browserVisible ? 950 : 750).tint(Palette.controlAccent)
            .alert(store.t("断开 Blackboard？", "Disconnect Blackboard?"), isPresented: $confirmDisconnect) {
                Button(store.t("取消", "Cancel"), role: .cancel) {}
                Button(store.t("断开", "Disconnect"), role: .destructive) { store.disconnect(); dismiss() }
            } message: { Text(store.t("将移除订阅链接、同步的事项和对应提醒。手动添加与文件导入的事项会保留。", "This removes the subscription, synced items, and their reminders. Manual and file-imported tasks are kept.")) }
    }
    private func connect() {
        Task { if await store.connect(link) { dismiss() } }
    }
}

struct BlackboardBrowser: NSViewRepresentable {
    let siteURL: URL
    let language: AppLanguage
    let onFeed: (String) -> Void
    let onError: (String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(siteURL: siteURL, language: language, onFeed: onFeed, onError: onError) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Login cookies exist only for this temporary web view; no password storage or background browser.
        configuration.websiteDataStore = .nonPersistent()
        let hostLiteral = String(data: try! JSONEncoder().encode(siteURL.host!), encoding: .utf8)!
        let script = """
        (() => {
          if (location.hostname !== \(hostLiteral)) return;
          let last = '';
          function check() {
            const nodes = document.querySelectorAll('a[href], input[type="text"], input:not([type]), textarea');
            for (const el of nodes) {
              const raw = el.tagName === 'A' ? el.href : el.value;
              if (!raw || !/^(https:|webcal:)\\/\\//i.test(raw)) continue;
              try {
                const u = new URL(raw.replace(/^webcal:/i, 'https:'));
                if (u.hostname !== \(hostLiteral) || !/(\\.ics(?:$|[?])|calendarFeed|ical)/i.test(u.pathname + u.search)) continue;
                if (u.href !== last) { last = u.href; window.webkit.messageHandlers.calendarFeed.postMessage(u.href); }
              } catch (_) {}
            }
          }
          check();
          const observer = new MutationObserver(check);
          observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
          document.addEventListener('input', check);
          setInterval(check, 1500);
        })();
        """
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
        configuration.userContentController.add(context.coordinator, name: "calendarFeed")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator; view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: siteURL))
        return view
    }
    func updateNSView(_ nsView: WKWebView, context: Context) { context.coordinator.language = language }
    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.stopLoading(); nsView.configuration.userContentController.removeScriptMessageHandler(forName: "calendarFeed")
        nsView.navigationDelegate = nil; nsView.uiDelegate = nil
    }
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let siteURL: URL
        var language: AppLanguage
        let onFeed: (String) -> Void
        let onError: (String) -> Void
        init(siteURL: URL, language: AppLanguage, onFeed: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
            self.siteURL = siteURL; self.language = language; self.onFeed = onFeed; self.onError = onError
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.securityOrigin.host == siteURL.host,
                  message.frameInfo.securityOrigin.protocol == "https",
                  let text = message.body as? String, let url = try? FeedAddress.validate(text), url.host == siteURL.host else { return }
            onFeed(url.absoluteString)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onError(language.text("页面加载失败，请检查校园网/VPN。也可以在默认浏览器获取链接后粘贴。", "Page loading failed. Check your campus network/VPN, or get the link in your browser and paste it here.")) }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, ["https", "about"].contains(url.scheme ?? "") else {
                decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url, url.scheme == "https" {
                webView.load(navigationAction.request)
            }
            return nil
        }
    }
}
