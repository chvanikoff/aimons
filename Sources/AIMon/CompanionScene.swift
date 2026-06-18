import SpriteKit
import AIMonCore

/// Renders a single monster sprite, pixel-crisp, centered, on a clear background,
/// with a gentle idle bob so it feels alive.
final class CompanionScene: SKScene {
    private let cgImage: CGImage
    private var sprite: SKSpriteNode?

    init(image: PixelImage, size: CGSize) {
        guard let cg = image.makeCGImage() else {
            fatalError("Failed to build CGImage from PixelImage")
        }
        self.cgImage = cg
        super.init(size: size)
        self.scaleMode = .resizeFill
        self.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        let texture = SKTexture(cgImage: cgImage)
        texture.filteringMode = .nearest   // crisp pixels, no blur
        let node = SKSpriteNode(texture: texture)
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        layoutSprite(node, in: size)
        addChild(node)
        self.sprite = node
        startIdleAnimation(on: node)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard let sprite else { return }
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        layoutSprite(sprite, in: size)
    }

    /// Scales the sprite to fit the scene while preserving aspect ratio and crisp pixels.
    private func layoutSprite(_ node: SKSpriteNode, in container: CGSize) {
        let tex = node.texture!.size()
        let scale = min(container.width / tex.width, container.height / tex.height)
        node.size = CGSize(width: tex.width * scale, height: tex.height * scale)
    }

    /// A slow, looping vertical bob centered on the resting position (net displacement zero).
    private func startIdleAnimation(on node: SKSpriteNode) {
        let up = SKAction.moveBy(x: 0, y: 3, duration: 0.7)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -3, duration: 0.7)
        down.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([up, down])), withKey: "idle")
    }
}
