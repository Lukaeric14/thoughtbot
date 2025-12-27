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

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popoverWindow: RecordingWindow?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRecording = false
    private var isShiftHeld = false
    private var isTyping = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("App launching...")

        // Check accessibility permissions first
        let isTrusted = AXIsProcessTrusted()
        print("Accessibility trusted: \(isTrusted)")

        if !isTrusted {
            print("Requesting accessibility permissions...")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }

        setupMenuBar()
        setupGlobalHotkey()

        // Show status indicator immediately
        popoverWindow = RecordingWindow()
        print("App launch complete")
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Thoughtbot")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold Right Option to record voice", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Press Left Option to type", action: nil, keyEquivalent: ""))
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

                // Handle event tap disabled (e.g., system disabled it)
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    print("Event tap was disabled, re-enabling...")
                    CGEvent.tapEnable(tap: appDelegate.eventTap!, enable: true)
                    return Unmanaged.passRetained(event)
                }

                return appDelegate.handleFlagsChanged(event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap. Check Accessibility permissions.")
            return
        }

        print("Event tap created successfully")
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Event tap enabled")
    }

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Track shift state
        isShiftHeld = flags.contains(.maskShift)

        // Right Option key code is 61 (voice recording)
        let isRightOptionPressed = keyCode == 61 && flags.contains(.maskAlternate)
        let isRightOptionReleased = keyCode == 61 && !flags.contains(.maskAlternate)

        // Left Option key code is 58 (typing input)
        let isLeftOptionPressed = keyCode == 58 && flags.contains(.maskAlternate)

        print("Key event - keyCode: \(keyCode), flags: \(flags.rawValue), rightOptPressed: \(isRightOptionPressed), rightOptReleased: \(isRightOptionReleased), leftOptPressed: \(isLeftOptionPressed), isRecording: \(isRecording)")

        // Left Option = activate typing mode (single press)
        if isLeftOptionPressed && !isRecording && !isTyping {
            print("Activating typing mode...")
            isTyping = true
            DispatchQueue.main.async {
                self.showTypingWindow()
            }
        }

        // Right Option handling (voice recording)
        if isRightOptionPressed {
            if isShiftHeld {
                // Shift + Right Option = toggle expanded view
                print("Toggle expanded view")
                DispatchQueue.main.async {
                    self.popoverWindow?.toggleExpanded()
                }
            } else if !isRecording && !isTyping {
                // Just Right Option = start recording
                print("Starting recording...")
                isRecording = true
                DispatchQueue.main.async {
                    self.showRecordingWindow()
                }
            }
        } else if isRightOptionReleased && isRecording {
            print("Stopping recording...")
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

    private func showTypingWindow() {
        popoverWindow?.showTyping()
    }

    func resetTypingState() {
        isTyping = false
    }

    @objc private func quit() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        NSApplication.shared.terminate(nil)
    }
}
