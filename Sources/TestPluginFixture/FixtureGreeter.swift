import TestPluginFixtureInterface

struct FixtureGreeter: Greeter {
    func greet(name: String) -> String {
        "Hello, \(name)!"
    }
}
