import Foundation

/// Minimal wrappers around the process standard streams.
///
/// Diagnostics go to standard error so that `--stdout` output can be piped
/// without contamination.
enum StandardStream {

    /// Writes `message` and a newline to standard output.
    static func out(_ message: String) {
        FileHandle.standardOutput.write(Data((message + "\n").utf8))
    }

    /// Writes `message` verbatim to standard output.
    static func outRaw(_ message: String) {
        FileHandle.standardOutput.write(Data(message.utf8))
    }

    /// Writes `message` and a newline to standard error.
    static func error(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
