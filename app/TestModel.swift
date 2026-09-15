import AppKit
import SceneKit

// The model and textures are CC0; see Resources/ToyCar-credits.txt.
enum TestModel {
    static func load(from url: URL) throws -> SCNNode {
        let source = try SCNScene(url: url, options: [.checkConsistency: true])
        let container = SCNNode()
        for node in source.rootNode.childNodes {container.addChildNode(node)}
        return container
    }
    static func studio(in scene: SCNScene, camera: SCNNode) {
        camera.camera = SCNCamera();camera.camera?.fieldOfView = 35
        camera.camera?.usesOrthographicProjection = true;camera.camera?.orthographicScale = TestNavigation.initialScale
        camera.camera?.wantsHDR = true;camera.camera?.exposureOffset = 0
        camera.position = SCNVector3(-2.8, 1.6, 4.5);camera.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(camera)
        func area(_ position: SCNVector3, _ intensity: CGFloat, _ color: NSColor) {
            let node = SCNNode();node.light = SCNLight();node.light?.type = .omni
            node.light?.intensity = intensity;node.light?.color = color;node.position = position
            scene.rootNode.addChildNode(node)
        }
        area(SCNVector3(-3, 5, 4), 600, NSColor(calibratedRed: 1, green: 0.94, blue: 0.84, alpha: 1))
        area(SCNVector3(4, 2, -3), 450, NSColor(calibratedRed: 0.7, green: 0.83, blue: 1, alpha: 1))
        // An original softbox environment gives chrome and clear coat broad reflections.
        let environment = NSImage(size: NSSize(width: 512, height: 256), flipped: false) {rect in
            NSColor(calibratedWhite: 0.32, alpha: 1).setFill();rect.fill()
            NSGradient(starting: NSColor(calibratedWhite: 0.72, alpha: 1), ending: NSColor(calibratedWhite: 0.16, alpha: 1))?.draw(in: rect, angle: -90)
            NSColor(calibratedWhite: 1, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 60, y: 90, width: 100, height: 100), xRadius: 15, yRadius: 15).fill()
            NSBezierPath(roundedRect: NSRect(x: 340, y: 100, width: 60, height: 110), xRadius: 12, yRadius: 12).fill()
            return true
        }
        scene.lightingEnvironment.contents = environment;scene.lightingEnvironment.intensity = 0.8
    }
}
