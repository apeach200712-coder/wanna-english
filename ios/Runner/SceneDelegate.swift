import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
	private let flutterEngine = FlutterEngine(name: "main_engine")

	override func scene(
		_ scene: UIScene,
		willConnectTo session: UISceneSession,
		options connectionOptions: UIScene.ConnectionOptions
	) {
		NSLog("[STARTUP_DIAG] iOS SceneDelegate willConnectTo")
		guard let windowScene = scene as? UIWindowScene else {
			return
		}

		flutterEngine.run()
		if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
			appDelegate.configureFlutterEngine(
				flutterEngine,
				messenger: flutterEngine.binaryMessenger)
		}
		registerSceneLifeCycle(with: flutterEngine)

		let flutterViewController = SafeFlutterViewController(
			engine: flutterEngine,
			nibName: nil,
			bundle: nil)
		if let splashViewController = UIStoryboard(name: "LaunchScreen", bundle: nil)
			.instantiateInitialViewController()
		{
			flutterViewController.splashScreenView = splashViewController.view
		}

		window = UIWindow(windowScene: windowScene)
		window?.rootViewController = flutterViewController
		window?.makeKeyAndVisible()

		super.scene(scene, willConnectTo: session, options: connectionOptions)
	}

	override func sceneDidDisconnect(_ scene: UIScene) {
		unregisterSceneLifeCycle(with: flutterEngine)
		super.sceneDidDisconnect(scene)
	}

	override func sceneDidBecomeActive(_ scene: UIScene) {
		NSLog("[STARTUP_DIAG] iOS SceneDelegate didBecomeActive")
		super.sceneDidBecomeActive(scene)
	}
}
