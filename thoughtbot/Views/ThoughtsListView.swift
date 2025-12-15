import SwiftUI

struct ThoughtsListView: View {
    @State private var thoughts: [Thought] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showRecorder = false

    var body: some View {
        NavigationStack {
            ZStack {
                if isLoading && thoughts.isEmpty {
                    ProgressView("Loading thoughts...")
                } else if let error = errorMessage, thoughts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(error)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            Task { await loadThoughts() }
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
                    List {
                        ForEach(thoughts) { thought in
                            ThoughtRow(thought: thought)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await loadThoughts()
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
            .sheet(isPresented: $showRecorder) {
                CaptureView()
                    .presentationDetents([.medium])
                    .onDisappear {
                        Task {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            await loadThoughts()
                        }
                    }
            }
        }
        .task {
            await loadThoughts()
        }
    }

    private func loadThoughts() async {
        isLoading = true
        errorMessage = nil

        do {
            thoughts = try await APIClient.shared.fetchThoughts()
        } catch {
            errorMessage = "Failed to load thoughts"
            print("Error loading thoughts: \(error)")
        }

        isLoading = false
    }
}

struct ThoughtRow: View {
    let thought: Thought
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main text (embossed/bold)
            Text(thought.text)
                .font(.body)
                .fontWeight(.semibold)

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
    }
}

#Preview {
    ThoughtsListView()
}
