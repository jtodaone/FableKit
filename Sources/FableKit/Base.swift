import Foundation

public typealias RenderEventHandler = (@MainActor @Sendable (FableController) -> ())

public struct Fable: Sendable {
    public var pages: [Page]
    @MainActor public static var defaultBundle: Bundle = Bundle.main
}

public struct Page: Sendable {
    var elements: [any Element]
}

extension Page: CustomStringConvertible {
    public var description: String { self.elements.map { $0.description }.joined(separator: "\n\n") }
}

#if !DEBUG
public protocol Element: Identifiable, CustomStringConvertible, Sendable {
    var id: UUID { get }
    var type: ElementMetadata { get }
    var lifetime: Lifetime { get set }
    
    var onRender: RenderEventHandler? { get }
    var onDisappear: RenderEventHandler? { get }
}
#endif

#if DEBUG
public protocol Element: Identifiable, CustomStringConvertible, Sendable, CustomDebugStringConvertible {
    var id: UUID { get }
    var contentData: ContentData { get }
    var lifetime: Lifetime { get set }
    
    var onRender: RenderEventHandler? { get }
    var onDisappear: RenderEventHandler? { get }
}
#endif

public enum ContentData: Sendable {
    case text(content: String)
    case image(description: String)
    case concurrent
    case timelined
    case realityKitEntity
    case other
}

public enum Lifetime: Sendable, Equatable {
    case element(count: Int)
    case time(duration: Duration, expired: Bool = false)
    case instant
    case infinite
    case indefinite(isOver: Bool)
    
    public var isOver: Bool {
        switch self {
        case .element(let count) where count <= 0:
            return true
        case .instant:
            return true
        case .indefinite(let isOver):
            return isOver
        case .time(_, let expired):
            return expired
        default:
            
            return false
        }
    }
    
    public func decreased() -> Self {
        switch self {
        case .element(let count):
            return .element(count: count - 1)
        default:
            return self
        }
    }
    
    public func expired() -> Self {
        switch self {
        case .time(let duration, _):
            return .time(duration: duration, expired: true)
        default:
            return self
        }
    }
}

public protocol ControllerReferencingElement: Element {
    @MainActor var context: FableController? { get set }
    @MainActor func withContext(_ context: FableController) -> Self
}

protocol GroupElement: Element {
    @MainActor var elements: [any Element] { get set }
    @MainActor func withNewElements(_ newElements: [any Element]) -> Self
}

protocol Loadable: Element {
    var isLoaded: Bool { get }
}
