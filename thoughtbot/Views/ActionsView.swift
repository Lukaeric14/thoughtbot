import SwiftUI

struct ActionsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)
                Text("Actions coming soon")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text("This is where automated actions will appear")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Actions")
        }
    }
}

#Preview {
    ActionsView()
}
