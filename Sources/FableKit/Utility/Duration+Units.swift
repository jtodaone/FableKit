import Foundation

public extension Duration {
    public static func hours<T: BinaryInteger>(_ hours: T) -> Duration {
        return .minutes(hours * T(60))
    }

    public static func hours(_ hours: Double) -> Duration {
        return .minutes(hours * 60)
    }

    public static func minutes<T: BinaryInteger>(_ minutes: T) -> Duration {
        return .seconds(minutes * T(60))
    }

    public static func minutes(_ minutes: Double) -> Duration {
        return .seconds(minutes * 60)
    }

    public static func frames<T: BinaryInteger>(_ frames: T, fps: Int = 60) -> Duration {
        return .seconds(Double(frames) / Double(fps))
    }
    
    public static func frames(_ frames: Double, fps: Int = 60) -> Duration {
        return .seconds(frames / Double(fps))
    }

    public func hours(_ hours: Double) -> Duration {
        self + .hours(hours)
    }

    public func minutes(_ minutes: Double) -> Duration {
        self + .minutes(minutes)
    }

    public func seconds(_ seconds: Double) -> Duration {
        self + .seconds(seconds)
    }

    public func frames(_ frames: Double, fps: Int = 60) -> Duration {
        self + .frames(frames, fps: fps)
    }
}
