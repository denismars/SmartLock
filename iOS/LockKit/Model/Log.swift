//
//  Log.swift
//  SmartLock
//
//  Created by Alsey Coleman Miller on 8/12/18.
//  Copyright © 2018 ColemanCDA. All rights reserved.
//

import Foundation

public func log(_ text: String) {
    
    let date = Date()
    
    DispatchQueue.log.async {
        
        // only print for debug builds
        #if DEBUG
        print(text)
        #endif
        
        let dateString = Log.dateFormatter.string(from: date)
        
        do { try Log.shared.log(dateString + " " + text) }
        catch CocoaError.fileWriteNoPermission {
            // unable to write due to permissions
            if #available(iOS 13, *) {
                assertionFailure("You don’t have permission to save the log file")
            }
        }
        catch { assertionFailure("Could not write log: \(error)") }
    }
}

fileprivate extension Log {
    
    static var custom: Log?
}

public extension Log {
    
    static var shared: Log {
        get { return Log.custom ?? appCache }
        set { Log.custom = newValue }
    }
    
    static let appCache: Log = try! Log.Store.caches.create(date: Date(), bundle: .main)
    
    static var dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "YYYY-MM-dd HH:mm:ss.SSS"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = nil
        return dateFormatter
    }()
}

public struct Log {
    
    public static let fileExtension = "log"
    
    public let url: URL
    
    public init?(url: URL) {
        
        guard url.isFileURL,
            url.pathExtension.lowercased() == Log.fileExtension
            else { return nil }
        
        self.url = url
    }
    
    fileprivate init(unsafe url: URL) {
        
        assert(Log(url: url) != nil, "Invalid url \(url)")
        self.url = url
    }
    
    public var fileName: String {
        return url.lastPathComponent
    }
    
    public func load() throws -> String {
        
        return try String(contentsOf: url)
    }
    
    public func log(_ text: String) throws {
        
        let newLine = "\n" + text
        let data = Data(newLine.utf8)
        try data.append(fileURL: url)
    }
}

private extension Data {
    
    func append(fileURL: URL) throws {
        if let fileHandle = FileHandle(forWritingAtPath: fileURL.path) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(self)
        }
        else {
            try write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Log Store

public extension Log.Store {
    
    private static let subfolder = "logs"
    
    /// Logs in cache directory
    static let caches: Log.Store = Log.Store(directory: .cachesDirectory, subfolder: subfolder)!
    
    /// Logs in documents directory.
    static let documents: Log.Store = Log.Store(directory: .documentDirectory, subfolder: subfolder)!
    
    /// Logs in Lock App Group.
    static let lockAppGroup: Log.Store = Log.Store(appGroup: .lock, subfolder: subfolder)!
}

public extension Log {
    
    final class Store {
        
        public typealias Item = Log
        
        public let folder: URL
        
        public private(set) var items: [Item] {
            get {
                if cachedItems.isEmpty {
                    try! self.load()
                }
                return cachedItems
            }
            set { cachedItems = newValue }
        }
        
        private var cachedItems = [Item]()
        
        internal init(folder: URL) {
            
            self.folder = folder
        }
        
        internal convenience init?(appGroup: AppGroup, subfolder: String? = nil) {
            
            guard let appGroupURL = FileManager.default.containerURL(for: appGroup)
                else { return nil }
            
            self.init(directory: appGroupURL, subfolder: subfolder)
        }
        
        internal convenience init?(directory: FileManager.SearchPathDirectory, subfolder: String? = nil) {
            
            guard let path = NSSearchPathForDirectoriesInDomains(directory, .userDomainMask, true).first
                else { return nil }
            
            let url = URL(fileURLWithPath: path)
            self.init(directory: url, subfolder: subfolder)
        }
        
        internal convenience init?(directory url: URL, subfolder: String? = nil) {
            
            var url = url
            
            if let subfolder = subfolder {
                url.appendPathComponent(subfolder)
                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                if isDirectory.boolValue == false {
                    do { try FileManager.default.createDirectory(at: url,
                                                                 withIntermediateDirectories: true,
                                                                 attributes: nil) }
                    catch { return nil }
                }
            }
            
            self.init(folder: url)
        }
        
        public func load() throws {
            
            let files = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsSubdirectoryDescendants)
            
            let sorted = files
                .lazy
                .map { (url: $0, date: (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast) }
                .lazy
                .sorted(by: { $0.date > $1.date })
                .lazy
                .map { $0.url }
            
            self.cachedItems = sorted
                .compactMap { Item(url: $0) }
        }
        
        private func item(named name: String) -> Item {
            
            let filename = name + "." + Item.fileExtension
            let url = folder.appendingPathComponent(filename)
            let item = Item(unsafe: url)
            return item
        }
        
        @discardableResult
        public func create(_ name: String) throws -> Log {
            
            let item = self.item(named: name)
            return item
        }
        
        @discardableResult
        public func create(date: Date = Date(), bundle: Bundle = .main) throws -> Log {
            
            let name = "\(bundle.bundleIdentifier ?? bundle.bundleURL.lastPathComponent) \(Int(date.timeIntervalSince1970))"
            return try create(name)
        }
        
        @discardableResult
        public func create(metadata: Metadata) throws -> Log {
            return try create(metadata.description)
        }
    }
}

public extension Log {
    
    struct Metadata {
        
        public let bundle: Bundle.Lock
        public let created: Date
    }
}

extension Log.Metadata: CustomStringConvertible {
    
    public var description: String {
        return "\(bundle.rawValue) \(Int(created.timeIntervalSince1970))"
    }
}

public extension Log {
    
    var metadata: Metadata? {
        
        let name = url.lastPathComponent.replacingOccurrences(of: "." + Log.fileExtension, with: "")
        let components = name.components(separatedBy: " ")
        guard components.count == 2,
            let bundleIdentifier = components.first,
            let bundle = Bundle.Lock(rawValue: bundleIdentifier),
            let timeInterval = Int(components[1])
            else { return nil }
        
        let date = Date(timeIntervalSince1970: TimeInterval(timeInterval))
        let metadata = Metadata(bundle: bundle, created: date)
        return metadata
    }
}
