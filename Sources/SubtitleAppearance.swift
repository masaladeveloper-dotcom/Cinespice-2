import Foundation

/// Same relative sizes as VLC iOS. A smaller renderer divisor produces larger text.
enum SubtitleSize: Int, CaseIterable, Identifiable {
    case smallest = 20, small = 18, normal = 16, large = 12, largest = 6
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .smallest: return "Smallest"
        case .small: return "Small"
        case .normal: return "Normal"
        case .large: return "Large"
        case .largest: return "Largest"
        }
    }
    static func restored(_ value: Int) -> Self { Self(rawValue: value) ?? .normal }
}
