import SpriteKit
import AIMonCore

/// Renders one monster sprite, pixel-crisp, with life: a gentle idle (bob + breathing), periodic
/// blinking, and brief flourishes when it reacts or speaks.
///
/// Position channels are split across a node hierarchy so transient hops can never accumulate
/// drift: a `carrier` node owns the endless, symmetric bob; the `sprite` child rests at `.zero`
/// and runs only the breathing (scale) and the transient hops (position), which reset to `.zero`
/// before each play. (Earlier, additive hops on a single node drifted upward when a rapid second
/// click interrupted the down-leg of the first.) The sprite is fit to ~82% of the window so motion
/// has headroom and never clips.
final class CompanionScene: SKScene {
    private let openCG: CGImage?
    private let closedCG: CGImage?
    private let renderConfig: RenderConfig
    private var carrier: SKNode?
    private var sprite: SKSpriteNode?
    private var openTexture: SKTexture?
    private var closedTexture: SKTexture?
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
        let carrier = SKNode()
        carrier.position = CGPoint(x: size.width / 2, y: size.height / 2)
        addChild(carrier)
        self.carrier = carrier

        let open = SKTexture(cgImage: openCG); open.filteringMode = .nearest
        openTexture = open
        if let closedCG { let c = SKTexture(cgImage: closedCG); c.filteringMode = .nearest; closedTexture = c }

        let node = SKSpriteNode(texture: open)
        node.position = .zero
        carrier.addChild(node)
        sprite = node
        layoutSprite(node, in: size)

        startBob(on: carrier)
        startBreathing(on: node)
        startBlinking(on: node)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        carrier?.position = CGPoint(x: size.width / 2, y: size.height / 2)
        sprite?.position = .zero
        if let sprite { layoutSprite(sprite, in: size) }
    }

    private func layoutSprite(_ node: SKSpriteNode, in container: CGSize) {
        guard let tex = node.texture else { return }
        let t = tex.size()
        let scale = min(container.width / t.width, container.height / t.height) * fitFraction
        node.size = CGSize(width: t.width * scale, height: t.height * scale)
        desiredSize = node.size
    }

    /// Swap to a freshly rendered look (e.g. after evolving). Keeps the laid-out size and updates
    /// the blink frames so the new look persists.
    func setTextures(image: PixelImage, closedEyesImage: PixelImage?) {
        guard let cg = image.makeCGImage() else { return }
        let open = SKTexture(cgImage: cg); open.filteringMode = .nearest
        openTexture = open
        if let ccg = closedEyesImage?.makeCGImage() {
            let c = SKTexture(cgImage: ccg); c.filteringMode = .nearest; closedTexture = c
        }
        sprite?.texture = open
        if let sprite, desiredSize != .zero { sprite.size = desiredSize }
    }

    // MARK: - Idle: bob (carrier position) + breathe (sprite scale) + blink (sprite texture)

    private func startBob(on carrier: SKNode) {
        let a = renderConfig.bobAmplitude
        let d = renderConfig.bobDuration
        let up = SKAction.moveBy(x: 0, y: a, duration: d); up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -a, duration: d); down.timingMode = .easeInEaseOut
        carrier.run(.repeatForever(.sequence([up, down])), withKey: "bob")
    }

    private func startBreathing(on node: SKSpriteNode) {
        let d = renderConfig.bobDuration
        let inhale = SKAction.scaleX(to: 0.97, y: 1.05, duration: d); inhale.timingMode = .easeInEaseOut
        let exhale = SKAction.scaleX(to: 1.0, y: 1.0, duration: d); exhale.timingMode = .easeInEaseOut
        node.run(.repeatForever(.sequence([inhale, exhale])), withKey: "breathe")
    }

    private func startBlinking(on node: SKSpriteNode) {
        guard closedTexture != nil else { return }
        // NB: SKAction.setTexture(_:resize:false) still resizes the node to the texture's native
        // size (a SpriteKit gotcha) — which shrank monsters to ~7px. Swap via the property (reading
        // the current open/closed textures, so an evolution mid-life is honoured) and re-assert size.
        let blink = SKAction.sequence([
            SKAction.wait(forDuration: 4.5, withRange: 4.0),   // every ~2.5–6.5s, varied
            SKAction.run { [weak self, weak node] in
                guard let self, let node else { return }
                if let c = self.closedTexture { node.texture = c }
                if self.desiredSize != .zero { node.size = self.desiredSize }
            },
            SKAction.wait(forDuration: 0.13),
            SKAction.run { [weak self, weak node] in
                guard let self, let node else { return }
                if let o = self.openTexture { node.texture = o }
                if self.desiredSize != .zero { node.size = self.desiredSize }
            },
        ])
        node.run(.repeatForever(blink), withKey: "blink")
    }

    // MARK: - Flourishes (transient position hops; reset to rest first so they can never drift)

    /// An excited little jump — e.g. when another session joins, or a double-click.
    func reactExcited() {
        guard let sprite else { return }
        sprite.removeAction(forKey: "flourish")
        sprite.position = .zero
        let jump = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 8, duration: 0.12),
            SKAction.moveBy(x: 0, y: -8, duration: 0.16),
            SKAction.run { [weak sprite] in sprite?.position = .zero },
        ])
        sprite.run(jump, withKey: "flourish")
    }

    /// A brief double-hop while speaking, so a bubble feels "said".
    func reactTalk() {
        guard let sprite else { return }
        sprite.removeAction(forKey: "flourish")
        sprite.position = .zero
        let hop = SKAction.sequence([
            SKAction.moveBy(x: 0, y: 4, duration: 0.09),
            SKAction.moveBy(x: 0, y: -4, duration: 0.11),
        ])
        sprite.run(.sequence([.repeat(hop, count: 2),
                              SKAction.run { [weak sprite] in sprite?.position = .zero }]),
                   withKey: "flourish")
    }
}
