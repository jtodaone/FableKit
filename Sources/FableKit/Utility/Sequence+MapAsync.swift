import Foundation

/// Returns an array containing the results of mapping the given closure over the sequence's elements in an asynchronous context.
extension Sequence {
    func map<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            try await values.append(transform(element))
        }

        return values
    }
}

extension MutableCollection {
    mutating func forEach(body: (inout Self.Element) throws -> Void) {
        for index in self.indices {
            try? body(&self[index])
        }
    }
}
