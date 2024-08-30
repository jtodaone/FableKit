import Foundation

struct AnyType {
    var metatype: Any.Type
    
    init(_ metatype: Any.Type) {
        self.metatype = metatype
    }
}

extension AnyType: Equatable {
    static func == (lhs: AnyType, rhs: AnyType) -> Bool {
        lhs.metatype == rhs.metatype
    }
}

extension AnyType: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(metatype))
    }
}

//extension Dictionary {
//    subscript(_ key: Any.Type) -> Value? where Key == AnyType {
//        get { self[AnyType(key)] }
//        _modify { yield &self[AnyType(key)] }
//    }
//}
