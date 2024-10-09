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

public func Proceed() -> EventElement {
    EventElement(description: "<Proceed>") { context in
        context.next()
    }
}

@MainActor
public struct Media: GroupElement, Loadable {
    public let id: UUID
    public var contentData: ContentData = .timelined
    
    public var onRender: RenderEventHandler? = nil
    public var onDisappear: RenderEventHandler? = nil
    
    public var isLoaded: Bool = false

    var anchorOffset: SIMD3<Float>
    
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
    public var lifetime: Lifetime = .element(count: 1)
    public let initialPosition: Position
    
    internal var mediaEndSink: (any Cancellable)? = nil
    
    public let avPlayer: AVQueuePlayer

    private let playbackRate: Float
    
    internal let avPlayerItem: AVPlayerItem

    public let isVisible: Bool?

    public let proceedOnEnd: Bool
    
    nonisolated public var description: String {
        zip(elements, times).map {
            "\($0.1.seconds.formatted(.number.precision(.fractionLength(2))))s: \($0.0.description)"
        }.joined(separator: "\n")
    }
    
    public init(
        _ url: URL,
        initialPosition: Position = (.zero, false),
        anchorOffset: SIMD3<Float> = .zero,
        playbackRate: Float = 1.0,
        isVisible: Bool? = nil,
        proceedOnEnd: Bool = false,
        @TimelineBuilder events: () -> ([Duration], [any Element])
    ) {
        let videoPlayerItem = AVPlayerItem(url: url)
        self.avPlayerItem = videoPlayerItem
        self.initialPosition = initialPosition
        let events = events()
        
        self._elements = events.1
        self.times = events.0
        
        let player = AVQueuePlayer()
        self.avPlayer = player

        self.playbackRate = playbackRate
        self.isVisible = isVisible
        
        let videoEntity = Entity()
        
        let id = UUID()
        self.id = id
        
        let entityElement = EntityElement(entity: videoEntity, description: "<Media>", initialPosition: initialPosition) { context in
            fatalError("Media file is not loaded")
        }
        
        self.entityElement = entityElement
        
        self.onRender = { context in
            fatalError("Media file is not loaded")
        }

        self.anchorOffset = anchorOffset
        self.proceedOnEnd = proceedOnEnd
    }
    
    func withNewElements(_ newElements: [any Element]) -> Self {
        return Self(from: self, with: newElements)
    }
    
    private init(from previous: Media, with newElements: [any Element]) {
        let id = previous.id
        self.id = id
        self.contentData = previous.contentData
        self._elements = newElements
        let times = previous.times
        self.times = times
        self.lifetime = previous.lifetime
        self.initialPosition = previous.initialPosition
        self.anchorOffset = previous.anchorOffset
        self.playbackRate = previous.playbackRate
        self.proceedOnEnd = previous.proceedOnEnd
        
        let player = AVQueuePlayer()
        let proceedOnEnd = previous.proceedOnEnd
        self.avPlayer = player
        
        let playerItem = previous.avPlayerItem.copy() as! AVPlayerItem
        self.avPlayerItem = playerItem

        if previous.isVisible == nil {
            self.isVisible = playerItem.tracks.contains { $0.assetTrack?.mediaType == .video }
        } else {
            self.isVisible = previous.isVisible
        }
        
        let videoEntity = Entity()
        
        if isVisible ?? false {
            var videoComponent = VideoPlayerComponent(avPlayer: avPlayer)
            videoComponent.desiredViewingMode = .stereo
            videoComponent.desiredImmersiveViewingMode = .full
        
            videoEntity.components.set(videoComponent)
        }
        
        avPlayer.removeAllItems()
        avPlayer.insert(self.avPlayerItem, after: nil)
        
        let entityElement = EntityElement(entity: videoEntity, description: "<MediaEntity>", initialPosition: initialPosition, initialRotation: (.init(), lookAtHead: true)) { context in
            context.cancelBag.append(
                NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: playerItem).sink { _ in
                    context.removeElement(id: id)
                    if proceedOnEnd {
                        context.next()
                    }
                }
            )
        } onDisappear: { context in
            // context.avPlayer.pause()
            // context.avPlayer.removeAllItems()
            // context.clearBoundaryTimeObserver()
        }
        
        self.entityElement = entityElement
        let playbackRate = self.playbackRate
        let isVisible = self.isVisible
        
        self.onRender = { context in
            func entityElementFadeInOutSetup(element: any Element, eventTime: CMTime, elementDuration: Duration) {
                if let entityElement = element as? EntityElement, let fadeInOutDuration = entityElement.fadeInOutDuration {
                    let fadeOutTime = eventTime + elementDuration.cmTime - fadeInOutDuration.out.cmTime
                    player.addBoundaryTimeObserver(forTimes: [NSValue(time: fadeOutTime)], queue: nil) {
                        Task { @MainActor in
                            guard let fadeOutAnimationResource = entityElement.fadeInOutAnimation.out else {
                                return
                            }
                            guard let entity = entityElement.entity else {
                                return
                            }
                            entity.playAnimation(fadeOutAnimationResource, transitionDuration: 0, startsPaused: false)
                        }
                    }
                }
            }
            player.play()
            player.rate = playbackRate
            
            // if isVisible ?? false {
                context.addElement(entityElement)
            // }
            
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
                        entityElementFadeInOutSetup(element: event.0, eventTime: event.1.cmTime, elementDuration: duration)

                        player.addBoundaryTimeObserver(forTimes: [NSValue(time: event.1.cmTime + duration.cmTime)], queue: nil) {
                            Task { @MainActor in
                                context.removeElement(newEvent)
                            }
                        }
                    }
                } else {
                    context.addElement(event.0, ignoreLifetime: true)
                    
                    if case .time(let duration, _) = event.0.lifetime {
                        entityElementFadeInOutSetup(element: event.0, eventTime: event.1.cmTime, elementDuration: duration)

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
                        entityElementFadeInOutSetup(element: event.0, eventTime: event.1.cmTime, elementDuration: duration)
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
                        entityElementFadeInOutSetup(element: event.0, eventTime: event.1.cmTime, elementDuration: duration)
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

    
    public init(_ resource: String, withExtension fileExtension: String = "mp4", in bundle: Bundle? = nil, initialPosition: Position = (.zero, false), anchorOffset: SIMD3<Float> = .zero, playbackRate: Float = 1.0, isVisible: Bool = true, proceedOnEnd: Bool = false, @TimelineBuilder events: () -> ([Duration], [any Element])) {
        let bundle = bundle ?? Fable.defaultBundle
        guard let url = bundle.url(forResource: resource, withExtension: fileExtension) else {
            fatalError("File \(resource) is not found in the bundle \"\(bundle.bundlePath)\"")
        }
        self.init(url, initialPosition: initialPosition, anchorOffset: anchorOffset, playbackRate: playbackRate, isVisible: isVisible, proceedOnEnd: proceedOnEnd, events: events)
    }
    
    internal func play() {
        avPlayer.play()
    }
    
    internal func pause() {
        avPlayer.pause()
    }
}
