import SwiftUI
import UIKit
import BackgroundTasks
import DeadlineCore

@MainActor
final class MobileAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MobileBackgroundRefresh.register()
        return true
    }
}

@main
struct ShiqiApp: App {
    @UIApplicationDelegateAdaptor(MobileAppDelegate.self) private var delegate
    @StateObject private var store = MobileStore.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            MobileDashboardView().environmentObject(store)
                .environment(\.locale, store.language.locale)
                .environment(\.timeZone, store.preferences.timeZone)
                .tint(MobilePalette.purple)
                .task { await store.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await store.activate() } }
                    if phase == .background { store.isForeground = false; MobileBackgroundRefresh.schedule() }
                }
        }
    }
}

@MainActor
enum MobileBackgroundRefresh {
    static let identifier = "cn.shuning.ddlreminder.ios.refresh"
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else { task.setTaskCompleted(success: false); return }
            let work = Task { @MainActor in
                let success = await MobileStore.shared.refreshInBackground()
                refresh.setTaskCompleted(success: success)
                schedule()
            }
            refresh.expirationHandler = {
                work.cancel()
                Task { @MainActor in MobileStore.shared.cancelBackgroundRefresh() }
            }
        }
    }
    static func schedule() {
        let store = MobileStore.shared
        guard store.isConnected, !store.isDemo, !store.isUITesting else { return }
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(Double(max(15, store.preferences.syncMinutes) * 60))
        // Background refresh is opportunistic, never a promise of a precise interval.
        try? BGTaskScheduler.shared.submit(request)
    }
    static func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
}
