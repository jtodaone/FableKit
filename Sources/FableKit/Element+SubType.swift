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
    public let initialPosition: Position
    
    internal var videoEndSink: (any Cancellable)? = nil
    
    private let avPlayer: AVQueuePlayer
    
    internal let avPlayerItem: AVPlayerItem
    
    nonisolated public var description: String {
        zip(elements, times).map {
            "\($0.1.seconds.formatted(.number.precision(.fractionLength(2))))s: \($0.0.description)"
        }.joined(separator: "\n")
    }
    
    public init(_ url: URL, initialPosition: Position = (.zero, false), @TimelineBuilder events: () -> ([Duration], [any Element])) {
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
        
        let playerItem = previous.avPlayerItem.copy() as! AVPlayerItem
        self.avPlayerItem = playerItem
        
        let videoEntity = Entity()
        var videoComponent = VideoPlayerComponent(avPlayer: avPlayer)
        
        videoComponent.desiredViewingMode = .stereo
        videoComponent.desiredImmersiveViewingMode = .full
        
        videoEntity.components.set(videoComponent)
        
        avPlayer.removeAllItems()
        avPlayer.insert(self.avPlayerItem, after: nil)
        
        let entityElement = EntityElement(entity: videoEntity, description: "<Video>", initialPosition: initialPosition, initialRotation: (.init(), lookAtHead: true)) { context in
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
            
            let events = zip(newElements, times)
            let initialEvents = events.filter { $0.1.cmTime.value <= 1}
            let observedEvents = events.filter { $0.1.cmTime.value > 1 }
            
            let observedTimedEvents = observedEvents.filter { $0.0.lifetime != .instant }
            let observedInstantEvents = observedEvents.filter { $0.0.lifetime == .instant }.map { ObservedInstantEvent($0) }
            
            for event in initialEvents {
                if let parentReferencingEvent = event.0 as? any ParentReferencingElement {
                    let newEvent = parentReferencingEvent.withParent(id)
                    context.addElement(newEvent, ignoreLifetime: true)
                    
                    if case .time(let duration, _) = event.0.lifetime {
                        player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.1.cmTime + duration.cmTime)], queue: nil) {
                            Task { @MainActor in
                                context.removeElement(newEvent)
                            }
                        }
                    }
                } else {
                    context.addElement(event.0, ignoreLifetime: true)
                    
                    if case .time(let duration, _) = event.0.lifetime {
                        player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.1.cmTime + duration.cmTime)], queue: nil) {
                            Task { @MainActor in
                                context.removeElement(event.0)
                            }
                        }
                    }
                }
            }
            
            for event in observedTimedEvents {
                if let parentReferencingEvent = event.0 as? any ParentReferencingElement {
                    let newEvent = parentReferencingEvent.withParent(id)
                    
                    player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.1.cmTime)], queue: nil) {
                        Task { @MainActor in
                            context.addElement(newEvent, ignoreLifetime: true)
                        }
                    }
                    
                    if case .time(let duration, _) = newEvent.lifetime {
                        player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.1.cmTime + duration.cmTime)], queue: nil) {
                            Task { @MainActor in
                                context.removeElement(newEvent)
                            }
                        }
                    }
                } else {
                    player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.1.cmTime)], queue: nil) {
                        Task { @MainActor in
                            context.addElement(event.0, ignoreLifetime: true)
                        }
                    }
                    
                    if case .time(let duration, _) = event.0.lifetime {
                        player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.1.cmTime + duration.cmTime)], queue: nil) {
                            Task { @MainActor in
                                context.removeElement(event.0)
                            }
                        }
                    }
                }
            }
            
            for event in observedInstantEvents {
                if let parentReferencingEvent = event.event.0 as? any ParentReferencingElement {
                    let newEvent = parentReferencingEvent.withParent(id)
                    
                    player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.event.1.cmTime)], queue: nil) {
                        Task { @MainActor in
                            context.addElement(newEvent, ignoreLifetime: true)
                            await Task.yield()
                            event.hasAppeared = true
                        }
                    }
                    
                    player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.event.1.cmTime + CMTime(value: 1, timescale: 60))], queue: nil) {
                        Task { @MainActor in
                            repeat {
                                try await Task.sleep(for: .milliseconds(10))
                            } while (!event.hasAppeared || player.timeControlStatus == .paused)
                            
                            context.removeElement(id: newEvent.id)
                        }
                    }
                } else {
                    player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.event.1.cmTime)], queue: nil) {
                        Task { @MainActor in
                            context.addElement(event.event.0, ignoreLifetime: true)
                            await Task.yield()
                            event.hasAppeared = true
                        }
                    }
                    
                    player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.event.1.cmTime + CMTime(value: 1, timescale: 60))], queue: nil) {
                        Task { @MainActor in
                            repeat {
                                try await Task.sleep(for: .milliseconds(10))
                            } while (!event.hasAppeared || player.timeControlStatus == .paused)
                            
                            context.removeElement(id: event.event.0.id)
                        }
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
        
        final class ObservedInstantEvent: @unchecked Sendable {
            fileprivate init(_ event: (any Element, Duration), hasAppeared: Bool = false) {
                self.hasAppeared = hasAppeared
                self.event = event
            }
            
            var hasAppeared: Bool = false
            let event: (any Element, Duration)
        }
    }
    
    public init(_ resource: String, withExtension fileExtension: String = "mp4", in bundle: Bundle? = nil, initialPosition: Position = (.zero, false), @TimelineBuilder events: () -> ([Duration], [any Element])) {
        let bundle = bundle ?? Fable.defaultBundle
        guard let url = bundle.url(forResource: resource, withExtension: fileExtension) else {
            fatalError("File is not found in the bundle \"\(bundle.bundlePath)\"")
        }
        self.init(url, initialPosition: initialPosition, events: events)
    }
    
    internal func play() {
        avPlayer.play()
    }
    
    internal func pause() {
        avPlayer.pause()
    }
}
