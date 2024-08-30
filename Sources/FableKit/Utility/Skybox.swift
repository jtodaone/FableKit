import RealityKit

@MainActor
internal func createEmptySkybox() -> Entity {
    let entity = Entity()
    
    let boxShapes = createBoxWithPlanes(1000)
    let collider = CollisionComponent(shapes: boxShapes)

    #if VISUAL_DEBUG
    let meshes = boxShapes.map { MeshResource(shape: $0) }
    var material = UnlitMaterial(color: .magenta)
    material.triangleFillMode = .lines
    
    meshes.forEach { mesh in
        entity.addChild(ModelEntity(mesh: mesh, materials: [material]))
    }
    #endif
    
    entity.components.set(collider)
    entity.components.set(InputTargetComponent())
    
    return entity
}

@MainActor
internal func createBoxWithPlanes(_ size: Float, depth: Float = 0.1) -> [ShapeResource] {
    [
        .generateBox(width: size, height: size, depth: depth).offsetBy(translation: SIMD3(x: 0, y: 0, z: size/2)),
        .generateBox(width: size, height: size, depth: depth).offsetBy(translation: SIMD3(x: 0, y: 0, z: -size/2)),
        .generateBox(width: depth, height: size, depth: size).offsetBy(translation: SIMD3(x: size/2, y: 0, z: 0)),
        .generateBox(width: depth, height: size, depth: size).offsetBy(translation: SIMD3(x: -size/2, y: 0, z: 0)),
        .generateBox(width: size, height: depth, depth: size).offsetBy(translation: SIMD3(x: 0, y: size/2, z: 0)),
        .generateBox(width: size, height: depth, depth: size).offsetBy(translation: SIMD3(x: 0, y: -size/2, z: 0))
    ]
}
