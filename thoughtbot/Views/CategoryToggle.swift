import SwiftUI

/// A pill-shaped toggle for switching between Personal and Business categories
/// Tap anywhere to switch, or swipe to slide between states
struct CategoryToggle: View {
    @Binding var selectedCategory: Category

    var body: some View {
        HStack(spacing: 2) {
            // Personal icon
            Image(systemName: "house.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(selectedCategory == .personal ? .white : .white.opacity(0.4))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(selectedCategory == .personal ? Color.white.opacity(0.2) : Color.clear)
                )

            // Business icon
            Image(systemName: "building.2.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(selectedCategory == .business ? .white : .white.opacity(0.4))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(selectedCategory == .business ? Color.white.opacity(0.2) : Color.clear)
                )
        }
        .padding(3)
        .background(
            Capsule()
                .fill(Color(.systemGray5))
        )
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCategory = selectedCategory == .personal ? .business : .personal
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if value.translation.width > 0 {
                            // Swipe right -> business
                            selectedCategory = .business
                        } else {
                            // Swipe left -> personal
                            selectedCategory = .personal
                        }
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        )
    }
}

#Preview {
    VStack(spacing: 20) {
        CategoryToggle(selectedCategory: .constant(.personal))
        CategoryToggle(selectedCategory: .constant(.business))
    }
    .padding()
    .background(Color.black)
}
