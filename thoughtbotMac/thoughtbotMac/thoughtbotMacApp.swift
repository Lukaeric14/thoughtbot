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
            button.image = createGridIcon()
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Hold Right Option to record voice", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Press Left Option to type", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func createGridIcon() -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size))

        image.lockFocus()

        let dotSize: CGFloat = 4
        let spacing: CGFloat = 2
        let gridSize = dotSize * 3 + spacing * 2
        let offset = (size - gridSize) / 2

        NSColor.white.setFill()

        for row in 0..<3 {
            for col in 0..<3 {
                let x = offset + CGFloat(col) * (dotSize + spacing)
                let y = offset + CGFloat(row) * (dotSize + spacing)
                let rect = NSRect(x: x, y: y, width: dotSize, height: dotSize)
                let path = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
                path.fill()
            }
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
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
                    if let tap = appDelegate.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }

                return appDelegate.handleFlagsChanged(event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap. Check Accessibility permissions.")
            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Thoughtbot needs accessibility permissions to detect the Option key. Please grant access in System Settings → Privacy & Security → Accessibility."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
            return
        }

        print("Event tap created successfully")
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Event tap enabled and listening for Option key")
    }

    private func handleFlagsChanged(event: CGEvent) -> Unmanaged<CGEvent>? {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Track shift state
        isShiftHeld = flags.contains(.maskShift)

        // Key codes for Option keys:
        // 58 = Left Option
        // 61 = Right Option
        // Note: Some keyboards might report different codes, so we also check the flag
        let isOptionKey = keyCode == 58 || keyCode == 61
        let optionFlagSet = flags.contains(.maskAlternate)

        // Right Option key code is 61 (voice recording)
        let isRightOptionPressed = keyCode == 61 && optionFlagSet
        let isRightOptionReleased = keyCode == 61 && !optionFlagSet

        // Left Option key code is 58 (typing input)
        let isLeftOptionPressed = keyCode == 58 && optionFlagSet

        // Debug logging (only for option key events to reduce noise)
        if isOptionKey {
            print("Option key event - keyCode: \(keyCode), flags: \(flags.rawValue), optionFlag: \(optionFlagSet), rightOptPressed: \(isRightOptionPressed), rightOptReleased: \(isRightOptionReleased), leftOptPressed: \(isLeftOptionPressed), isRecording: \(isRecording)")
        }

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
