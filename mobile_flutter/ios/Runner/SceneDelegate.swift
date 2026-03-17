import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    if let url = connectionOptions.urlContexts.first?.url {
      _ = (UIApplication.shared.delegate as? AppDelegate)?.handleIncomingURL(
        url,
        source: "scene_will_connect"
      )
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url,
      (UIApplication.shared.delegate as? AppDelegate)?.handleIncomingURL(
        url,
        source: "scene_open_url_context"
      ) == true
    {
      return
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
