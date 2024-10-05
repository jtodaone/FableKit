import Foundation
import SwiftUI
import AVKit
import RealityKit
import Combine
import ARKit

@available(macOS, unavailable)
@Observable
public final class FableController: @unchecked Sendable, SignalReceiver {
    public let id = UUID()
    public var fable: Fable
    
    private var currentPageIndex = 0
    private var currentElementIndex = -1
    
    @MainActor var skybox = createEmptySkybox()
    
    var currentPage: Page { fable.pages[currentPageIndex] }
    
    var currentElement: any Element { currentPage.elements[currentElementIndex] }
    
    var activeElements: [any Element] = []
    
    private var entityElements: [EntityElement] { activeElements.compactMap { $0 as? EntityElement } }
    private var entitiesToAdd: [(EntityElement, ignoreLifetime: Bool)] = []
    private var entitiesToRemove: [EntityElement] = []
    
    private var nonEntitiesToRemove: [any Element] {
        activeElements.filter { $0.lifetime.isOver && !($0 is EntityElement) }
    }
    
    var viewElements: [ViewElement] { activeElements.compactMap { $0 as? ViewElement } }
    
    public var overlayViews: some View {
        ForEach(viewElements.filter { $0.isOverlay }) { view in
            view.body
        }.allowsHitTesting(false)
    }
    
    public var floatingViews: [ViewElement] {
        viewElements.filter { !$0.isOverlay }
    }
    
    public var floatingViewAttachments: some AttachmentContent {
        ForEach(floatingViews) { element in
            Attachment(id: element.id) {
                element.body
            }
        }
    }
    public var floatingViewAttachmentsToAdd: [ViewElement] = []
    
    var timedQueue: [UUID : [Task<Void, Never>]] = [:]
    
    let clock = ContinuousClock()
    
    var boundaryTimeObservers: [Any] = []
    internal var cancelBag: [any Cancellable] = []
    
    var dimming: Double = 1
    
    internal var avPlayer = AVQueuePlayer()
    internal var avPlayerDidPlayToEndTimeNotificationCancellation: AnyCancellable? = nil
    
    var isPreloadComplete = false
    var isReady: Bool = false
    
    var headAnchor: AnchorEntity? = nil
    
    private let session = ARKitSession()
    private let worldInfo = WorldTrackingProvider()
    
    var sceneUpdateSubscription: EventSubscription? = nil
    
    @ObservationIgnored var currentHeadPosition: SIMD3<Float> = .zero
    @ObservationIgnored var currentHeadRotation: simd_float3x3 = .init(0)

    var entityGarbageBag: [(id: Entity.ID, hasBeenCollected: Bool)] = []
    var garbageColleector: Task<Void, any Error>?

    private var realityViewContent: RealityViewContent? = nil
    
    @MainActor
    public init?(fable: Fable) {
        self.fable = fable
        
        SignalDispatch.main.add(subscriber: self)
        
        let session = AVAudioSession.sharedInstance()
        guard let _ = try? session.setCategory(.playback, mode: .moviePlayback) else { return nil }
        
        self.skybox = createEmptySkybox()

        garbageColleector = Task {
            try await garbageCollect()
        }
    }
    
    deinit {
        let id = self.id
        Task {
            await SignalDispatch.main.remove(subscriber: id)
        }
    }

    func garbageCollect() async throws {
        while true {
            await Task.yield()
            try Task.checkCancellation()
            try? await Task.sleep(for: .milliseconds(10))
            if let realityViewContent {
                entityGarbageBag = entityGarbageBag.map { garbage in
                    guard !garbage.hasBeenCollected else { return garbage }
                    if let entity = realityViewContent.entities.first(where: { $0.id == garbage.id }) {
                        realityViewContent.remove(entity)
                        return (garbage.id, true)
                    }
                    return (garbage.id, false)
                }
                entityGarbageBag = entityGarbageBag.filter { !$0.hasBeenCollected }
            }
        }
    }
    
