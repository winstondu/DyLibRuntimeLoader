//
//  SceneDelegate.swift
//  DynamicLoadingDemo
//
//  Created by Winston Du on 17/7/26.
//

import UIKit

@available(iOS 13.0, *)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window : UIWindow?
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let windowScene = scene as? UIWindowScene {
            self.window = UIWindow(windowScene: windowScene)
            let vc = UIStoryboard(name: "Main", bundle: .main).instantiateInitialViewController()
            self.window!.rootViewController = vc
            self.window!.makeKeyAndVisible()
        }
    }
}
   
