import Foundation
import CryptoKit

/// Hybrid Caching System (Memory + Disk) for AudioIntelligence.
/// Optimized for high-throughput DSP calculations.
/// Default Disk Limit: 4GB.
public actor IntelligenceCache {
    
    public static let shared = IntelligenceCache()
    
    private let cacheDirectory: URL
    private let maxDiskSize: Int64 = 4 * 1024 * 1024 * 1024 // 4GB
    private let memoryCache = NSCache<NSString, AnyObject>()
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.cacheDirectory = home.appendingPathComponent("Library/Caches/AudioIntelligence", isDirectory: true)
        
        // Ensure directory exists
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        memoryCache.countLimit = 50 // Keep max 50 objects in memory
    }
    
    // MARK: - Key Generation
    
    public func generateKey(for url: URL, parameters: [String: Any]) -> String {
        var input = url.absoluteString
        // Sort keys to ensure deterministic key naming
        let sortedKeys = parameters.keys.sorted()
        for key in sortedKeys {
            let value = parameters[key]
            // Use String presentation for hashing to handle non-codable 'Any' safely
            input += "|\(key):\(String(describing: value))"
        }
        
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Store & Retrieve
    
    public func set<T: Codable>(_ value: T, forKey key: String) async {
        // 1. Memory Store
        memoryCache.setObject(value as AnyObject, forKey: key as NSString)
        
        do {
            let data = try JSONEncoder().encode(value)
            
            // Capture necessary values to avoid actor isolation issues in detached task
            let fileURL = self.cacheDirectory.appendingPathComponent(key)
            
            Task.detached(priority: .background) {
                do {
                    try data.write(to: fileURL)
                    // Trigger asynchronous cleanup without blocking
                    await IntelligenceCache.shared.enforceDiskLimit()
                } catch {
                    print("Cache write failed: \(error.localizedDescription)")
                }
            }
        } catch {
            print("Encoding failed: \(error.localizedDescription)")
        }
    }
    
    public func get<T: Codable>(forKey key: String) async -> T? {
        // 1. Memory Check
        if let memoryObj = memoryCache.object(forKey: key as NSString) as? T {
            return memoryObj
        }
        
        // 2. Disk Check
        let fileURL = cacheDirectory.appendingPathComponent(key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let value = try JSONDecoder().decode(T.self, from: data)
            
            // Promote to memory
            memoryCache.setObject(value as AnyObject, forKey: key as NSString)
            return value
        } catch {
            return nil
        }
    }
    
    // MARK: - Maintenance
    
    private func enforceDiskLimit() async {
        let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentAccessDateKey, .fileSizeKey],
            options: []
        )
        
        guard let fileList = files else { return }
        
        var currentSize: Int64 = 0
        let sortedFiles = fileList.compactMap { url -> (URL, Date, Int64)? in
            let resource = try? url.resourceValues(forKeys: [.contentAccessDateKey, .fileSizeKey])
            let size = Int64(resource?.fileSize ?? 0)
            currentSize += size
            return (url, resource?.contentAccessDate ?? Date.distantPast, size)
        }.sorted(by: { $0.1 < $1.1 }) // Oldest first
        
        if currentSize > maxDiskSize {
            var reducedSize = currentSize
            for (url, _, size) in sortedFiles {
                if reducedSize <= maxDiskSize { break }
                try? FileManager.default.removeItem(at: url)
                reducedSize -= size
            }
        }
    }
    
    public func clear() async {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    /// Returns the current size of the disk cache in bytes.
    public func currentSize() async -> Int64 {
        let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: []
        )
        guard let fileList = files else { return 0 }
        return fileList.reduce(0) { total, url in
            let resource = try? url.resourceValues(forKeys: [.fileSizeKey])
            return total + Int64(resource?.fileSize ?? 0)
        }
    }
}