    @MainActor
    public var body: some View {
        RealityView { content, attachments in
            // content.add(self.skybox)
            self.realityViewContent = content
            
            if let attachment = attachments.entity(for: "overlay") {
                let head = AnchorEntity(.head, trackingMode: .once)
                attachment.setPosition(.init(.zero, -1), relativeTo: head)
                head.anchoring.trackingMode = .continuous
                head.addChild(attachment)
                content.add(head)
                self.headAnchor = head
            }
            
            self.sceneUpdateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                guard let anchor = self.worldInfo.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else {
                    return
                }
                
                let toDeviceTransform = anchor.originFromAnchorTransform
                self.currentHeadPosition = toDeviceTransform.translation
                self.currentHeadRotation = toDeviceTransform.upper3x3
            }
            
            self.isReady = true
        } update: { content, attachments in
            for floatingView in self.floatingViewAttachmentsToAdd {
                if let attachment = attachments.entity(for: floatingView.id) {
                    switch floatingView.initialPosition.anchor {
                    case .relativeToHead:
                        let headEntity = Entity()
                        headEntity.setPosition(self.currentHeadPosition, relativeTo: nil)
                        headEntity.setOrientation(simd_quatf(self.currentHeadRotation), relativeTo: nil)
                        attachment.move(to: Transform(translation: floatingView.initialPosition.position), relativeTo: headEntity)
                    case .world:
                        attachment.setPosition(floatingView.initialPosition.position, relativeTo: nil)
                    case .relativeTo(let anchorEntity):
                        break
                    case .relativeToParent:
                        guard
                            let parentID = floatingView.parentID,
                            let parent = self.activeElements.first(where: { $0.id == parentID })
                        else {
                            attachment.setPosition(floatingView.initialPosition.position, relativeTo: nil)
                            break
                        }

                        // if let entityParent = parent as? EntityElement, let entity = entityParent.entity {
                        //     let realPosition = floatingView.initialPosition.position - entityParent.anchorOffset
                        //     attachment.setPosition(floatingView.initialPosition.position, relativeTo: entity)
                        if let videoParent = parent as? Video, let entity = videoParent.entityElement.entity {
                            let realPosition = floatingView.initialPosition.position + videoParent.anchorOffset
                            attachment.setPosition(realPosition, relativeTo: entity)
                        }
                    }
                    
                    if floatingView.initialRotation.lookAtHead {
                        attachment.look(at: self.currentHeadPosition, from: floatingView.initialPosition.position + self.currentHeadPosition, relativeTo: nil)
                        attachment.setOrientation(simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0)), relativeTo: attachment)
                        attachment.setOrientation(simd_quatf(Rotation3D(eulerAngles: floatingView.initialRotation.0)), relativeTo: attachment)
                    } else {
                        attachment.setOrientation(simd_quatf(Rotation3D(eulerAngles: floatingView.initialRotation.0)), relativeTo: attachment)
                    }
                    
                    content.add(attachment)
                }
            }
            
            for entry in self.entitiesToAdd {
                let entityElement = entry.0
                guard let entity = entityElement.entity else { continue }

                if entityElement.isInteractable {
                    entity.enableGesture()
                }
                
                switch entityElement.initialPosition.anchor {
                case .relativeToHead:
                    let headEntity = Entity()
                    headEntity.setPosition(self.currentHeadPosition, relativeTo: nil)
                    headEntity.setOrientation(simd_quatf(self.currentHeadRotation), relativeTo: nil)
                    entity.move(to: Transform(translation: entityElement.initialPosition.position), relativeTo: headEntity)
                case .world:
                    entity.setPosition(entityElement.initialPosition.position, relativeTo: nil)
                case .relativeTo(let anchorEntity):
                    let uuid: UUID = anchorEntity.id;
                    
                    break
                case .relativeToParent:
                    guard
                        let parentID = entityElement.parentID,
                        let parent = self.activeElements.first(where: { $0.id == parentID })
                    else {
                        entity.setPosition(entityElement.initialPosition.position, relativeTo: nil)
                        break    
                    }

                    // if let entityParent = parent as? EntityElement, let parentEntity = entityParent.entity {
                    //     entity.setPosition(entityElement.initialPosition.position, relativeTo: parentEntity)
                    if let videoParent = parent as? Video, let parentEntity = videoParent.entityElement.entity {
                        let realPosition = entityElement.initialPosition.position + videoParent.anchorOffset
                        entity.setPosition(realPosition, relativeTo: parentEntity)
                    }
                }
                
                if entityElement.initialRotation.lookAtHead {
                    entity.look(at: self.currentHeadPosition, from: entityElement.initialPosition.position + self.currentHeadPosition, relativeTo: nil)
                    entity.setOrientation(simd_quatf(angle: Float.pi, axis: SIMD3<Float>(0, 1, 0)), relativeTo: entity)
                    entity.setOrientation(simd_quatf(Rotation3D(eulerAngles: entityElement.initialRotation.0)), relativeTo: entity)
                } else {
                    entity.setOrientation(simd_quatf(Rotation3D(eulerAngles: entityElement.initialRotation.0)), relativeTo: entity)
                }
                
                entity.setScale(entityElement.initialScale, relativeTo: entity)
                
                if case .time(let duration, _) = entityElement.lifetime, !entry.ignoreLifetime {
                    if let fadeInOutDuration = entityElement.fadeInOutDuration {
                        Task {
                            guard let fadeOutAnimationResource = entityElement.fadeInOutAnimation.out else {
                                return
                            }
                            try await Task.sleep(for: duration - fadeInOutDuration.out)
                            entityElement.entity?.playAnimation(fadeOutAnimationResource, transitionDuration: 0, startsPaused: false)
                        }
                    }
                    Task {
                        try await Task.sleep(for: duration)
                        self.entitiesToRemove.append(entityElement)
                        if let id = entityElement.entity?.id {
                            self.entityGarbageBag.append((id, false))
                        }
                    }
                }
                
                content.add(entity)
                if let fadeInAnimation = entityElement.fadeInOutAnimation.in {
                    entityElement.entity?.playAnimation(fadeInAnimation, transitionDuration: 0, startsPaused: false)
                }
                
                Task {
                    self.activeElements.append(entityElement)
                }
                
                if let onRender = entityElement.onRender { onRender(self) }
            }
            
            Task {
                self._entitiesToAdd.removeAll()
            }
            
            for entityElement in self.entitiesToRemove {
                guard entityElement.entity != nil else { continue }
                if let onDisappear = entityElement.onDisappear { onDisappear(self) }
                if let entity = entityElement.entity {
                    content.remove(entity)
                }
                
                Task {
                    self.activeElements.removeAll { $0.id == entityElement.id }
                }
            }
            
            Task {
                self._entitiesToRemove.removeAll()
            }
        } attachments: {
            Attachment(id: "overlay") {
                self.overlayViews
            }
            self.floatingViewAttachments
        }
        .installGestures()
