import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    syncStripePaymentSheetHostWindow(from: scene)
  }

  override func sceneWillEnterForeground(_ scene: UIScene) {
    super.sceneWillEnterForeground(scene)
    syncStripePaymentSheetHostWindow(from: scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    syncStripePaymentSheetHostWindow(from: scene)
  }

  /// stripe_ios 的 `presentPaymentSheet` 仍从 `UIApplication.shared.delegate?.window` 取宿主 VC；
  /// 使用 UIScene 时 `FlutterAppDelegate.window` 往往未赋值，会得到空 VC，进而触发
  /// "Attempt to present ... whose view is not in the window hierarchy"。
  /// 将当前场景的 keyWindow 写回 AppDelegate，使 Stripe 与旧式插件能拿到正确 window。
  private func syncStripePaymentSheetHostWindow(from scene: UIScene) {
    guard let windowScene = scene as? UIWindowScene else { return }
    let window = windowScene.windows.first(where: { $0.isKeyWindow })
      ?? windowScene.windows.first
      ?? self.window
    guard let w = window else { return }
    (UIApplication.shared.delegate as? FlutterAppDelegate)?.window = w
  }
}
