import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ThoughtsListView()
                .tabItem {
                    Label("Thoughts", systemImage: "bubble.left.and.bubble.right")
                }
                .tag(0)

            TasksListView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(1)

            ActionsView()
                .tabItem {
                    Label("Actions", systemImage: "bolt.fill")
                }
                .tag(2)
        }
    }
}

#Preview {
    MainTabView()
}
