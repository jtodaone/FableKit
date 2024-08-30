import Foundation
import AVFoundation
import AVKit
import RealityKit
import SwiftUI
import Combine

@MainActor
public func Image(named name: String, in bundle: Bundle? = nil, description: String? = nil) -> ViewElement {
    let bundle = bundle ?? Fable.defaultBundle
    return ViewElement(description: description ?? "Image: \(name)") {
        Image(name, bundle: bundle)
    }
}

@MainActor
public func Subtitle(_ content: String, lifetime: Lifetime = .element(count: 1)) -> ViewElement {
    return ViewElement(description: "Subtitle: \(content)", type: .text(content: content), lifetime: lifetime) {
        VStack {
            Spacer()
            Text(content)
                .font(.system(size: 50))
                .foregroundStyle(.white)
                .padding()
                .background(.black)
        }
    }
}

public func Dim(_ level: Double) -> EventElement {
    EventElement(description: "<Dimming to \(level.formatted(.percent.precision(.fractionLength(0))))>") { context in
        context.dimming = level
    }
}

public func WaitAndProceed(for duration: Duration) -> EventElement {
    EventElement(description: "<Wait \(duration.seconds.formatted(.number.precision(.fractionLength(2)))) seconds and proceed>") { context in
        Task {
            try await ContinuousClock().sleep(for: duration)
            context.next()
        }
    }
}

@MainActor
public struct Video: GroupElement, Loadable {
    public let id: UUID
    public var contentData: ContentData = .timelined
    
    public var onRender: RenderEventHandler? = nil
    public var onDisappear: RenderEventHandler? = nil
    
    public var isLoaded: Bool = false
    
    private var _elements: [any Element] = []
    nonisolated public var elements: [any Element] {
        get {
            if isLoaded {
                return _elements + [entityElement]
            } else {
                return _elements
            }
        }
        set {
            _elements = newValue
        }
    }
    internal let entityElement: EntityElement
    
    public let times: [Duration]
    public var lifetime: Lifetime = .indefinite(isOver: false)
    public let initialPosition: (SIMD3<Float>, relativeToHead: Bool)
    
    internal var videoEndSink: (any Cancellable)? = nil
    
    private let avPlayer: AVQueuePlayer
    
//    public var context: FableController?
//    internal let
    internal let avPlayerItem: AVPlayerItem
    
    nonisolated public var description: String {
        zip(elements, times).map {
            "\($0.1.seconds.formatted(.number.precision(.fractionLength(2))))s: \($0.0.description)"
        }.joined(separator: "\n")
    }
    
    public init(_ url: URL, initialPosition: (SIMD3<Float>, relativeToHead: Bool) = (.zero, false), @TimelineBuilder events: () -> ([Duration], [any Element])) {
        let videoPlayerItem = AVPlayerItem(url: url)
        self.avPlayerItem = videoPlayerItem
        self.initialPosition = initialPosition
        let events = events()
        
        self._elements = events.1
        self.times = events.0
        
        let player = AVQueuePlayer()
        self.avPlayer = player
        
        let videoEntity = Entity()
        
        let id = UUID()
        self.id = id
        
        let entityElement = EntityElement(entity: videoEntity, description: "<Video>", initialPosition: initialPosition) { context in
            fatalError("Video is not loaded")
        }
        
        self.entityElement = entityElement
        
        self.onRender = { context in
            fatalError("Video is not loaded")
        }
    }
    
    func withNewElements(_ newElements: [any Element]) -> Self {
        return Self(from: self, with: newElements)
    }
    
    private init(from previous: Video, with newElements: [any Element]) {
        let id = previous.id
        self.id = id
        self.contentData = previous.contentData
        self._elements = newElements
        let times = previous.times
        self.times = times
        self.lifetime = previous.lifetime
        self.initialPosition = previous.initialPosition
        
        let player = AVQueuePlayer()
        
        self.avPlayer = player
//        self.context = previous.context
        
        let playerItem = previous.avPlayerItem.copy() as! AVPlayerItem
        self.avPlayerItem = playerItem
        
        let videoEntity = Entity()
        var videoComponent = VideoPlayerComponent(avPlayer: avPlayer)
        
        videoComponent.desiredViewingMode = .stereo
        videoComponent.desiredImmersiveViewingMode = .full
        
        videoEntity.components.set(videoComponent)
        
        avPlayer.removeAllItems()
        avPlayer.insert(self.avPlayerItem, after: nil)
        
        let entityElement = EntityElement(entity: videoEntity, description: "<Video>", initialPosition: initialPosition) { context in
            context.cancelBag.append(
                NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem).sink { _ in
                    print("video ended")
                    context.removeElement(id: id)
                }
            )
        } onDisappear: { context in
            context.avPlayer.pause()
            context.avPlayer.removeAllItems()
            context.clearBoundaryTimeObserver()
        }
        
        self.entityElement = entityElement
        
        self.onRender = { context in
            player.play()
            
            context.addElement(entityElement)
            
            for event in zip(newElements, times) {
                player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.1.cmTime)], queue: nil) {
                    Task { @MainActor in
                        context.addElement(event.0)
                    }
                }
            }
        }
        
        self.onDisappear = { context in
            context.avPlayer.pause()
            context.avPlayer.removeAllItems()
            context.clearBoundaryTimeObserver()
        }
        
        self.isLoaded = true
    }
    
    public init(_ resource: String, withExtension fileExtension: String = "mp4", in bundle: Bundle? = nil, initialPosition: (SIMD3<Float>, relativeToHead: Bool) = (.zero, false), @TimelineBuilder events: () -> ([Duration], [any Element])) {
        let bundle = bundle ?? Fable.defaultBundle
        guard let url = bundle.url(forResource: resource, withExtension: fileExtension) else {
            fatalError("File is not found in the bundle \"\(bundle.bundlePath)\"")
        }
        self.init(url, initialPosition: initialPosition, events: events)
    }
    
//    public func withContext(_ context: FableController) -> Self {
//        var copy = self
//        copy.context = context
//        return copy
//    }
}
