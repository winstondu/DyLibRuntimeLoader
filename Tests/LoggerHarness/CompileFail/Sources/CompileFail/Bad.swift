import AnimalInterface
import Dynasty

enum NotALogger {}

@DyLibConnect(Animal.self, framework: "CatPlugin", logger: NotALogger.self)
enum BadConn {}
