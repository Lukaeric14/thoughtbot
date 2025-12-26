//
//  ProcessingIndicator.swift
//  thoughtbot
//
//  Minimal processing indicator for navigation bar
//

import SwiftUI

struct ProcessingIndicator: View {
    @ObservedObject var captureQueue = CaptureQueue.shared
    @State private var rotation: Double = 0
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background circle
                Circle()
                    .fill(Color(.systemGray6))
                    .frame(width: 32, height: 32)

                // Processing ring animation
                if captureQueue.isProcessing {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(rotation))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                rotation = 360
                            }
                        }
                }

                // Count or checkmark
                if captureQueue.queuedCount > 0 {
                    Text("\(captureQueue.queuedCount)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(captureQueue.isProcessing ? .accentColor : .primary)
                } else if captureQueue.isProcessing {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.accentColor)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// Environment key to track highlighted item
struct HighlightedItemKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var highlightedItemId: String? {
        get { self[HighlightedItemKey.self] }
        set { self[HighlightedItemKey.self] = newValue }
    }
}

#Preview {
    HStack(spacing: 20) {
        ProcessingIndicator(onTap: {})
    }
}
