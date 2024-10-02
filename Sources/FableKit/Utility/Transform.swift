import simd
import Spatial

public typealias Position = (position: SIMD3<Float>, anchor: AnchorType)
public typealias Rotation = (rotation: EulerAngles, lookAtHead: Bool)

public indirect enum AnchorType: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        if value { self = .relativeToParent }
        else { self = .world }
    }
    
    public typealias BooleanLiteralType = Bool
    
    case relativeToHead
    case relativeTo(entity: EntityElement)
    case world
    case relativeToParent
}
