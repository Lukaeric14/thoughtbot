//
//  thoughtbotApp.swift
//  thoughtbot
//
//  Created by Luka Eric on 15/12/2025.
//

import SwiftUI
import BackgroundTasks

@main
struct thoughtbotApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background {
                scheduleBackgroundRefresh()
            }
        }
    }

    private func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.thoughtbot.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Register background tasks
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.thoughtbot.refresh", using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.thoughtbot.processing", using: nil) { task in
            self.handleBackgroundProcessing(task: task as! BGProcessingTask)
        }

        return true
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        // Schedule next refresh
        scheduleNextRefresh()

        // Fetch latest data
        Task {
            do {
                // Pre-fetch thoughts and tasks so they're ready when user opens app
                _ = try await APIClient.shared.fetchThoughts()
                _ = try await APIClient.shared.fetchTasks()
                task.setTaskCompleted(success: true)
            } catch {
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }

    private func handleBackgroundProcessing(task: BGProcessingTask) {
        // Handle any pending uploads from the queue
        Task {
            await CaptureQueue.shared.processQueue()
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }

    private func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.thoughtbot.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
