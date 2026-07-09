import AnimalInterface
import DyLibPlugin
import UIKit

class ViewController: UIViewController {

    private let manager = PluginManager()
    private var animal: Animal?

    @IBOutlet var lbl: UILabel!

    @IBAction func load(sender: UIButton) {
        do {
            try manager.discoverPlugins()
            try manager.activateAll()
            animal = try manager.instance(of: AnimalContract.self)
            let plugins = manager.registeredManifests
                .map { "\($0.id) \($0.version)" }
                .joined(separator: "\n")
            show(title: "Success", message: "Activated plugins:\n\(plugins)")
        } catch let error as PluginError {
            show(title: "Error", message: error.description)
        } catch {
            show(title: "Error", message: error.localizedDescription)
        }
    }

    @IBAction func speak(sender: UIButton) {
        show(title: "animal.speak()", message: animal?.speak() ?? "Load a plugin first")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        lbl.text = Bundle.main.resourcePath
    }

    private func show(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(.init(title: "Dismiss", style: .cancel))
        present(alert, animated: true)
    }
}
