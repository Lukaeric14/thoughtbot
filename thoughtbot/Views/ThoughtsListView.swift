import SwiftUI
import Combine

struct ThoughtsListView: View {
    @Binding var selectedCategory: Category
    @StateObject private var dataStore = DataStore.shared
    @State private var showRecorder = false
    @State private var highlightedId: String?
    @State private var scrollToId: String?
    @State private var errorItemId: String?  // Track item with delete error

    private var thoughts: [Thought] {
        dataStore.thoughts(for: selectedCategory)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if dataStore.isLoadingThoughts && thoughts.isEmpty {
                    ProgressView("Loading thoughts...")
                } else if let error = dataStore.thoughtsError, thoughts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await dataStore.forceRefreshThoughts(for: selectedCategory) }
                        }
                    }
                } else if thoughts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("No thoughts yet")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap the mic to capture a thought")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(thoughts) { thought in
                                ThoughtRow(
                                    thought: thought,
                                    isHighlighted: highlightedId == thought.id,
                                    hasError: errorItemId == thought.id
                                )
                                .id(thought.id)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteThought(thought: thought)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable {
                            await dataStore.forceRefreshThoughts(for: selectedCategory)
                        }
                        .onChange(of: scrollToId) { _, newId in
                            if let id = newId {
                                withAnimation {
                                    proxy.scrollTo(id, anchor: .top)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    scrollToId = nil
                                }
                            }
                        }
                    }
                }

                // Floating record button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showRecorder = true }) {
                            Image(systemName: "mic.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                                .shadow(radius: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Thoughts")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CategoryToggle(selectedCategory: $selectedCategory)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    ProcessingIndicator {
                        // Navigate to most recent thought
                        if let firstThought = thoughts.first {
                            scrollToId = firstThought.id
                            highlightedId = firstThought.id
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    highlightedId = nil
                                }
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showRecorder) {
                CaptureView()
                    .presentationDetents([.medium])
            }
        }
        .task {
            // Initial load if cache is empty/stale
            await dataStore.refreshThoughtsIfNeeded(for: selectedCategory)
        }
        .onChange(of: selectedCategory) { _, newCategory in
            // Refresh if needed when category changes
            Task {
                await dataStore.refreshThoughtsIfNeeded(for: newCategory)
            }
        }
        .onReceive(dataStore.$personalThoughts.merge(with: dataStore.$businessThoughts)) { _ in
            // Highlight newest thought when data updates
            if let firstThought = thoughts.first, highlightedId == nil {
                // Only auto-highlight if we just got new data from a capture
                if CaptureQueue.shared.isProcessing == false && CaptureQueue.shared.queuedCount == 0 {
                    // Check if this is a recent thought (within last 5 seconds)
                    if firstThought.createdAt.timeIntervalSinceNow > -5 {
                        scrollToId = firstThought.id
                        highlightedId = firstThought.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            withAnimation {
                                highlightedId = nil
                            }
                        }
                    }
                }
            }
        }
    }

    private func deleteThought(thought: Thought) {
        let category = thought.category ?? selectedCategory

        // Optimistic delete - remove immediately with animation
        withAnimation(.easeOut(duration: 0.25)) {
            dataStore.removeThoughtLocally(id: thought.id, category: category)
        }

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        // API call in background
        Task {
            do {
                try await APIClient.shared.deleteThought(id: thought.id)
                // Success - item already removed
            } catch {
                print("Error deleting thought: \(error)")
                // Failure - restore item with animation
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        dataStore.restoreThought(thought, category: category)
                    }
                    // Show error state
                    showError(itemId: thought.id)
                }
            }
        }
    }

    private func showError(itemId: String) {
        errorItemId = itemId
        // Haptic feedback for error
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)

        // Auto-clear error after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation {
                if errorItemId == itemId {
                    errorItemId = nil
                }
            }
        }
    }
}

struct ThoughtRow: View {
    let thought: Thought
    var isHighlighted: Bool = false
    var hasError: Bool = false
    @State private var isExpanded = false
    @State private var shakeOffset: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main text with mention count badge
            HStack(spacing: 6) {
                Text(thought.text)
                    .font(.body)
                    .fontWeight(.semibold)

                // Mention count badge (only show if > 1)
                if let count = thought.mentionCount, count > 1 {
                    Text("x\(count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
            }

            // Collapsible transcript
            if let transcript = thought.transcript, !transcript.isEmpty, transcript != thought.text {
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                        Text(isExpanded ? "Hide transcript" : "Show transcript")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Text(transcript)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }

            // Timestamp
            Text(thought.createdAt, style: .relative)
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(0.7)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isHighlighted || hasError ? 8 : 0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .offset(x: shakeOffset)
        .animation(.easeInOut(duration: 0.3), value: isHighlighted)
        .onChange(of: hasError) { _, newValue in
            if newValue {
                // Shake animation
                withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                    shakeOffset = 8
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                        shakeOffset = -8
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                        shakeOffset = 4
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
                        shakeOffset = 0
                    }
                }
            }
        }
    }

    private var backgroundColor: Color {
        if hasError {
            return Color.red.opacity(0.15)
        } else if isHighlighted {
            return Color.accentColor.opacity(0.15)
        }
        return Color.clear
    }
}

#Preview {
    ThoughtsListView(selectedCategory: .constant(.personal))
}
