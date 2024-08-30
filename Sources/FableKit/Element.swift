import Foundation
import SwiftUI
import RealityKit
import AVKit
import Combine

extension Array where Element: FableKit.Element {
    var expiredElements: Self {
        self.filter { $0.lifetime.isOver }
    }
}

extension Element {
    var lifetimeDecreased: Self {
        var copy = self
        copy.lifetime = copy.lifetime.decreased()
        return copy
    }
    
    var lifetimeExpired: Self {
        var copy = self
        copy.lifetime = copy.lifetime.expired()
        return copy
    }
}

@MainActor
public struct ConcurrentElement: GroupElement {
    nonisolated public var description: String { elements.map { $0.description }.joined(separator: "\n") }
    public var id = UUID()
    public var contentData: ContentData = .concurrent
    
    nonisolated public var lifetime: Lifetime {
        get {
            let isEverythingOver = self.elements.allSatisfy { $0.lifetime.isOver }
            return .indefinite(isOver: isEverythingOver)
        }
        set {}
    }
    
    public var elements: [any Element]
    public var onRender: RenderEventHandler? = nil
    public var onDisappear: RenderEventHandler? = nil
    
    private init(from previous: ConcurrentElement, with newElements: [any Element]) {
        self.id = previous.id
        self.contentData = previous.contentData
        self.elements = newElements
        self.onRender = previous.onRender
        self.onDisappear = previous.onDisappear
    }
    
    func withNewElements(_ newElements: [any Element]) -> Self {
        return Self(from: self, with: newElements)
    }
}

@MainActor
public struct TimelinedElement: GroupElement {
    nonisolated public var description: String {
        zip(elements, times).map {
            "\($0.1.seconds.formatted(.number.precision(.fractionLength(2))))s: \($0.0.description)"
        }.joined(separator: "\n")
    }
    public var id = UUID()
    public var contentData: ContentData = .timelined
    public var onRender: RenderEventHandler? = nil
    public var onDisappear: RenderEventHandler? = nil
    
    public var elements: [any Element]
    public let times: [Duration]
    public var lifetime: Lifetime = .indefinite(isOver: false)
    
    public init(elements: [any Element], times: [Duration]) {
        self.elements = elements
        self.times = times
        
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
    }
    
    private init(from previous: TimelinedElement, with newElements: [any Element]) {
        self.contentData = previous.contentData
        self.onRender = previous.onRender
        self.onDisappear = previous.onDisappear
        self.elements = newElements
        self.lifetime = previous.lifetime
        
        let times = previous.times
        let id = previous.id
        
        self.id = id
        self.times = times
        
        self.onRender = { @Sendable context in
            let events = zip(newElements, times)
            for event in events {
                context.addElementToQueue(event.0, after: event.1, taskID: id)
            }
        }
        
        self.onDisappear = { @Sendable context in
            context.cancelQueue(for: id)
        }
    }
    
    func withNewElements(_ newElements: [any Element]) -> Self {
        return Self(from: self, with: newElements)
    }
}

public struct ViewElement: Element, @unchecked Sendable {
    public var description = "<View>"
    public var id = UUID()
    public var contentData: ContentData
    
    public var body: AnyView
    
    public var onRender: RenderEventHandler? = nil
    public var onDisappear: RenderEventHandler? = nil
    
    public var lifetime: Lifetime = .element(count: 1)
    
    public init(description: String = "<View>", id: UUID = UUID(), type: ContentData = .other, lifetime: Lifetime = .element(count: 1), @ViewBuilder body: () -> some View) {
        self.description = description
        self.id = id
        self.contentData = type
        self.body = AnyView(body())
    }
}

@MainActor
public struct EntityElement: Element, Loadable {
    public var entity: Entity?
    public var description: String = "<Entity>"
    public var id: UUID = UUID()
    public let contentData = ContentData.realityKitEntity
    
    private var resourceName: String?
    private var bundle: Bundle?
    
    public var onRender: RenderEventHandler? = { _ in }
    public var onDisappear: RenderEventHandler? = { _ in }
    
    public var lifetime: Lifetime = .element(count: 1)
    public var isInteractable: Bool = false
    
    public private(set) var isLoaded = true
    
    public let initialPosition: (position: SIMD3<Float>, relativeToHead: Bool)
    public let initialRotation: (EulerAngles, lookAtHead: Bool)
    public let initialScale: SIMD3<Float>
    
    public init(entity: Entity, description: String = "<Entity>", initialPosition: (SIMD3<Float>, relativeToHead: Bool) = (.zero, false), initialRotation: (EulerAngles, lookAtHead: Bool) = (EulerAngles(), true), lifetime: Lifetime = .element(count: 1), initialScale: SIMD3<Float> = .one, isInteractable: Bool = false, onRender: @escaping RenderEventHandler = { _ in }, onDisappear: @escaping RenderEventHandler = { _ in }) {
        self.entity = entity
        self.description = description
        self.id = UUID()
        self.initialPosition = initialPosition
        self.initialRotation = initialRotation
        self.initialScale = initialScale
        self.lifetime = lifetime
        self.onRender = onRender
        self.onDisappear = onDisappear
        
        self.isInteractable = isInteractable
        
        if isInteractable {
            self.entity?.components.set(GestureComponent(canDrag: true, pivotOnDrag: true, preserveOrientationOnPivotDrag: true, canScale: true, canRotate: true))
        }
    }
    
    public init(named resourceName: String, in bundle: Bundle? = nil, description: String = "<Entity>", initialPosition: (SIMD3<Float>, relativeToHead: Bool) = (.zero, false), initialRotation: (EulerAngles, lookAtHead: Bool) = (EulerAngles(), true), initialScale: SIMD3<Float> = .one, isInteractable: Bool = false, lifetime: Lifetime = .element(count: 1), onRender: @escaping RenderEventHandler = { _ in }, onDisappear: @escaping RenderEventHandler = { _ in }) {
        self.resourceName = resourceName
        self.bundle = bundle
        self.description = description
        self.id = UUID()
        self.isLoaded = false
        self.lifetime = lifetime
        self.initialPosition = initialPosition
        self.initialRotation = initialRotation
        self.initialScale = initialScale
        self.onRender = onRender
        self.onDisappear = onDisappear
        self.isInteractable = isInteractable
    }
    
    public func load() async throws -> EntityElement {
        if !self.isLoaded, self.entity == nil, let resourceName {
            let bundle = self.bundle ?? Fable.defaultBundle
            guard let entity = try? await Entity(named: resourceName, in: bundle) else {
                throw FileError.fileNotFound(fileName: resourceName)
            }
            var copy = self
            copy.entity = entity
            if copy.isInteractable {
                copy.entity?.components.set(GestureComponent(canDrag: true, pivotOnDrag: true, preserveOrientationOnPivotDrag: true, canScale: true, canRotate: true))
            }
            copy.isLoaded = true
            return copy
        } else {
            return self
        }
    }
}

public struct EventElement: Element {
    public let contentData: ContentData = .other
    
    public var lifetime: Lifetime = .instant
    
    public let description: String
    public let id: UUID = UUID()
    
    public var onRender: RenderEventHandler? = nil
    public var onDisappear: RenderEventHandler? = nil
    
    init(description: String = "<Swift Function>", onRender: (@MainActor @escaping @Sendable (FableController) -> Void)) {
        self.description = description
        self.onRender = onRender
    }
}

public enum FileError: Error {
    case fileNotFound(fileName: String)
}
