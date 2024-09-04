import Foundation

@MainActor
public final class SignalDispatch {
    public static let main = SignalDispatch()
    
    private var subscribers: [any SignalReceiver] = []
    
    private init() {}
    
    public func add(subscriber: any SignalReceiver) {
        subscribers.append(subscriber)
    }
    
    public func remove(subscriber: any SignalReceiver) {
        subscribers = subscribers.filter { $0.id != subscriber.id }
    }
    
    public func broadcastSignal(_ message: Message) {
        subscribers.forEach {
            $0.onReceive(message)
        }
    }
}

public protocol SignalReceiver: Identifiable {
    var id: UUID { get }
    func onReceive(_ message: Message)
}

public enum Message {
    case proceed
    case pauseVideo
    case resumeVideo
}
