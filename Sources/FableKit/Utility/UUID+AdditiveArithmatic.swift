//import Foundation
//
//extension UUID: @retroactive AdditiveArithmetic {
//    public static var zero: UUID {
//        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
//    }
//    
//    public static func +(_ lhs: UUID, _ rhs: UUID) -> UUID {
//        UUID(uuid: zip(lhs.array, rhs.array).map {
//            return $0.0 &+ $0.1
//        }.uuid)
//    }
//    
//    public static func - (lhs: UUID, rhs: UUID) -> UUID {
//        UUID(uuid: zip(lhs.array, rhs.array).map {
//            return $0.0 &- $0.1
//        }.uuid)
//    }
//}
//
//extension UUID {
//    var array: [UInt8] {
//        return [
//            uuid.0,
//            uuid.1,
//            uuid.2,
//            uuid.3,
//            uuid.4,
//            uuid.5,
//            uuid.6,
//            uuid.7,
//            uuid.8,
//            uuid.9,
//            uuid.10,
//            uuid.11,
//            uuid.12,
//            uuid.13,
//            uuid.14,
//            uuid.15
//        ]
//    }
//}
//
//extension [UInt8] {
//    var uuid: uuid_t {
//        assert(self.count == 16)
//        return (
//            self[0],
//            self[1],
//            self[2],
//            self[3],
//            self[4],
//            self[5],
//            self[6],
//            self[7],
//            self[8],
//            self[9],
//            self[10],
//            self[11],
//            self[12],
//            self[13],
//            self[14],
//            self[15]
//        )
//    }
//}
