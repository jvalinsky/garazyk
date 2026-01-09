# macOS Network Server APIs

## Foundation Framework Networking

### NSURLSession
Best for HTTP/HTTPS clients and REST API communication.

```swift
class HTTPServerHandler: NSObject, URLSessionDataDelegate {
    private let port: Int
    private var urlSession: URLSession!
    
    func start() throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config, 
                               delegate: self, 
                               delegateQueue: nil)
    }
}
```

### NSStream (CFStream)
Best for custom protocol implementations and bidirectional communication.

```swift
class StreamBasedServer: NSObject {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    
    func connectToHost(host: String, port: UInt32) {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(nil as CFAllocator?, 
                                           host as CFString, 
                                           port, 
                                           &readStream, 
                                           &writeStream)
    }
}
```

---

## Network.framework (Modern Approach)

### NWListener for TCP Servers

```swift
import Network

class NWTCPServer {
    private var listener: NWListener?
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.server.network")
    
    init(port: UInt16) {
        self.port = NWEndpoint.Port(rawValue: port)!
    }
    
    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: parameters, on: self.port)
        
        listener?.stateUpdateHandler = { [weak self] state in
            self?.handleListenerStateChange(state)
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        listener?.start(queue: queue)
    }
}
```

### WebSocket Support

```swift
func startWebSocketServer(port: UInt16) throws {
    let parameters = NWParameters.tcp
    let wsOptions = NWProtocolWebSocket.Options()
    wsOptions.autoReplyPing = true
    parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
    
    listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
}
```

---

## Keychain Services

### Basic Keychain Operations

```swift
import Security

struct KeychainService {
    private let service: String
    
    func savePassword(_ password: String, forAccount account: String) throws {
        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: passwordData
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            try updatePassword(passwordData, forAccount: account)
        }
    }
}
```

---

## Security Framework - Cryptographic Operations

### CommonCrypto Integration

```swift
import CommonCrypto

struct CryptoManager {
    func sha256Hash(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    func encryptAES(data: Data, key: Data, iv: Data) throws -> Data {
        var encryptedData = Data(count: data.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0
        
        let status = encryptedData.withUnsafeMutableBytes { encryptedBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCEncrypt),
                                CCAlgorithm(kCCAlgorithmAES),
                                CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count,
                                ivBytes.baseAddress,
                                dataBytes.baseAddress, data.count,
                                encryptedBytes.baseAddress, encryptedData.count,
                                &numBytesEncrypted)
                    }
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw CryptoError.encryptionFailed(status)
        }
        
        encryptedData.count = numBytesEncrypted
        return encryptedData
    }
}
```

---

## LaunchDaemons

### LaunchDaemon Configuration

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.myserver</string>
    
    <key>Program</key>
    <string>/usr/local/bin/myserver</string>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>UserName</key>
    <string>_myserver</string>
    
    <key>ProcessType</key>
    <string>Background</string>
    
    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>1024</integer>
    </dict>
</dict>
</plist>
```

---

## Modern Server Framework: SwiftNIO

SwiftNIO is Apple's cross-platform asynchronous network application framework.

```swift
import NIO

let group = MultiThreadedEventLoopGroup(numberOfThreads: 4)
let bootstrap = ServerBootstrap(group: group)
    .serverSocketOption(.backlog, value: 256)
    .childChannelOption(.socketOption(.so_reuseaddr), value: 1)
    .childChannelOption(.maxMessagesPerRead, value: 16)
    .childChannelInitializer { channel in
        channel.pipeline.addHandler(BackPressureHandler()).flatMap {
            channel.pipeline.addHandler(ChatHandler())
        }
    }

let serverChannel = try bootstrap.bind(host: "127.0.0.1", port: 8080).wait()
```
