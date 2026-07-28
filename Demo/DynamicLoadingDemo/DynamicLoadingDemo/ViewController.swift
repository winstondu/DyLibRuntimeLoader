//
//  ViewController.swift
//  DynamicLoadingDemo
//
//  Created by Winston Du on 17/7/26.
//

import UIKit
import AnimalInterface
import DyLibRuntimeLoader

@DyLibConnect(Animal.self, framework: "AnimalImplementation")
enum DogPlugin {}

class ViewController: UIViewController {
    @IBOutlet private weak var label: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        label.text = "Not loaded"
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            let message = "Animal says: \(DogPlugin.instance.speak())"
            label.text = message
            NSLog("%@", message)
        }
    }

    @IBAction private func loadAnimal(_ sender: UIButton) {
        let message = "Animal says: \(DogPlugin.instance.speak())"
        label.text = message
        NSLog("%@", message)
    }
}
