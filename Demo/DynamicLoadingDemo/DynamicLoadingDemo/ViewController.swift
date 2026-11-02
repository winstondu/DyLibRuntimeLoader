//
//  ViewController.swift
//  DynamicLoadingDemo
//
//  Created by Winston Du on 17/7/26.
//

import UIKit
import AnimalInterface
import DemoLogging
import Dynasty

@DyLibConnect(Animal.self, framework: "CatImplementation", logger: DebugLogger.self)
enum CatPlugin {}

@DyLibConnect(Animal.self, framework: "MouseImplementation", logger: DebugLogger.self)
enum MousePlugin {}

@DyLibConnect(Animal.self, framework: "DogImplementation", logger: DebugLogger.self)
enum DogPlugin {}

class ViewController: UIViewController {
    @IBOutlet private weak var label: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        label.text = "Not loaded"
    }

    @IBAction private func runCat(_ sender: UIButton) {
        show(CatPlugin.instance)
    }

    @IBAction private func runMouse(_ sender: UIButton) {
        show(MousePlugin.instance)
    }

    @IBAction private func runDog(_ sender: UIButton) {
        show(DogPlugin.instance)
    }

    /// Each tap goes through the connection's proxy; only the first tap per
    /// animal performs a load, which `DebugLogger` reports in Debug builds.
    private func show(_ animal: any Animal) {
        let message = "Animal says: \(animal.speak())"
        label.text = message
        NSLog("%@", message)
    }
}
