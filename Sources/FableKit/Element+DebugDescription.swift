#if DEBUG
import Foundation

extension Element {
    public var debugDescription: String {
        let mirror = Mirror(reflecting: self)
        
        return (
            """
            \(mirror.subjectType)
                - id: \(self.id)
                - content: \(self.description)
                - lifetime: \(self.lifetime) (\(self.lifetime.isOver ? "over" : "alive")
                - contentData: \(self.contentData)
            """
        )
    }
}

extension EntityElement {
    nonisolated public var debugDescription: String {
        let mirror = Mirror(reflecting: self)
        
        return (
            """
            \(mirror.subjectType)
                - id: \(self.id)
                - content: \(self.description)
                - lifetime: \(self.lifetime) (\(self.lifetime.isOver ? "over" : "alive")
                - contentData: \(self.contentData)
                - entity: \(self.entity == nil ? "not loaded" : "loaded")
            """
        )
    }
}

extension TimelinedElement {
    nonisolated public var debugDescription: String {
        zip(elements, times).map {
            "\($0.1.seconds.formatted(.number.precision(.fractionLength(2))))s: \($0.0.debugDescription)"
        }.joined(separator: "\n")
    }
}
#endif
