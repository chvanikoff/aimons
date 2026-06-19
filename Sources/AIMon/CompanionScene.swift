import SpriteKit
import AIMonCore

/// Renders one monster sprite, pixel-crisp, with life: a gentle idle (bob + breathing), periodic
/// blinking (eyes-closed frame swap), and brief flourishes when it reacts or speaks.
///
/// Animation channels are kept independent so they never fight: position via additive `moveBy`
/// (bob/talk/react compose cleanly), scale reserved for breathing only. The sprite is fit to ~82%
/// of the window so movement has headroom and never clips.
final class CompanionScene: SKScene {
    private let openCG: CGImage?
    private let closedCG: CGImage?
    private let renderConfig: RenderConfig
    private var sprite: SKSpriteNode?
    private var openTexture: SKTexture?
    private var desiredSize: CGSize = .zero   // laid-out base size; re-asserted after texture swaps
    private let fitFraction: CGFloat = 0.82

    init(image: PixelImage, closedEyesImage: PixelImage?, size: CGSize, renderConfig: RenderConfig = .default) {
        self.openCG = image.makeCGImage()
        self.closedCG = closedEyesImage?.makeCGImage()
        self.renderConfig = renderConfig
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
        if openCG == nil {
            Log.lifecycle.error("CompanionScene: could not build CGImage; rendering empty")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit { Log.lifecycle.debug("CompanionScene released") }

    override func didMove(to view: SKView) {
        guard let openCG else { return }
        let texture = SKTexture(cgImage: openCG)
        texture.filteringMode = .nearest
        openTexture = texture
        let node = SKSpriteNode(texture: texture)
        node.position = CGPoint(x: size.width / 2, y: size.height / 2)
        layoutSprite(node, in: size)
        addChild(node)
        sprite = node
        startIdle(on: node)
        startBlinking(on: node)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        guard let sprite else { return }
        sprite.position = CGPoint(x: size.width / 2, y: size.height / 2)
        layoutSprite(sprite, in: size)
    }

    private func layoutSprite(_ node: SKSpriteNode, in container: CGSize) {
        guard let tex = node.texture else { return }
        let t = tex.size()
        let scale = min(container.width / t.width, container.height / t.height) * fitFraction
        node.size = CGSize(width: t.width * scale, height: t.height * scale)
        desiredSize = node.size
    }

    // MARK: - Idle: bob (position) + breathe (scale) + blink (texture)

    private func startIdle(on node: SKSpriteNode) {
        let a = renderConfig.bobAmplitude
        let d = renderConfig.bobDuration
        let up = SKAction.moveBy(x: 0, y: a, duration: d); up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -a, duration: d); down.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([up, down])), withKey: "bob")

        let inhale = SKAction.scaleX(to: 0.97, y: 1.05, duration: d); inhale.timingMode = .easeInEaseOut
        let exhale = SKAction.scaleX(to: 1.0, y: 1.0, duration: d); exhale.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([inhale, exhale])), withKey: "breathe")
    }

    private func startBlinking(on node: SKSpriteNode) {
        guard let openTexture, let closedCG else { return }
        let closed = SKTexture(cgImage: closedCG)
        closed.filteringMode = .nearest
        let open = openTexture
        // NB: SKAction.setTexture(_:resize:false) still resizes the node to the texture's native
        // size (a SpriteKit gotcha) — which shrank monsters to ~7px. Swap via the property and
        // re-assert the laid-out size instead.
        let blink = SKAction.sequence([
            SKAction.wait(forDuration: 4.5, withRange: 4.0),   // every ~2.5–6.5s, varied
            SKAction.run { [weak self, weak node] in node?.texture = closed; node?.size = self?.desiredSize ?? node?.size ?? .zero },
            SKAction.wait(forDuration: 0.13),
            SKAction.run { [weak self, weak node] in node?.texture = open; node?.size = self?.desiredSize ?? node?.size ?? .zero },
        ])
        node.run(.repeatForever(blink), withKey: "blink")
    }

    // MARK: - Flourishes (additive position hops; compose with the bob, no scale conflict)

    /// An excited little jump — e.g. when another session joins.
    func reactExcited() {
        guard let sprite else { return }
        let jump = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 8, duration: 0.12),
            SKAction.moveBy(x: 0, y: -8, duration: 0.16),
        ])
        sprite.run(jump, withKey: "react")
    }

    /// A brief double-hop while speaking, so a bubble feels "said".
    func reactTalk() {
        guard let sprite else { return }
        let hop = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 4, duration: 0.09),
            SKAction.moveBy(x: 0, y: -4, duration: 0.11),
        ])
        sprite.run(.repeat(hop, count: 2), withKey: "talk")
    }
}
