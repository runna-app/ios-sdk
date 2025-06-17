import Foundation

class AtomicDictionary<T>
{
    private var internalDictionary:Dictionary<String, T>
    private let queue: DispatchQueue

    static func fromData(_ data: Data, label: String) -> AtomicDictionary<T> {
        let dict = unarchiveData(data) as? [String: T]
        return AtomicDictionary(dict ?? [:], label: label)
    }

    convenience init(label: String = "com.Statsig.AtomicDictionary") {
        self.init([:], label: label)
    }

    internal init(_ initialValues: [String: T] = [:], label: String) {
        queue = DispatchQueue(label: label, attributes: .concurrent)
        internalDictionary = initialValues
    }

    subscript(key: String) -> T? {
        get {
            var value : T?
            self.queue.sync {
                value = self.internalDictionary[key]
            }

            return value
        }

        set {
            setValue(value: newValue, forKey: key)
        }
    }

    func setValue(value: T?, forKey key: String) {
        self.queue.async(flags: .barrier) {
            self.internalDictionary[key] = value
        }
    }
    
    func removeValue(forKey key: String) {
        self.queue.async(flags: .barrier) {
            self.internalDictionary.removeValue(forKey: key)
        }
    }
    
    
    func count() -> Int {
        return self.queue.sync {
            return self.internalDictionary.count
        }
    }

    func keys() -> [String] {
        var keys: [String] = []
        self.queue.sync {
            keys = self.internalDictionary.keys.sorted()
        }
        return keys
    }

    func toData() -> Data? {
        self.queue.sync {
            let dict = self.internalDictionary
            if #available(iOS 11.0, tvOS 11.0, *) {
                guard let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false) else {
                    PrintHandler.log("[Statsig]: Failed create Data from AtomicDictionary")
                    return nil
                }
                return data
            } else {
                let data = NSKeyedArchiver.archivedData(withRootObject: dict)
                return data
            }
        }
    }

    private func dictSnapshotAsync(completion: @escaping (_: [String : T]) -> Void) {
        self.queue.async {
            let dict = self.internalDictionary
            DispatchQueue.global().async {
                completion(dict)
            }
        }
    }

    func toDataAsync(completion: @escaping (_: Data?) -> Void) {
        self.dictSnapshotAsync { dict in
            if #available(iOS 11.0, tvOS 11.0, *) {
                guard let data = try? NSKeyedArchiver.archivedData(withRootObject: dict, requiringSecureCoding: false) else {
                    PrintHandler.log("[Statsig]: Failed create Data from AtomicDictionary")
                    completion(nil)
                    return
                }
                completion(data)
                return
            } else {
                let data = NSKeyedArchiver.archivedData(withRootObject: dict)
                completion(data)
                return
            }
        }
    }

    internal func reset(_ values: [String: T] = [:]) {
        self.queue.async(flags: .barrier) {
            self.internalDictionary = values
        }
    }

    internal func nsDictionary() -> NSDictionary? {
        guard let raw = toData() else {
            return nil
        }

        return unarchiveData(raw) as? NSDictionary
    }
}



#if COCOAPODS && os(watchOS)

fileprivate let allowedClasses: [AnyClass] = [
    NSDictionary.self,
    NSString.self,
    NSArray.self,
    NSNumber.self,
    URLSessionTask.self,
]

fileprivate func unarchiveData(_ data: Data) -> Any? {
    if #available(macOS 10.13, iOS 11.0, watchOS 4.0, tvOS 11.0, *) {
        return try? NSKeyedUnarchiver.unarchivedObject(ofClasses: allowedClasses, from: data)
    } else {
        return try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data)
    }
}

#else

fileprivate func unarchiveData(_ data: Data) -> Any? {
    return try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) 
}

#endif
