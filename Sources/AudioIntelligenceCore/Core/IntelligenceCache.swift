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
        // Sort parameters to ensure deterministic key
        let sortedKeys = parameters.keys.sorted()
        for key in sortedKeys {
            input += "|\(key):\(parameters[key] ?? "")"
        }
        
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Store & Retrieve
    
    public func set<T: Codable>(_ value: T, forKey key: String) async {
        // 1. Memory Store
        memoryCache.setObject(value as AnyObject, forKey: key as NSString)
        
        // 2. Disk Store (Background)
        let directory = self.cacheDirectory
        do {
            let data = try JSONEncoder().encode(value)
            Task.detached(priority: .background) {
                do {
                    let fileURL = directory.appendingPathComponent(key)
                    try data.write(to: fileURL)
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
}
