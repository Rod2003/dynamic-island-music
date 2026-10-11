import AppKit

public enum Constants {
    public enum Analyzer {
        public static let edges: [Float] = [40, 120, 300, 800, 2000, 5000, 12000]
        public static let bands = edges.count - 1
        public static let balanceRise: Float = 1.5, balanceFall: Float = 8
        public static let contrast: [Float] = [2, 1.3, 1, 1, 1, 1], beatTime: Float = 0.25
        public static let rangeDB: Float = 18, peakFallDB: Float = 0.06
        public static let attack: Float = 0.015, release: Float = 0.06
        public static let showAfter: Float = 2.5, hideAfter: Float = 2
        public static let publishRate: Double = 60
    }

    public enum Tap {
        /// How long IO keeps running after the last process stops outputting. Outlasts `hideAfter` so the island fades out on silence first.
        public static let stopDelay = TimeInterval(Analyzer.hideAfter) + 0.5
    }

    public enum Island {
        public static let flare: CGFloat = 6, bottomRadius: CGFloat = 14, inset: CGFloat = 6
        public static let level: NSWindow.Level = .mainMenu + 3
    }
}
