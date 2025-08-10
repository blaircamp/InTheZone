import Foundation
import SwiftUI
import os.log

enum LogLevel: String, CaseIterable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    
    var priority: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }
}

struct LogEntry {
    let timestamp: Date
    let level: LogLevel
    let source: String
    let message: String
    let metadata: [String: Any]?
    
    func formatted() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestampStr = formatter.string(from: timestamp)
        
        var logLine = "[\(timestampStr)] [\(level.rawValue)] [\(source)] \(message)"
        
        if let metadata = metadata, !metadata.isEmpty {
            if let jsonData = try? JSONSerialization.data(withJSONObject: metadata),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                logLine += " | \(jsonString)"
            }
        }
        
        return logLine
    }
}

final class SessionLogger: ObservableObject {
    static let shared = SessionLogger()
    
    private let fileQueue = DispatchQueue(label: "sessionLogger.fileQueue", qos: .utility)
    private var currentLogFile: FileHandle?
    private var currentLogURL: URL?
    private let logger = Logger(subsystem: "com.inTheZone.debug", category: "SessionLogger")
    
    @Published var isLoggingEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLoggingEnabled, forKey: "debugLoggingEnabled")
            if !isLoggingEnabled {
                stopLogging()
            }
        }
    }
    
    @Published var minimumLogLevel: LogLevel {
        didSet {
            UserDefaults.standard.set(minimumLogLevel.rawValue, forKey: "minimumLogLevel")
        }
    }
    
    private init() {
        self.isLoggingEnabled = UserDefaults.standard.bool(forKey: "debugLoggingEnabled")
        let savedLevel = UserDefaults.standard.string(forKey: "minimumLogLevel")
        self.minimumLogLevel = LogLevel(rawValue: savedLevel ?? "info") ?? .info
        setupLogDirectory()
        cleanupOldLogs()
    }
    
    private func setupLogDirectory() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("Failed to get documents directory")
            return
        }
        
        let logsDirectory = documentsURL.appendingPathComponent("SessionLogs")
        
        if !FileManager.default.fileExists(atPath: logsDirectory.path) {
            do {
                try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
                logger.info("Created logs directory at \(logsDirectory.path)")
            } catch {
                logger.error("Failed to create logs directory: \(error.localizedDescription)")
            }
        }
    }
    
    private func cleanupOldLogs() {
        fileQueue.async { [weak self] in
            self?.performLogCleanup()
        }
    }
    
    private func performLogCleanup() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        
        let logsDirectory = documentsURL.appendingPathComponent("SessionLogs")
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        do {
            let logFiles = try FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])
            
            for fileURL in logFiles {
                if let creationDate = try fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < cutoffDate {
                    try FileManager.default.removeItem(at: fileURL)
                    logger.info("Deleted old log file: \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            logger.error("Failed to cleanup old logs: \(error.localizedDescription)")
        }
    }
    
    func startSessionLogging() {
        guard isLoggingEnabled else { return }
        
        fileQueue.async { [weak self] in
            self?.createSessionLogFile()
            self?.writeSystemInfo()
        }
    }
    
    private func createSessionLogFile() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let filename = "session_\(timestamp).log"
        
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            logger.error("Failed to get documents directory for log file creation")
            return
        }
        
        let logsDirectory = documentsURL.appendingPathComponent("SessionLogs")
        let logFileURL = logsDirectory.appendingPathComponent(filename)
        
        do {
            // Create the file
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
            
            // Open file handle for writing
            currentLogFile = try FileHandle(forWritingTo: logFileURL)
            currentLogURL = logFileURL
            
            logger.info("Created session log file: \(filename)")
            
            // Write header
            let header = "=== InTheZone Session Debug Log ===\n"
            writeToFile(header)
            
        } catch {
            logger.error("Failed to create log file: \(error.localizedDescription)")
        }
    }
    
    private func writeSystemInfo() {
        let systemInfo = [
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "device_model": UIDevice.current.model,
            "system_name": UIDevice.current.systemName,
            "system_version": UIDevice.current.systemVersion,
            "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
            "build_number": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        ]
        
        log(level: .info, source: "SystemInfo", message: "Session started", metadata: systemInfo)
    }
    
    func stopLogging() {
        fileQueue.async { [weak self] in
            self?.closeCurrentLogFile()
        }
    }
    
    private func closeCurrentLogFile() {
        if let logFile = currentLogFile {
            let footer = "\n=== Session Debug Log End ===\n"
            writeToFile(footer)
            
            do {
                try logFile.close()
                logger.info("Closed session log file")
            } catch {
                logger.error("Failed to close log file: \(error.localizedDescription)")
            }
        }
        
        currentLogFile = nil
        currentLogURL = nil
    }
    
    private func writeToFile(_ content: String) {
        guard let logFile = currentLogFile,
              let data = content.data(using: .utf8) else { return }
        
        do {
            try logFile.write(contentsOf: data)
            try logFile.synchronize() // Force write to disk
        } catch {
            logger.error("Failed to write to log file: \(error.localizedDescription)")
        }
    }
    
    func log(level: LogLevel, source: String, message: String, metadata: [String: Any]? = nil) {
        guard isLoggingEnabled, level.priority >= minimumLogLevel.priority else { return }
        
        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            source: source,
            message: message,
            metadata: metadata
        )
        
        // Also log to system console for development
        logger.log(level: OSLogType.info, "\(entry.formatted())")
        
        fileQueue.async { [weak self] in
            let logLine = entry.formatted() + "\n"
            self?.writeToFile(logLine)
        }
    }
    
    func getCurrentLogFileURL() -> URL? {
        return currentLogURL
    }
    
    func getAllLogFiles() -> [URL] {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        
        let logsDirectory = documentsURL.appendingPathComponent("SessionLogs")
        
        do {
            return try FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey])
                .filter { $0.pathExtension == "log" }
                .sorted { file1, file2 in
                    let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                    return date1 > date2 // Most recent first
                }
        } catch {
            logger.error("Failed to get log files: \(error.localizedDescription)")
            return []
        }
    }
}

// Convenience logging methods
extension SessionLogger {
    func debug(_ message: String, source: String = #function, metadata: [String: Any]? = nil) {
        log(level: .debug, source: source, message: message, metadata: metadata)
    }
    
    func info(_ message: String, source: String = #function, metadata: [String: Any]? = nil) {
        log(level: .info, source: source, message: message, metadata: metadata)
    }
    
    func warning(_ message: String, source: String = #function, metadata: [String: Any]? = nil) {
        log(level: .warning, source: source, message: message, metadata: metadata)
    }
    
    func error(_ message: String, source: String = #function, metadata: [String: Any]? = nil) {
        log(level: .error, source: source, message: message, metadata: metadata)
    }
}