import SwiftUI
import SpriteKit
import CoreMotion

class BallPhysicsScene: SKScene, SKPhysicsContactDelegate {
    let motionManager = CMMotionManager()
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    var ballTexture: SKTexture?
    var multiplier: Int = 0
    let ballCategory: UInt32 = 0x1 << 0
    let edgeCategory: UInt32 = 0x1 << 1

    override func didMove(to view: SKView) {
        self.physicsWorld.contactDelegate = self
        self.physicsBody = SKPhysicsBody(edgeLoopFrom: self.frame)
        self.physicsBody?.categoryBitMask = edgeCategory
        
        self.backgroundColor = .clear
        feedbackGenerator.prepare()
        
        setupBalls()
        startMotionUpdates()
    }

    private func startMotionUpdates() {
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 0.02
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let data = data else { return }
                self?.physicsWorld.gravity = CGVector(dx: data.acceleration.x * 12, dy: data.acceleration.y * 12)
            }
        }
    }

    func setupBalls() {
        guard let texture = ballTexture else { return }
        
        for _ in 0..<multiplier {
            let ball = SKSpriteNode(texture: texture)
            ball.size = CGSize(width: 44, height: 44)
            ball.position = CGPoint(x: CGFloat.random(in: 50...size.width-50),
                                    y: CGFloat.random(in: 50...size.height-50))
            
            let body = SKPhysicsBody(circleOfRadius: 22)
            body.restitution = 0.5
            body.friction = 0.1
            body.categoryBitMask = ballCategory
            body.contactTestBitMask = ballCategory | edgeCategory
            
            ball.physicsBody = body
            addChild(ball)
        }
    }
    func didBegin(_ contact: SKPhysicsContact) {
        if contact.collisionImpulse > 2 {
            DispatchQueue.main.async {
                self.feedbackGenerator.impactOccurred(intensity: CGFloat(min(contact.collisionImpulse / 10, 1.0)))
            }
        }
    }
}

struct PhysicsBallView<Content: View>: View {
    let multiplier: Int
    let content: Content
    
    init(multiplier: Int, @ViewBuilder content: () -> Content) {
        self.multiplier = multiplier
        self.content = content()
    }
    
    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: createScene(size: proxy.size), options: [.allowsTransparency])
        }
    }
    
    private func createScene(size: CGSize) -> SKScene {
        let scene = BallPhysicsScene(size: size)
        scene.multiplier = multiplier
        scene.scaleMode = .resizeFill
        let renderer = ImageRenderer(content: content.frame(width: 50, height: 50))
        if let uiImage = renderer.uiImage {
            scene.ballTexture = SKTexture(image: uiImage)
        }
        
        return scene
    }
}

#Preview {
    PhysicsBallView(multiplier: 80, content: {
        ZStack {
            Circle()
                .foregroundStyle(.yellow)
            Image(systemName: "brain.fill")
                .font(.title)
                .foregroundStyle(.white)
        }
    })
}
