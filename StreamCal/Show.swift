import Foundation
import SwiftData

@Model
final class Show {
    var title: String
    var platform: String
    var createdAt: Date
    
    init(title: String, platform: String, createdAt: Date = .now) {
        self.title = title
        self.platform = platform
        self.createdAt = createdAt
    }
}
