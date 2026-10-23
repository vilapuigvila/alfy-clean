import Foundation
import ArgumentParser

/// Removes the DerivedData of every project whose workspace lives inside a (removed) worktree folder.
struct WorktreeClean: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "worktree-clean",
        abstract: "Delete the DerivedData of projects whose workspace is inside <path> (e.g. a git worktree)."
    )

    @Argument(help: "Folder (such as a worktree) whose projects' DerivedData should be deleted.")
    var path: String

    @Flag(name: .long, help: "Skip the yes/no question (for hooks).")
    var yes: Bool = false

    mutating func run() throws {
        let root = (URL(fileURLWithPath: expandTilde(path)).standardizedFileURL.path)
        guard root != "/", root != NSHomeDirectory() else { throw "Refusing to use `\(root.terminalSafe)` as a worktree path." }

        let folders = DerivedDataDiscovery.found
        let matches = folders.flatMap { DerivedDataProjects.projects(in: $0) }
        let targets = DerivedDataProjects.projects(matches, inside: root)
        guard !targets.isEmpty else {
            Print.withColor(.yellow, "No DerivedData found for projects inside \(root.terminalSafe).")
            return
        }

        let list = targets.map { "  • \($0.name.terminalSafe)  \(Print.Color.dim.rawValue)\(($0.workspacePath ?? "").terminalSafe)\(Print.Color.reset.rawValue)" }
        customPrint("DerivedData for projects inside \(root.terminalSafe):\n" + list.joined(separator: "\n"))
        if !yes, !Prompt().yesNo("⚠️  Delete these \(targets.count) folder(s)?") {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        let paths = DerivedDataProjects.deletable(targets.map { $0.path }, allowedFolders: folders)
        let before = DerivedDataProjects.freeSpace()
        let result = runProcess("/bin/rm", ["-rf"] + paths)
        guard result.success else { throw "Command failed with exit code \(result.exitCode): /bin/rm -rf" }
        if let before, let after = DerivedDataProjects.freeSpace() {
            Print.withColor(.green, DerivedDataProjects.freedSpaceMessage(before: before, after: after))
        }
        Print.withColor(.green, "job done! 🍻")
    }
}
