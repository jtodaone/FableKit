import Foundation

@resultBuilder
public struct FableBuilder {
    public static func buildBlock(_ components: Page...) -> [Page] {
        return components
    }
}

@resultBuilder
public struct PageBuilder {
    public static func buildBlock(_ components: any Element...) -> [any Element] {
        return components
    }
}

infix operator >>>: AdditionPrecedence

public func >>>(_ lhs: Duration, _ rhs: any Element) -> (Duration, any Element) {
    return (lhs, rhs)
}

public func >>>(_ lhs: Double, _ rhs: any Element) -> (Duration, any Element) {
    return (Duration.nanoseconds(Int(lhs * 1e9)), rhs)
}

public func >>>(_ lhs: (Duration, any Element), _ rhs: Double) -> (Duration, any Element) {
    var copy = lhs.1
    copy.lifetime = .time(duration: Duration.nanoseconds(Int(rhs * 1e9)) - lhs.0)
    return (lhs.0, copy)
}

public func >>>(_ lhs: (Duration, any Element), _ rhs: Duration) -> (Duration, any Element) {
    var copy = lhs.1
    copy.lifetime = .time(duration: rhs - lhs.0)
    return (lhs.0, copy)
}

public func +(_ lhs: (Duration, any Element), _ rhs: Double) -> (Duration, any Element) {
    var copy = lhs.1
    copy.lifetime = .time(duration: .seconds(rhs))
    return (lhs.0, copy)
}

public func +(_ lhs: (Duration, any Element), _ rhs: Duration) -> (Duration, any Element) {
    var copy = lhs.1
    copy.lifetime = .time(duration: rhs)
    return (lhs.0, copy)
}

postfix operator -|

postfix public func -|(_ item: any Element) -> any Element {
    var copy = item
    copy.lifetime = .instant
    return copy
}

@resultBuilder
public struct TimelineBuilder {
    public static func buildBlock(_ components: (Duration, any Element)...) -> ([Duration], [any Element]) {
        let times = components.map { $0.0 }
        let events = components.map { $0.1 }
        
        return (times, events)
    }
}

extension Fable {
    @MainActor
    public init(defaultBundle: Bundle = Bundle.main, @FableBuilder pages: () -> [Page]) {
        Fable.defaultBundle = defaultBundle
        self.pages = pages()
    }
}

extension Page {
    public init(@PageBuilder elements: () -> [any Element]) {
        self.elements = elements()
    }
}

extension ConcurrentElement {
    public init(anchorOffset: SIMD3<Float> = .zero, @PageBuilder elements: () -> [any Element]) {
        self.elements = elements()
        self.anchorOffset = anchorOffset
    }
    
    public init(anchorOffset: SIMD3<Float> = .zero, @PageBuilder elements: () -> [any Element], onDisappear: @escaping @Sendable (FableController) -> ()) {
        self.elements = elements()
        self.onDisappear = onDisappear
        self.anchorOffset = anchorOffset
    }
    
    public init(id: UUID, anchorOffset: SIMD3<Float> = .zero, @PageBuilder elements: () -> [any Element], onDisappear: @escaping @Sendable (FableController) -> ()) {
        self.id = id
        self.elements = elements()
        self.onDisappear = onDisappear
        self.anchorOffset = anchorOffset
    }
}

extension TimelinedElement {
    public init (anchorOffset: SIMD3<Float> = .zero, @TimelineBuilder elements: () -> ([Duration], [any Element])) {
        let times = elements().0
        let elements = elements().1
        
        self.times = times
        self.elements = elements
        
        let id = self.id
        
        self.onRender = { @Sendable context in
            let events = zip(elements, times)
            for event in events {
                context.addElementToQueue(event.0, after: event.1, taskID: id)
            }
        }
        
        self.onDisappear = { @Sendable context in
            context.cancelQueue(for: id)
        }
        self.anchorOffset = anchorOffset
    }
}
