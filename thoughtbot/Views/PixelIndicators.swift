import SwiftUI

// MARK: - Color Palette
struct PixelColors {
    static let idle = Color.red
    static let recording = Color(red: 1.0, green: 0.08, blue: 0.8)      // Hot pink/magenta
    static let processing = Color(red: 0.6, green: 0.4, blue: 1.0)      // Purple
    static let success = Color(red: 0.3, green: 0.85, blue: 0.4)        // Green
    static let error = Color(red: 1.0, green: 0.3, blue: 0.3)           // Red
}

// MARK: - Base Pixel Grid Renderer
struct PixelGridRenderer: View {
    let pixelStates: [[Double]]  // 3x3 grid of opacity values (0.0 to 1.0)
    let color: Color
    let pixelSize: CGFloat
    let spacing: CGFloat

    init(pixelStates: [[Double]], color: Color, pixelSize: CGFloat = 16, spacing: CGFloat = 4) {
        self.pixelStates = pixelStates
        self.color = color
        self.pixelSize = pixelSize
        self.spacing = spacing
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { col in
                        RoundedRectangle(cornerRadius: pixelSize * 0.2)
                            .fill(color.opacity(pixelStates[row][col]))
                            .frame(width: pixelSize, height: pixelSize)
                    }
                }
            }
        }
    }
}

// MARK: - Microphone Pixel Indicator (Idle State)
// Pattern:
// ░ ▓ ░   (low, full, low)
// ▒ ▓ ▒   (med, full, med)
// · ▓ ·   (off, full, off)
struct MicrophonePixelIndicator: View {
    let pixelSize: CGFloat
    let spacing: CGFloat

    init(pixelSize: CGFloat = 16, spacing: CGFloat = 4) {
        self.pixelSize = pixelSize
        self.spacing = spacing
    }

    private let pattern: [[Double]] = [
        [0.25, 1.0, 0.25],  // top row: faint sides, bright center
        [0.5,  1.0, 0.5],   // middle row: medium sides, bright center
        [0.0,  1.0, 0.0]    // bottom row: empty sides, bright center
    ]

    var body: some View {
        PixelGridRenderer(
            pixelStates: pattern,
            color: PixelColors.idle,
            pixelSize: pixelSize,
            spacing: spacing
        )
    }
}

// MARK: - Wave Pixel Indicator (Recording State)
// Diagonal sweep from bottom-left to top-right
struct WavePixelIndicator: View {
    @State private var frame: Int = 0
    let pixelSize: CGFloat
    let spacing: CGFloat

    init(pixelSize: CGFloat = 16, spacing: CGFloat = 4) {
        self.pixelSize = pixelSize
        self.spacing = spacing
    }

    // Diagonal index for each cell (sum of row + col, but inverted for bottom-left start)
    // Grid positions and their diagonal index (for wave from bottom-left to top-right):
    // (0,0)=2  (0,1)=3  (0,2)=4
    // (1,0)=1  (1,1)=2  (1,2)=3
    // (2,0)=0  (2,1)=1  (2,2)=2
    private func diagonalIndex(row: Int, col: Int) -> Int {
        return (2 - row) + col
    }

    // Wave animation: diagonal sweep with trailing glow
    // 7 frames total (5 diagonals + 2 pause frames)
    private func opacity(row: Int, col: Int) -> Double {
        let diagIdx = diagonalIndex(row: row, col: col)
        let phase = frame % 7

        // Calculate distance from current wave front
        let distance = diagIdx - phase

        switch distance {
        case 0:  // Wave front (brightest)
            return 1.0
        case -1:  // Just passed (trailing)
            return 0.6
        case -2:  // Further behind (fading)
            return 0.25
        case 1:  // About to hit (leading glow)
            return 0.3
        default:
            return 0.0
        }
    }

    private var pixelStates: [[Double]] {
        (0..<3).map { row in
            (0..<3).map { col in opacity(row: row, col: col) }
        }
    }

