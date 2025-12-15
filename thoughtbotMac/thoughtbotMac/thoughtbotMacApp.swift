//
//  thoughtbotMacApp.swift
//  thoughtbotMac
//
//  Created by Luka Eric on 15/12/2025.
//

import SwiftUI
import Carbon.HIToolbox

@main
struct thoughtbotMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popoverWindow: RecordingWindow?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()
        setupGlobalHotkey()

        // Show status indicator immediately
        popoverWindow = RecordingWindow()

        // Check accessibility permissions
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Thoughtbot")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold Right Option to record", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func setupGlobalHotkey() {
        // Monitor flagsChanged for modifier keys (Option, Command, etc.)
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()
                return appDelegate.handleFlagsChanged(event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap. Check Accessibility permissions.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Right Option key code is 61
        let isRightOptionPressed = keyCode == 61 && flags.contains(.maskAlternate)
        let isRightOptionReleased = keyCode == 61 && !flags.contains(.maskAlternate)

        if isRightOptionPressed && !isRecording {
            isRecording = true
            DispatchQueue.main.async {
                self.showRecordingWindow()
            }
        } else if isRightOptionReleased && isRecording {
            isRecording = false
            DispatchQueue.main.async {
                self.hideRecordingWindow()
            }
        }

        return Unmanaged.passRetained(event)
    }

    private func showRecordingWindow() {
        popoverWindow?.show()
    }

    private func hideRecordingWindow() {
        popoverWindow?.stopAndSend()
    }

    @objc private func quit() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        NSApplication.shared.terminate(nil)
    }
}
