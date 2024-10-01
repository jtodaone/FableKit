import simd
import Spatial

public typealias Position = (position: SIMD3<Float>, anchor: PositionAnchor)
public typealias Rotation = (rotation: EulerAngles, lookAtHead: Bool)

public indirect enum PositionAnchor: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        if value { self = .relativeToHead }
        else { self = .world }
    }
    
    public typealias BooleanLiteralType = Bool
    
    case relativeToHead
    case relativeTo(entity: EntityElement)
    case world
    case relativeToParent
}