    var body: some View {
        PixelGridRenderer(
            pixelStates: pixelStates,
            color: PixelColors.recording,
            pixelSize: pixelSize,
            spacing: spacing
        )
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.15)) {
                frame += 1
            }
        }
    }
}

// MARK: - Breathe Pixel Indicator (Processing State)
// Pulse expanding from center outward
struct BreathePixelIndicator: View {
    @State private var frame: Int = 0
    let pixelSize: CGFloat
    let spacing: CGFloat

    init(pixelSize: CGFloat = 16, spacing: CGFloat = 4) {
        self.pixelSize = pixelSize
        self.spacing = spacing
    }

    // Distance from center for each cell
    // (0,0)=2  (0,1)=1  (0,2)=2
    // (1,0)=1  (1,1)=0  (1,2)=1
    // (2,0)=2  (2,1)=1  (2,2)=2
    private func distanceFromCenter(row: Int, col: Int) -> Int {
        let centerRow = 1, centerCol = 1
        return abs(row - centerRow) + abs(col - centerCol)
    }

    // Breathe animation: pulse from center outward then back
    // 6 frames total
    private func opacity(row: Int, col: Int) -> Double {
        let dist = distanceFromCenter(row: row, col: col)
        let phase = frame % 6

        switch phase {
        case 0:  // Center only
            return dist == 0 ? 1.0 : 0.0
        case 1:  // Center bright, ring 1 starting
            if dist == 0 { return 1.0 }
            if dist == 1 { return 0.4 }
            return 0.0
        case 2:  // Ring 1 bright, center fading, ring 2 starting
            if dist == 0 { return 0.6 }
            if dist == 1 { return 1.0 }
            if dist == 2 { return 0.3 }
            return 0.0
        case 3:  // Ring 2 bright, others fading
            if dist == 0 { return 0.3 }
            if dist == 1 { return 0.6 }
            if dist == 2 { return 1.0 }
            return 0.0
        case 4:  // All fading back
            if dist == 0 { return 0.5 }
            if dist == 1 { return 0.4 }
            if dist == 2 { return 0.6 }
            return 0.0
        case 5:  // Pause before restart
            if dist == 0 { return 0.7 }
            if dist == 1 { return 0.2 }
            return 0.0
        default:
            return 0.0
        }
    }

    private var pixelStates: [[Double]] {
        (0..<3).map { row in
            (0..<3).map { col in opacity(row: row, col: col) }
        }
    }

    var body: some View {
        PixelGridRenderer(
            pixelStates: pixelStates,
            color: PixelColors.processing,
            pixelSize: pixelSize,
            spacing: spacing
        )
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                frame += 1
            }
        }
    }
}

// MARK: - Arrow Up Pixel Indicator (Success State)
// Pattern:
// · ▓ ·   (off, full, off)
// ▓ ▓ ▓   (full, full, full)
// · ▓ ·   (off, full, off)
// With upward animation
struct ArrowUpPixelIndicator: View {
    @State private var frame: Int = 0
    let pixelSize: CGFloat
    let spacing: CGFloat

    init(pixelSize: CGFloat = 16, spacing: CGFloat = 4) {
        self.pixelSize = pixelSize
        self.spacing = spacing
    }

    // Arrow pixels: center column + middle row
    private func isArrowPixel(row: Int, col: Int) -> Bool {
        return col == 1 || row == 1
    }

