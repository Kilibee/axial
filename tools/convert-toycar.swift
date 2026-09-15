// Build-time conversion of the pinned CC0 ToyCar asset; not a general glTF importer.
import AppKit
import SceneKit
import simd
let input = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let json = try JSONSerialization.jsonObject(with: Data(contentsOf: input.appendingPathComponent("ToyCar.gltf"))) as! [String: Any]
let data = try Data(contentsOf: input.appendingPathComponent("ToyCar.bin"))
let accessors = json["accessors"] as! [[String: Any]]
let views = json["bufferViews"] as! [[String: Any]]
func buffer(_ index: Int, components: Int, bytes: Int) -> (Data, Int, Int) {
    let a = accessors[index], v = views[a["bufferView"] as! Int]
    let offset = (v["byteOffset"] as? Int ?? 0) + (a["byteOffset"] as? Int ?? 0)
    let count = a["count"] as! Int, stride = v["byteStride"] as? Int ?? components * bytes
    let end = offset + (count - 1) * stride + components * bytes
    precondition(offset >= 0 && end <= data.count && count > 0)
    return (data.subdata(in: offset..<end), count, stride)
}
func source(_ index: Int, _ semantic: SCNGeometrySource.Semantic, _ components: Int) -> SCNGeometrySource {
    precondition(accessors[index]["componentType"] as! Int == 5126)
    let (bytes, count, stride) = buffer(index, components: components, bytes: 4)
    return SCNGeometrySource(data: bytes, semantic: semantic, vectorCount: count, usesFloatComponents: true, componentsPerVector: components, bytesPerComponent: 4, dataOffset: 0, dataStride: stride)
}
func texture(_ name: String) -> NSImage {
    guard let image = NSImage(contentsOf: input.appendingPathComponent(name)) else {fatalError("Missing texture: \(name)")}
    return image
}
let paint = SCNMaterial();paint.name = "Painted tin and chrome";paint.lightingModel = .physicallyBased
paint.diffuse.contents = texture("ToyCar_basecolor.png")
paint.normal.contents = texture("ToyCar_normal.png")
let orm = texture("ToyCar_occlusion_roughness_metallic.png")
paint.ambientOcclusion.contents = orm;paint.ambientOcclusion.textureComponents = .red
paint.roughness.contents = orm;paint.roughness.textureComponents = .green
paint.metalness.contents = orm;paint.metalness.textureComponents = .blue
paint.emission.contents = texture("ToyCar_emissive.png")
paint.clearCoat.contents = texture("ToyCar_clearcoat.png");paint.clearCoatRoughness.contents = 0.12
paint.isDoubleSided = true
let glass = SCNMaterial();glass.name = "Tinted glass";glass.lightingModel = .physicallyBased
// SceneKit has no glTF transmission extension: approximate it with tinted transparency.
glass.diffuse.contents = NSColor(calibratedRed: 0.35, green: 0.6, blue: 0.45, alpha: 0.25)
glass.roughness.contents = 0.08;glass.metalness.contents = 0.05;glass.transparencyMode = .dualLayer
let scene = SCNScene(), root = SCNNode();scene.rootNode.addChildNode(root)
let meshes = json["meshes"] as! [[String: Any]], nodes = json["nodes"] as! [[String: Any]]
var triangles = 0
for nodeIndex in [0, 2] { // Car and windows; omit the upstream fabric display stand.
    let definition = nodes[nodeIndex], mesh = meshes[definition["mesh"] as! Int]
    let node = SCNNode();node.name = definition["name"] as? String
    let rotation = (definition["rotation"] as! [NSNumber]).map(\.floatValue), scale = (definition["scale"] as! [NSNumber]).map(\.floatValue)
    node.simdOrientation = simd_quatf(ix: rotation[0], iy: rotation[1], iz: rotation[2], r: rotation[3])
    node.simdScale = SIMD3(scale[0], scale[1], scale[2])
    for primitive in mesh["primitives"] as! [[String: Any]] {
        let attributes = primitive["attributes"] as! [String: Int]
        let index = primitive["indices"] as! Int
        let component = accessors[index]["componentType"] as! Int
        precondition(component == 5123 || component == 5125)
        let width = component == 5123 ? 2 : 4
        let (indices, count, _) = buffer(index, components: 1, bytes: width)
        precondition(count % 3 == 0);triangles += count / 3
        let geometry = SCNGeometry(sources: [source(attributes["POSITION"]!, .vertex, 3), source(attributes["NORMAL"]!, .normal, 3), source(attributes["TEXCOORD_0"]!, .texcoord, 2)], elements: [SCNGeometryElement(data: indices, primitiveType: .triangles, primitiveCount: count / 3, bytesPerIndex: width)])
        geometry.materials = [nodeIndex == 0 ? paint : glass]
        node.addChildNode(SCNNode(geometry: geometry))
    }
    root.addChildNode(node)
}
let bounds = root.boundingBox
let low = SIMD3<Float>(Float(bounds.min.x), Float(bounds.min.y), Float(bounds.min.z)), high = SIMD3<Float>(Float(bounds.max.x), Float(bounds.max.y), Float(bounds.max.z))
let extent = high - low, scale = 2.8 / max(extent.x, max(extent.y, extent.z))
root.simdScale = SIMD3(repeating: scale);root.simdPosition = -(low + high) * 0.5 * scale
precondition(scene.write(to: output, options: nil, delegate: nil, progressHandler: nil))
let loaded = try SCNScene(url: output)
var materials = 0
loaded.rootNode.enumerateChildNodes {node, _ in if let material = node.geometry?.firstMaterial {precondition(material.diffuse.contents != nil);materials += 1}}
precondition(materials == 2)
print("Converted ToyCar: \(triangles) triangles, \(materials) materials, centered extent \(extent * scale)")
