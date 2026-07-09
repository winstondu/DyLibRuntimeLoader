struct CommandLineArguments {
    let expectedPluginIDs: [String]
    let paths: [String]
    let showsHelp: Bool

    static func parse(_ arguments: [String]) -> Result<CommandLineArguments, VerificationFailure> {
        var expectedPluginIDs = [String]()
        var paths = [String]()
        var showsHelp = false

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--help", "-h":
                showsHelp = true
            case "--expect-id":
                index += 1
                guard index < arguments.count else {
                    return .failure(VerificationFailure("--expect-id requires a plugin id value"))
                }
                expectedPluginIDs.append(arguments[index])
            default:
                guard !argument.hasPrefix("-") else {
                    return .failure(VerificationFailure("unknown option: \(argument)"))
                }
                paths.append(argument)
            }
            index += 1
        }

        if !showsHelp, paths.isEmpty {
            return .failure(VerificationFailure("no binary or framework paths given"))
        }
        return .success(
            CommandLineArguments(expectedPluginIDs: expectedPluginIDs, paths: paths, showsHelp: showsHelp))
    }
}
