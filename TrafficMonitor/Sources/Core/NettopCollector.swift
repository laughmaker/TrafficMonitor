import Foundation

public final class NettopCollector: TrafficCollector, @unchecked Sendable {
    private let interval: Int
    private let frameQuietPeriod: TimeInterval
    private let queue = DispatchQueue(label: "com.example.TrafficMonitor.nettop", qos: .utility)
    private let parser: NettopFrameParser
    private let attributor = ProcessTrafficAttributor()
    private let applicationResolver = ProcessApplicationResolver()

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var buffer = Data()
    private var frameLines: [String] = []
    private var flushWorkItem: DispatchWorkItem?
    private var handler: (@Sendable (TrafficSnapshot) -> Void)?
    private var shouldRun = false
    private var droppedInitialFrame = false
    private var restartAttempt = 0

    public init(interval: Int = 2, frameQuietPeriod: TimeInterval = 0.12) {
        self.interval = interval
        self.frameQuietPeriod = frameQuietPeriod
        self.parser = NettopFrameParser(sampleDuration: TimeInterval(interval))
    }

    public func start(handler: @escaping @Sendable (TrafficSnapshot) -> Void) throws {
        var startError: Error?
        queue.sync {
            guard !shouldRun else {
                startError = TrafficCollectorError.alreadyRunning
                return
            }
            self.handler = handler
            shouldRun = true
            do {
                try spawn()
            } catch {
                shouldRun = false
                self.handler = nil
                startError = error
            }
        }
        if let startError { throw startError }
    }

    public func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            shouldRun = false
            process?.terminationHandler = nil
            process?.terminate()
            cleanup()
            process = nil
            handler = nil
        }
    }

    private func spawn() throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/script")
        task.arguments = [
            "-q", "/dev/null",
            "/usr/bin/nettop",
            "-P", "-d", "-L", "0",
            "-J", "bytes_in,bytes_out",
            "-s", String(interval),
            "-c"
        ]

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        task.standardInput = input
        task.standardOutput = output
        task.standardError = errors

        inputPipe = input
        outputPipe = output
        errorPipe = errors
        buffer.removeAll(keepingCapacity: true)
        frameLines.removeAll(keepingCapacity: true)
        droppedInitialFrame = false

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let self else { return }
            self.queue.async { [weak self] in
                self?.consume(data)
            }
        }

        task.terminationHandler = { [weak self] _ in
            guard let self else { return }
            self.queue.async { [weak self] in
                self?.processDidTerminate()
            }
        }

        do {
            try task.run()
            process = task
        } catch {
            cleanup()
            throw TrafficCollectorError.launchFailed(error.localizedDescription)
        }
    }

    private func consume(_ data: Data) {
        restartAttempt = 0
        buffer.append(data)

        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            let line = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                frameLines.append(line)
            }
        }

        scheduleFrameFlush()
    }

    private func scheduleFrameFlush() {
        flushWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushFrame() }
        flushWorkItem = work
        queue.asyncAfter(deadline: .now() + frameQuietPeriod, execute: work)
    }

    private func flushFrame() {
        guard !frameLines.isEmpty else { return }
        let lines = frameLines
        frameLines.removeAll(keepingCapacity: true)

        guard droppedInitialFrame else {
            droppedInitialFrame = true
            return
        }

        let parsedSnapshot = parser.parseFrame(lines)
        let snapshot = attributor.attribute(parsedSnapshot) { [applicationResolver] process in
            applicationResolver.identity(for: process)
        }
        guard !snapshot.processes.isEmpty else { return }
        handler?(snapshot)
    }

    private func processDidTerminate() {
        cleanup()
        process = nil
        guard shouldRun else { return }

        restartAttempt += 1
        let delay = min(pow(2, Double(restartAttempt - 1)) * 0.5, 8)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, shouldRun else { return }
            do {
                try spawn()
            } catch {
                processDidTerminate()
            }
        }
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        flushWorkItem?.cancel()
        flushWorkItem = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
    }
}
