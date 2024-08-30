import Foundation

extension Fable {
    internal func preloaded(context: FableController) async throws -> Fable {
        var copy = self
        copy.pages = try await pages.map { try await preload(page: $0) }
        return copy
    }
}

extension Page {
    internal func preloaded() async throws -> Page {
        var copy = self
        copy.elements = try await elements.map {
            try await preload(element: $0)
        }
        return copy
    }
}

internal func preload(page: Page) async throws -> Page {
    var copy = page
    copy.elements = try await page.elements.map {
        try await preload(element: $0)
    }
    return copy
}

internal func preload(element: any Element) async throws -> any Element {
    if let loadable = element as? EntityElement {
        var copy = loadable
        copy = try await copy.load()
        return copy
    } else if let loadable = element as? (any GroupElement) {
        return await loadable.withNewElements(try await loadable.elements.map { try await preload(element: $0) })
    } else {
        return element
    }
}

internal func injectContext(page: Page, context: FableController) async -> Page {
    var copy = page
    copy.elements = await page.elements.map { await injectContext(element: $0, context: context) }
    return copy
}

internal func injectContext(element: any Element, context: FableController) async -> any Element {
    if element is any ControllerReferencingElement, let inputElement = (element as? (any ControllerReferencingElement)) {
        return await inputElement.withContext(context)
    } else if let inputElement = element as? (any GroupElement) {
        return await injectContext(element: inputElement, context: context)
    } else {
        return element
    }
}
