import AnimalInterface
import DyLibRuntimeLoader

enum NotALogger {}

@DyLibConnect(Animal.self, framework: "CatPlugin", logger: NotALogger.self)
enum BadConn {}