//        .gesture(SpatialTapGesture().targetedToEntity(skybox).onEnded({ _ in
//            self.next()
//        }))
        .preferredSurroundingsEffect(SurroundingsEffect.dim(intensity: dimming))
        .task {
            try? await self.session.run([self.worldInfo])
            do { self.fable = try await self.fable.preloaded(context: self) }
            catch {
                fatalError("Fable Content cannot be Loaded. \(error)")
            }
            
            try? await self.clock.sleep(for: .seconds(1))
            self.next()
        }
    }
    
    @MainActor
    public func next() {
        let currentPage = fable.pages[currentPageIndex]
        if currentPage.elements.count <= currentElementIndex + 1 {
            if fable.pages.count <= currentPageIndex + 1 {
                return
            }
            currentPageIndex += 1
            currentElementIndex = -1
        } else {
            currentElementIndex += 1
        }
        
        activeElements = activeElements.map { $0.lifetimeDecreased }
        
        entitiesToRemove.append(contentsOf: entityElements.filter { element in
            element.lifetime.isOver
        })

        entityGarbageBag.append(contentsOf: entitiesToRemove.compactMap { $0.entity?.id }.map { ($0, false) } )
        
        addElement(currentElement)
        
        for element in nonEntitiesToRemove {
            if let onDisappear = element.onDisappear { onDisappear(self) }
        }
        
        activeElements = activeElements.filter { element in
            if element is EntityElement { return true }
            
            return !self.nonEntitiesToRemove.contains { $0.id == element.id }
        }
    }
    
    @MainActor
    func addElement(_ element: any Element, initialPosition: SIMD3<Float> = .zero, ignoreLifetime: Bool = false) {
        if let entityElement = element as? EntityElement {
            entitiesToAdd.append((entityElement, ignoreLifetime))
        } else if let concurrentElement = element as? ConcurrentElement {
            activeElements.append(concurrentElement)
            if let onRender = concurrentElement.onRender { onRender(self) }
            for element in concurrentElement.elements {
                addElement(element)
            }
            
            if case .time(let duration, _) = concurrentElement.lifetime, !ignoreLifetime {
                addEventToQueue(after: duration, taskID: concurrentElement.id) { context in
                    context.removeElement(concurrentElement)
                }
            }
        } else if let viewElement = element as? ViewElement, !viewElement.isOverlay {
            activeElements.append(viewElement)
            floatingViewAttachmentsToAdd.append(viewElement)
            if let onRender = element.onRender { onRender(self) }
            
            if case .time(let duration, _) = element.lifetime, !ignoreLifetime {
                addEventToQueue(after: duration, taskID: element.id) { context in
                    context.removeElement(element)
                }
            }
        } else {
            activeElements.append(element)
            if let onRender = element.onRender { onRender(self) }
            
            if case .time(let duration, _) = element.lifetime, !ignoreLifetime {
                addEventToQueue(after: duration, taskID: element.id) { context in
                    context.removeElement(element)
                }
            }
        }
    }
    
    @MainActor
    func removeElement(_ element: any Element) {
        if let entityElement = element as? EntityElement {
            entitiesToRemove.append(entityElement)
            
            if let id = entityElement.entity?.id {
                self.entityGarbageBag.append((id, false))
            }
            return
        } else if let concurrentElement = element as? (any GroupElement) {
            for element in concurrentElement.elements {
                removeElement(element)
            }
            if let onDisappear = concurrentElement.onDisappear { onDisappear(self) }
        } else {
            if let onDisappear = element.onDisappear { onDisappear(self) }
        }
        
        activeElements = activeElements.filter {
            $0.id != element.id
        }
    }
    
    @MainActor
    func removeElement(id: UUID) {
        guard let element = activeElements.first(where: { $0.id == id }) else {
            print("cannot find \(id.uuidString)")
            return
        }
        
        removeElement(element)
    }
    
    func addElementToQueue(_ element: any Element, after duration: Duration, taskID: UUID) {
        if !timedQueue.keys.contains(where: { $0 == taskID }) {
            timedQueue[taskID] = []
        }
        
        timedQueue[taskID]!.append(
            Task {
                try? await clock.sleep(for: duration)
                if Task.isCancelled { return }
                await addElement(element)
            }
        )
    }
    
    func addEventToQueue(for element: (any Element)? = nil, after duration: Duration, taskID: UUID, task: @escaping RenderEventHandler) {
        if !timedQueue.keys.contains(where: { $0 == taskID }) {
            timedQueue[taskID] = []
        }
        
        timedQueue[taskID]?.append(
            Task {
                try? await clock.sleep(for: duration)
                if Task.isCancelled { return }
                await task(self)
            }
        )
    }
    
    func cancelQueue(for id: UUID) {
        guard let queue = timedQueue[id] else {
            return
        }
        
        for task in queue {
            task.cancel()
        }
        timedQueue.removeValue(forKey: id)
    }
    
//    func addBoundaryTimeObserver(_ element: any Element, at time: CMTime) {
//        boundaryTimeObservers.append(avPlayer.addBoundaryTimeObserver(forTimes: [NSValue(time: time)], queue: nil) {
//            Task { @MainActor in
//                print("add from boundary observer")
//                self.addElement(element, ignoreLifetime: true)
//            }
//        })
//        
//        if case .time(let duration, _) = element.lifetime {
//            boundaryTimeObservers.append(avPlayer.addBoundaryTimeObserver(forTimes: [NSValue(time: time + duration.cmTime)], queue: nil) {
//                Task { @MainActor in
//                    print("from boundary observer")
//                    self.removeElement(element)
//                }
//            })
//        }
//    }
    
    func clearBoundaryTimeObserver() {
        boundaryTimeObservers.forEach { avPlayer.removeTimeObserver($0) }
    }
    
    public func onReceive(_ message: Message) {
        switch message {
        case .proceed:
            Task { await self.next() }
        case .pauseVideo:
            for video in activeElements.compactMap({ $0 as? Video }) {
                Task { await video.pause() }
            }
        case .resumeVideo:
            for video in activeElements.compactMap({ $0 as? Video }) {
                Task { await video.play() }
            }
        }
    }
}