    // Animation: arrow "rises" from bottom to top with trailing glow
    private func opacity(row: Int, col: Int) -> Double {
        if !isArrowPixel(row: row, col: col) { return 0.0 }

        let phase = frame % 8

        switch phase {
        case 0:  // Bottom stem starts
            if row == 2 && col == 1 { return 1.0 }
            return 0.0
        case 1:  // Bottom bright, middle row starting
            if row == 2 && col == 1 { return 0.8 }
            if row == 1 { return 0.4 }
            return 0.0
        case 2:  // Middle row bright, bottom fading, top starting
            if row == 1 { return 1.0 }
            if row == 2 && col == 1 { return 0.4 }
            if row == 0 && col == 1 { return 0.3 }
            return 0.0
        case 3:  // Top bright, middle fading
            if row == 0 && col == 1 { return 1.0 }
            if row == 1 { return 0.6 }
            if row == 2 && col == 1 { return 0.2 }
            return 0.0
        case 4:  // Full arrow visible, top brightest
            if row == 0 && col == 1 { return 1.0 }
            if row == 1 { return 0.8 }
            if row == 2 && col == 1 { return 0.5 }
            return 0.0
        case 5:  // Full arrow pulse
            if row == 0 && col == 1 { return 0.9 }
            if row == 1 { return 0.9 }
            if row == 2 && col == 1 { return 0.7 }
            return 0.0
        case 6:  // Fading out from bottom
            if row == 0 && col == 1 { return 0.7 }
            if row == 1 { return 0.5 }
            if row == 2 && col == 1 { return 0.2 }
            return 0.0
        case 7:  // Almost off, pause
            if row == 0 && col == 1 { return 0.3 }
            if row == 1 && col == 1 { return 0.2 }
            return 0.0
        default:
            return 0.0
        }
    }

    private var pixelStates: [[Double]] {
        (0..<3).map { row in
            (0..<3).map { col in opacity(row: row, col: col) }
        }
    }

    var body: some View {
        PixelGridRenderer(
            pixelStates: pixelStates,
            color: PixelColors.success,
            pixelSize: pixelSize,
            spacing: spacing
        )
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            withAnimation(.easeOut(duration: 0.15)) {
                frame += 1
            }
        }
    }
}

// MARK: - Error Pixel Indicator (Error State)
// Pattern:
// ▓ · ▓   (full, off, full)
// · ▓ ·   (off, full, off)
// ▓ · ▓   (full, off, full)
// X pattern with pulse animation
struct ErrorPixelIndicator: View {
    @State private var frame: Int = 0
    let pixelSize: CGFloat
    let spacing: CGFloat

    init(pixelSize: CGFloat = 16, spacing: CGFloat = 4) {
        self.pixelSize = pixelSize
        self.spacing = spacing
    }

    // X pattern pixels: diagonals
    private func isXPixel(row: Int, col: Int) -> Bool {
        return row == col || row == (2 - col)
    }

    // Animation: X pulses/flashes
    private func opacity(row: Int, col: Int) -> Double {
        if !isXPixel(row: row, col: col) { return 0.0 }

        let phase = frame % 6

        switch phase {
        case 0:  // Full X
            return 1.0
        case 1:  // Slight fade
            return 0.8
        case 2:  // More fade
            return 0.5
        case 3:  // Dim
            return 0.3
        case 4:  // Coming back
            return 0.6
        case 5:  // Almost full
            return 0.9
        default:
            return 1.0
        }
    }

    private var pixelStates: [[Double]] {
        (0..<3).map { row in
            (0..<3).map { col in opacity(row: row, col: col) }
        }
    }

    var body: some View {
        PixelGridRenderer(
            pixelStates: pixelStates,
            color: PixelColors.error,
            pixelSize: pixelSize,
            spacing: spacing
        )
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.1)) {
                frame += 1
            }
        }
    }
}

// MARK: - Preview
#Preview("All States") {
    VStack(spacing: 40) {
        VStack {
            MicrophonePixelIndicator(pixelSize: 24, spacing: 6)
            Text("Idle").font(.caption)
        }

        VStack {
            WavePixelIndicator(pixelSize: 24, spacing: 6)
            Text("Recording").font(.caption)
        }

        VStack {
            BreathePixelIndicator(pixelSize: 24, spacing: 6)
            Text("Processing").font(.caption)
        }

        VStack {
            ArrowUpPixelIndicator(pixelSize: 24, spacing: 6)
            Text("Success").font(.caption)
        }

        VStack {
            ErrorPixelIndicator(pixelSize: 24, spacing: 6)
            Text("Error").font(.caption)
        }
    }
    .padding(40)
    .background(Color.black)
}
