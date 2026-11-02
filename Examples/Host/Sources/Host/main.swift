import AnimalInterface
import Dynasty
import Foundation

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let catPath = directory.appendingPathComponent("libCatPlugin.dylib").path
let dogPath = directory.appendingPathComponent("libDogPlugin.dylib").path
let trickPath = directory.appendingPathComponent("libBackflipPlugin.dylib").path

do {
    let cat = try AnimalPluginSpec.load(from: catPath)
    print("Cat: \(cat.speak())")

    let dogLibrary = DyLibLibrary(
        path: dogPath,
        dependencies: [DyLibLibrary(path: trickPath)]
    )
    let dog = try AnimalPluginSpec.load(from: dogLibrary)
    print("Dog: \(dog.speak())")
} catch {
    fputs("Host failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
