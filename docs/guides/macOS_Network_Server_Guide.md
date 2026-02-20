# macOS Network Server Application Development Guide

## Table of Contents
1. [Foundation Framework Networking Classes](#foundation-framework-networking-classes)
2. [Network.framework (Modern Approach)](#network-framework-modern-approach)
3. [Bonjour/mDNS Service Discovery](#bonjourmdns-service-discovery)
4. [Keychain Services for Secure Credential Storage](#keychain-services-for-secure-credential-storage)
5. [Security Framework for Cryptographic Operations](#security-framework-for-cryptographic-operations)
6. [System Configuration Framework](#system-configuration-framework)
7. [LaunchDaemons and Background Execution](#launchdaemons-and-background-execution)
8. [Modern Server Frameworks and Patterns](#modern-server-frameworks-and-patterns)

---

## Foundation Framework Networking Classes

### Overview
Apple provides multiple networking APIs within the Foundation framework, including high-level URL loading systems and lower-level stream-based communications.

### NSURLSession
**Best for:** HTTP/HTTPS clients and servers, REST API communication

NSURLSession provides client-side operations with server behavior adaptations:

```swift
import Foundation

class HTTPServerHandler: NSObject, URLSessionDataDelegate {
    private let port: Int
    private var urlSession: URLSession!
    private let responseQueue = DispatchQueue(label: "com.server.response")
    
    init(port: Int) {
        self.port = port
        super.init()
    }
    
    func start() throws {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        
        urlSession = URLSession(configuration: config, 
                               delegate: self, 
                               delegateQueue: nil)
        
        // NSURLSession does not support server sockets directly
        // Use Network.framework or SwiftNIO for server implementation
    }
    
    func urlSession(_ session: URLSession, 
                   dataTask: URLSessionDataTask, 
                   didReceive response: URLResponse, 
                   completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, 
                   dataTask: URLSessionDataTask, 
                   didReceive data: Data) {
        // Process incoming data
        processRequest(data)
    }
    
    private func processRequest(_ data: Data) {
        // Handle incoming request data
    }
}
```

### NSStream (CFStream)
**Best for:** Custom protocol implementations, bidirectional communication

```swift
import Foundation

class StreamBasedServer: NSObject {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var readStream: Unmanaged<CFReadStream>?
    private var writeStream: Unmanaged<CFWriteStream>?
    
    func connectToHost(host: String, port: UInt32) {
        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?
        
        CFStreamCreatePairWithSocketToHost(nil as CFAllocator?, 
                                          host as CFString, 
                                          port, 
                                          &readStream, 
                                          &writeStream)
        
        guard let read = readStream?.takeRetainedValue(),
              let write = writeStream?.takeRetainedValue() else {
            return
        }
        
        self.readStream = read
        self.writeStream = write
        
        let inputStream = read as InputStream
        let outputStream = write as OutputStream
        
        inputStream.delegate = self
        outputStream.delegate = self
        
        inputStream.schedule(in: .main, forMode: .default)
        outputStream.schedule(in: .main, forMode: .default)
        
        inputStream.open()
        outputStream.open()
    }
    
    func sendData(_ data: Data) {
        _ = data.withUnsafeBytes { bytes in
            outputStream?.write(bytes, maxLength: data.count)
        }
    }
}

extension StreamBasedServer: StreamDelegate {
    func stream(_ aStream: Stream, 
               handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            print("Stream opened")
        case .hasBytesAvailable:
            if let inputStream = aStream as? InputStream {
                var buffer = [UInt8](repeating: 0, count: 1024)
                let bytesRead = inputStream.read(&buffer, maxLength: 1024)
                if bytesRead > 0 {
                    let data = Data(bytes: buffer, count: bytesRead)
                    processReceivedData(data)
                }
            }
        case .hasSpaceAvailable:
            print("Can send more data")
        case .errorOccurred:
            print("Stream error: \(aStream.streamError?.localizedDescription ?? "unknown")")
        case .endEncountered:
            print("Stream ended")
            aStream.close()
        default:
            break
        }
    }
    
    private func processReceivedData(_ data: Data) {
        // Process received data
    }
}
```

### CFNetwork (C-based API)
**Best for:** High-performance requirements, C code integration

```c
#include <CoreFoundation/CoreFoundation.h>
#include <sys/socket.h>
#include <netinet/in.h>

void CFNetworkServerExample() {
    int serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in serverAddress;
    serverAddress.sin_family = AF_INET;
    serverAddress.sin_addr.s_addr = INADDR_ANY;
    serverAddress.sin_port = htons(8080);
    
    bind(serverSocket, (struct sockaddr *)&serverAddress, sizeof(serverAddress));
    listen(serverSocket, 5);
    
    // Handle connections in a run loop
    CFSocketContext context = {0, NULL, NULL, NULL, NULL};
    CFSocketRef socket = CFSocketCreateWithNative(NULL, 
                                                   serverSocket, 
                                                   kCFSocketAcceptCallBack, 
                                                   AcceptCallback, 
                                                   &context);
    
    CFRunLoopSourceRef source = CFSocketCreateRunLoopSource(NULL, socket, 0);
    CFRunLoopAddSource(CFRunLoopGetMain(), source, kCFRunLoopCommonModes);
    
    CFRelease(source);
    CFRelease(socket);
}
```

### GCDAsyncSocket Alternatives
Apple recommends native frameworks over GCDAsyncSocket (CocoaAsyncSocket):

```swift
// DispatchSource implementation
class GCDBasedServer {
    private var listenHandle: DispatchSourceReadProtocol?
    private let listenQueue = DispatchQueue(label: "com.server.listen", 
                                            attributes: .concurrent)
    
    func startListening(port: UInt16) {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = in_addr_t(0) // INADDR_ANY
        addr.sin_port = port.bigEndian
        
        let socketFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        
        var on: Int32 = 1
        setsockopt(socketFileDescriptor, SOL_SOCKET, SO_REUSEADDR, &on, 
                  socklen_t(MemoryLayout<Int32>.size))
        
        let bindingResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socketFileDescriptor, sockaddrPtr, 
                    socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        
        listen(socketFileDescriptor, 1024) // backlog of 1024
        
        listenHandle = DispatchSource.makeReadSource(fileDescriptor: socketFileDescriptor, 
                                                     queue: listenQueue)
        
        listenHandle?.setEventHandler { [weak self] in
            self?.handleNewConnection(socketFileDescriptor: socketFileDescriptor)
        }
        
        listenHandle?.setCancelHandler {
            close(socketFileDescriptor)
        }
        
        listenHandle?.resume()
    }
    
    private func handleNewConnection(socketFileDescriptor: Int32) {
        var clientAddr = sockaddr_in()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        
        let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(socketFileDescriptor, sockaddrPtr, &clientAddrLen)
            }
        }
        
        if clientSocket >= 0 {
            let clientSource = DispatchSource.makeReadSource(fileDescriptor: clientSocket, 
                                                             queue: listenQueue)
            clientSource.setEventHandler {
                self.handleClientData(socketFileDescriptor: clientSocket, 
                                     source: clientSource)
            }
            clientSource.setCancelHandler {
                close(clientSocket)
            }
            clientSource.resume()
        }
    }
    
    private func handleClientData(socketFileDescriptor: Int, 
                                  source: DispatchSourceReadProtocol) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = read(socketFileDescriptor, &buffer, buffer.count)
        
        if bytesRead > 0 {
            let data = Data(bytes: buffer, count: bytesRead)
            processClientData(data, socket: socketFileDescriptor)
        } else if bytesRead == 0 {
            source.cancel()
        }
    }
    
    private func processClientData(_ data: Data, socket: Int) {
        // Process client data
    }
}
```

---

## Network.framework (Modern Approach)

### Overview
Network.framework (iOS 13/macOS 10.15+) provides a Swift-friendly API for network communication based on the IETF Transport Services (TAPS) specification.

### NWListener for TCP Servers
```swift
import Foundation
import Network

class NWTCPServer {
    private var listener: NWListener?
    private let port: NWEndpoint.Port
    private let queue = DispatchQueue(label: "com.server.network", qos: .userInitiated)
    private var connections = [NWConnection]()
    private let connectionsQueue = DispatchQueue(label: "com.server.connections")
    
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
    
    private func handleListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            print("Server listening on port \(self.listener?.port?.rawValue ?? 0)")
        case .failed(let error):
            print("Listener failed: \(error)")
        case .cancelled:
            print("Listener cancelled")
        default:
            break
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.processConnection(connection)
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.removeConnection(connection)
            case .cancelled:
                self?.removeConnection(connection)
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        addConnection(connection)
    }
    
    private func addConnection(_ connection: NWConnection) {
        connectionsQueue.async { [weak self] in
            self?.connections.append(connection)
        }
    }
    
    private func removeConnection(_ connection: NWConnection) {
        connectionsQueue.async { [weak self] in
            self?.connections.removeAll { $0 === connection }
        }
    }
    
    private func processConnection(_ connection: NWConnection) {
        receiveMessage(from: connection)
    }
    
    private func receiveMessage(from connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, 
                          maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                let message = String(data: data, encoding: .utf8)
                print("Received: \(message ?? "binary data")")
                self.handleMessage(message, from: connection)
            }
            
            if error == nil && !isComplete {
                self.receiveMessage(from: connection)
            } else if isComplete {
                connection.cancel()
            }
        }
    }
    
    private func handleMessage(_ message: String?, from connection: NWConnection) {
        guard let message = message else { return }
        
        let response = "Echo: \(message)"
        let responseData = Data(response.utf8)
        
        connection.send(content: responseData, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
    }
    
    func stop() {
        listener?.cancel()
        connectionsQueue.async { [weak self] in
            self?.connections.forEach { $0.cancel() }
            self?.connections.removeAll()
        }
    }
}
```

### UDP Server with NWListener
```swift
class NWDatagramServer {
    private var listener: NWListener?
    
    func startUdpServer(port: UInt16) throws {
        let parameters = NWParameters.udp
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("UDP server ready on port \(port)")
            case .failed(let error):
                print("UDP server failed: \(error)")
            default:
                break
            }
        }
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleDatagram(connection)
        }
        
        listener?.start(queue: .global(qos: .userInitiated))
    }
    
    private func handleDatagram(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            if let data = data, !data.isEmpty {
                self?.processDatagram(data, connection: connection)
            }
            
            if error == nil {
                self?.handleDatagram(connection)
            }
        }
        
        connection.start(queue: .global(qos: .userInitiated))
    }
    
    private func processDatagram(_ data: Data, connection: NWConnection) {
        // Process incoming UDP datagram
        print("Received UDP packet: \(data.count) bytes")
    }
    
    func stop() {
        listener?.cancel()
    }
}
```

### WebSocket Support
```swift
class WebSocketServer {
    private var listener: NWListener?
    
    func startWebSocketServer(port: UInt16) throws {
        let parameters = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        
        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleWebSocketConnection(connection)
        }
        
        listener?.start(queue: .global())
    }
    
    private func handleWebSocketConnection(_ connection: NWConnection) {
        guard let wsProtocol = connection.protocolMetadata(definition: NWProtocolWebSocket.definition) 
                as? NWProtocolWebSocket.Metadata else {
            return
        }
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.receiveWebSocketMessage(connection: connection)
            default:
                break
            }
        }
        
        connection.start(queue: .global())
    }
    
    private func receiveWebSocketMessage(connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                self.handleMessage(data, context: context, connection: connection)
            }
            
            if error == nil {
                self.receiveWebSocketMessage(connection: connection)
            }
        }
    }
    
    private func handleMessage(_ data: Data, 
                              context: NWConnection.Context?, 
                              connection: NWConnection) {
        if let wsContext = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) 
                as? NWProtocolWebSocket.Metadata {
            switch wsContext.opcode {
            case .binary:
                print("Binary message received")
            case .text:
                if let text = String(data: data, encoding: .utf8) {
                    print("Text message received: \(text)")
                }
            case .ping:
                print("Ping received")
            case .pong:
                print("Pong received")
            @unknown default:
                break
            }
        }
    }
    
    func sendMessage(_ text: String, connection: NWConnection) {
        let data = Data(text.utf8)
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.Context(metadata: metadata)
        
        connection.send(content: data, context: context, completion: .contentProcessed { error in
            if let error = error {
                print("WebSocket send error: \(error)")
            }
        })
    }
}
```

### Network Monitoring with NWPathMonitor
```swift
class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.server.networkmonitor")
    
    var statusUpdateHandler: ((NWPath.Status) -> Void)?
    
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.statusUpdateHandler?(path.status)
                self?.logPathStatus(path)
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    private func logPathStatus(_ path: NWPath) {
        print("Network path status: \(path.status)")
        print("Is connected: \(path.status == .satisfied)")
        print("Uses interface type: \(path.usesInterfaceType)")
        
        if path.usesInterfaceType(.wifi) {
            print("Connected via WiFi")
        } else if path.usesInterfaceType(.cellular) {
            print("Connected via cellular")
        } else if path.usesInterfaceType(.wiredEthernet) {
            print("Connected via wired ethernet")
        }
        
        print("Available interfaces: \(path.availableInterfaces)")
        print("Is expensive: \(path.isExpensive)")
        print("Is constrained: \(path.isConstrained)")
    }
    
    func stop() {
        monitor.cancel()
    }
}
```

---

## Bonjour/mDNS Service Discovery

### Overview
Bonjour implements DNS-SD and mDNS for zero-configuration service discovery on local networks.

### NSNetService (High-level API)
```swift
import Foundation

class BonjourServer {
    private var service: NetService?
    private var connection: NWConnection?
    
    func publishService(name: String, type: String, domain: String, port: Int) {
        let serviceType = "_\(type)._tcp."
        let serviceDomain = "local."
        
        service = NetService(domain: serviceDomain, 
                            type: serviceType, 
                            name: name, 
                            port: Int32(port))
        
        service?.delegate = self
        service?.publish(options: [])
    }
    
    func stopPublishing() {
        service?.stop()
        service = nil
    }
}

extension BonjourServer: NetServiceDelegate {
    func netServiceDidPublish(_ sender: NetService) {
        print("Service published: \(sender.name).\(sender.type)\(sender.domain)")
    }
    
    func netService(_ sender: NetService, 
                   didNotPublish errorDict: [String: Number]) {
        print("Failed to publish service: \(errorDict)")
    }
}
```

### Service Discovery/Browsing
```swift
class ServiceBrowser {
    private var browser: NetServiceBrowser?
    private var discoveredServices = [NetService]()
    private let browseQueue = DispatchQueue(label: "com.server.browse")
    
    func browseForServices(type: String, domain: String) {
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_\(type)._tcp.", inDomain: domain)
    }
    
    func stopBrowsing() {
        browser?.stop()
        browser = nil
        discoveredServices.removeAll()
    }
}

extension ServiceBrowser: NetServiceBrowserDelegate {
    func netServiceBrowser(_ browser: NetServiceBrowser, 
                          didFind service: NetService, 
                          moreComing: Bool) {
        print("Found service: \(service.name)")
        service.delegate = self
        service.resolve(withTimeout: 10)
        discoveredServices.append(service)
        
        if !moreComing {
            print("Discovery complete. Found \(discoveredServices.count) services")
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, 
                          didRemove service: NetService, 
                          moreComing: Bool) {
        print("Service removed: \(service.name)")
        discoveredServices.removeAll { $0 === service }
        
        if !moreComing {
            print("Update complete")
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, 
                          didNotSearch errorDict: [String: Number]) {
        print("Search failed: \(errorDict)")
    }
}

extension ServiceBrowser: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        print("Resolved service: \(sender.name)")
        print("  Host: \(sender.hostName ?? "unknown")")
        print("  Port: \(sender.port)")
        print("  TXT Record: \(sender.txtRecordData ?? Data())")
    }
    
    func netService(_ sender: NetService, 
                   didNotResolve errorDict: [String: Number]) {
        print("Failed to resolve service \(sender.name): \(errorDict)")
    }
}
```

### DNS Service Discovery API (Low-level)
```c
#include <DNSServiceDiscovery/DNSServiceDiscovery.h>

void DNSServiceDiscoveryExample() {
    DNSServiceRef sdRef;
    DNSServiceErrorType err;
    
    // Register a service
    err = DNSServiceRegister(&sdRef,
                             0,                  // flags
                             0,                  // interface index (all interfaces)
                             "My Server",        // name
                             "_myservice._tcp",  // regtype
                             "local.",           // domain
                             NULL,               // host
                             8080,               // port
                             0,                  // txtLen
                             NULL,               // txtRecord
                             RegistrationCallback,
                             NULL);              // context
    
    if (err == kDNSServiceErr_NoError) {
        DNSServiceProcessResult(sdRef);
    }
}

void DNSSD_API RegistrationCallback(DNSServiceRef sdRef,
                                    DNSServiceFlags flags,
                                    DNSServiceErrorType errorCode,
                                    const char *name,
                                    const char *regtype,
                                    const char *domain,
                                    void *context) {
    if (errorCode == kDNSServiceErr_NoError) {
        printf("Service registered: %s.%s%s\n", name, regtype, domain);
    } else {
        printf("Registration failed: %d\n", errorCode);
    }
    
    DNSServiceRefDeallocate(sdRef);
}

// Browse for services
void BrowseServices() {
    DNSServiceRef sdRef;
    DNSServiceErrorType err;
    
    err = DNSServiceBrowse(&sdRef,
                           0,                  // flags
                           0,                  // interface index
                           "_myservice._tcp",  // regtype
                           "local.",           // domain
                           BrowseCallback,
                           NULL);
    
    if (err == kDNSServiceErr_NoError) {
        DNSServiceProcessResult(sdRef);
    }
}

void DNSSD_API BrowseCallback(DNSServiceRef sdRef,
                              DNSServiceFlags flags,
                              uint32_t interfaceIndex,
                              DNSServiceErrorType errorCode,
                              const char *serviceName,
                              const char *regtype,
                              const char *domain,
                              void *context) {
    if (errorCode == kDNSServiceErr_NoError) {
        printf("Found service: %s.%s%s\n", serviceName, regtype, domain);
        
        // Resolve the service
        DNSServiceRef resolveRef;
        DNSServiceResolve(&resolveRef,
                          0,
                          interfaceIndex,
                          serviceName,
                          regtype,
                          domain,
                          ResolveCallback,
                          NULL);
    }
}
```

### Network.framework Service Discovery
```swift
import Network

class NetworkFrameworkDiscovery {
    private var browser: NWBrowser?
    private var connection: NWConnection?
    
    func browseForServices(type: String) {
        let parameters = NWParameters()
        let serviceType = "_\(type)._tcp"
        
        browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), 
                           using: parameters)
        
        browser?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Browser ready")
            case .failed(let error):
                print("Browser failed: \(error)")
            default:
                break
            }
        }
        
        browser?.browseResultsChangedHandler = { [weak self] results, changes in
            self?.handleBrowseResults(results)
        }
        
        browser?.start(queue: .global())
    }
    
    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        for result in results {
            switch result.endpoint {
            case .service(let name, let type, let domain, _):
                print("Discovered: \(name).\(type)\(domain)")
                connectToService(name: name, type: type, domain: domain)
            default:
                break
            }
        }
    }
    
    private func connectToService(name: String, type: String, domain: String) {
        let endpoint = NWEndpoint.service(name: name, 
                                          type: type, 
                                          domain: domain, 
                                          interface: nil)
        
        connection = NWConnection(to: endpoint, using: .tcp)
        
        connection?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Connected to service")
            case .failed(let error):
                print("Connection failed: \(error)")
            default:
                break
            }
        }
        
        connection?.start(queue: .global())
    }
    
    func stop() {
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }
}
```

---

## Keychain Services for Secure Credential Storage

### Overview
Keychain Services API provides secure storage for passwords, encryption keys, certificates, and sensitive data.

### Basic Keychain Operations
```swift
import Security

struct KeychainService {
    private let service: String
    private let accessGroup: String?
    
    init(service: String, accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }
    
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
        
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            try updatePassword(passwordData, forAccount: account)
        } else if status != errSecSuccess {
            throw KeychainError.unableToSave(status)
        }
    }
    
    func getPassword(forAccount account: String) throws -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            throw KeychainError.unableToRetrieve(status)
        }
        
        return password
    }
    
    func deletePassword(forAccount account: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unableToDelete(status)
        }
    }
    
    private func updatePassword(_ passwordData: Data, forAccount account: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        if let group = accessGroup {
            query[kSecAttrAccessGroup as String] = group
        }
        
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        guard status == errSecSuccess else {
            throw KeychainError.unableToUpdate(status)
        }
    }
}

enum KeychainError: Error {
    case encodingFailed
    case notFound
    case unableToSave(OSStatus)
    case unableToRetrieve(OSStatus)
    case unableToUpdate(OSStatus)
    case unableToDelete(OSStatus)
}
```

### Storing Certificates and Keys
```swift
import Security

struct CertificateKeyManager {
    func importCertificate(_ certificateData: Data, label: String) throws {
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            throw CertificateError.invalidCertificate
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: label
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw CertificateError.importFailed(status)
        }
    }
    
    func importPrivateKey(_ keyData: Data, label: String) throws {
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, 
                                                    keyAttributes as CFDictionary, 
                                                    nil) else {
            throw CertificateError.invalidKey
        }
        
        let addKeyQuery: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecValueRef as String: privateKey,
            kSecAttrLabel as String: label
        ]
        
        let status = SecItemAdd(addKeyQuery as CFDictionary, nil)
        
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw CertificateError.keyImportFailed(status)
        }
    }
    
    func getIdentity(forLabel label: String) throws -> SecIdentity {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess else {
            throw CertificateError.identityNotFound
        }
        
        return item as! SecIdentity
    }
    
    func getCertificateChain(forIdentity identity: SecIdentity) -> [SecCertificate] {
        var certificates = [SecCertificate]()
        var certificate: SecCertificate?
        
        var policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        
        let status = SecIdentityCopyCertificate(identity, &certificate)
        if status == errSecSuccess, let cert = certificate {
            certificates.append(cert)
        }
        
        return certificates
    }
}

enum CertificateError: Error {
    case invalidCertificate
    case importFailed(OSStatus)
    case invalidKey
    case keyImportFailed(OSStatus)
    case identityNotFound
}
```

### Keychain with Biometric Protection
```swift
import Security
import LocalAuthentication

class SecureKeychainStorage {
    func saveWithBiometrics(_ data: Data, 
                           forKey key: String,
                           reason: String) throws {
        let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            nil
        )
        
        guard let access = accessControl else {
            throw BiometricError.accessControlCreationFailed
        }
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrLabel as String: key,
            kSecValueData as String: data,
            kSecAttrAccessControl as String: access
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw BiometricError.saveFailed(status)
        }
    }
    
    func retrieveWithBiometrics(forKey key: String, 
                               reason: String) throws -> Data {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrLabel as String: key,
            kSecReturnData as String: true,
            kSecUseOperationPrompt as String: reason
        ]
        
        query[kSecAttrAccessControl as String] = query.removeValue(forKey: kSecAttrAccessControl as String)
        if let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
            .biometryCurrentSet,
            nil
        ) {
            query[kSecAttrAccessControl as String] = accessControl
        }
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecUserCanceled || status == errSecAuthFailed {
                throw BiometricError.authenticationFailed
            }
            throw BiometricError.retrieveFailed(status)
        }
        
        return data
    }
}

enum BiometricError: Error {
    case accessControlCreationFailed
    case saveFailed(OSStatus)
    case authenticationFailed
    case retrieveFailed(OSStatus)
}
```

### Using Keychain Wrapper Libraries
```swift
// Example with KeychainAccess library
import KeychainAccess

class SecureCredentialManager {
    private let keychain: Keychain
    
    init(service: String) {
        keychain = Keychain(service: service)
            .synchronizable(false)
            .accessibility(.whenUnlockedThisDeviceOnly)
    }
    
    func saveToken(_ token: String, forKey key: String) throws {
        try keychain.set(token, key: key)
    }
    
    func getToken(forKey key: String) throws -> String {
        guard let token = try keychain.get(key) else {
            throw CredentialError.tokenNotFound
        }
        return token
    }
    
    func deleteToken(forKey key: String) throws {
        try keychain.remove(key)
    }
    
    func clearAll() throws {
        try keychain.removeAll()
    }
}

enum CredentialError: Error {
    case tokenNotFound
}

// Using KeychainSwift for simpler operations
import KeychainSwift

class QuickKeychain {
    private let keychain = KeychainSwift()
    
    init() {
        keychain.accessGroup = nil
        keychain.synchronizable = false
    }
    
    func setSecureValue(_ value: String, forKey key: String) -> Bool {
        return keychain.set(value, forKey: key)
    }
    
    func getSecureValue(forKey key: String) -> String? {
        return keychain.get(key)
    }
    
    func deleteValue(forKey key: String) -> Bool {
        return keychain.delete(key)
    }
}
```

---

## Security Framework for Cryptographic Operations

### Overview
Security framework provides cryptographic services including encryption, hashing, digital signatures, and certificate handling.

### CommonCrypto Integration
```swift
import CommonCrypto

struct CryptoManager {
    
    // MARK: - Hashing Functions
    
    func md5Hash(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_MD5(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    func sha256Hash(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA256(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    func sha512Hash(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA512_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA512(bytes.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
    
    // MARK: - Symmetric Encryption (AES)
    
    func encryptAES(data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES256 else {
            throw CryptoError.invalidKeySize
        }
        
        var encryptedData = Data(count: data.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0
        
        let status = encryptedData.withUnsafeMutableBytes { encryptedBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCEncrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            encryptedBytes.baseAddress,
                            encryptedData.count,
                            &numBytesEncrypted
                        )
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
    
    func decryptAES(data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES256 else {
            throw CryptoError.invalidKeySize
        }
        
        var decryptedData = Data(count: data.count + kCCBlockSizeAES128)
        var numBytesDecrypted: size_t = 0
        
        let status = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            decryptedBytes.baseAddress,
                            decryptedData.count,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }
        
        guard status == kCCSuccess else {
            throw CryptoError.decryptionFailed(status)
        }
        
        decryptedData.count = numBytesDecrypted
        return decryptedData
    }
    
    // MARK: - Random Data Generation
    
    func generateRandomBytes(count: Int) -> Data? {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        
        guard status == errSecSuccess else {
            return nil
        }
        
        return Data(bytes)
    }
    
    func generateRandomIV() -> Data? {
        return generateRandomBytes(count: kCCBlockSizeAES128)
    }
    
    func generateSecureKey(size: KeySize) -> Data? {
        return generateRandomBytes(count: size.bitCount / 8)
    }
    
    enum KeySize {
        case aes128, aes256
        
        var bitCount: Int {
            switch self {
            case .aes128: return kCCKeySizeAES128 * 8
            case .aes256: return kCCKeySizeAES256 * 8
            }
        }
    }
    
    enum CryptoError: Error {
        case invalidKeySize
        case encryptionFailed(CCCryptorStatus)
        case decryptionFailed(CCCryptorStatus)
    }
}
```

### HMAC for Message Authentication
```swift
struct HMACManager {
    
    func createHMAC(data: Data, key: Data, algorithm: HMACAlgorithm) -> Data {
        var digest = [UInt8](repeating: 0, count: algorithm.digestLength)
        
        data.withUnsafeBytes { dataBytes in
            key.withUnsafeBytes { keyBytes in
                CCHmac(
                    algorithm.algorithm,
                    keyBytes.baseAddress,
                    key.count,
                    dataBytes.baseAddress,
                    data.count,
                    &digest
                )
            }
        }
        
        return Data(digest)
    }
    
    func verifyHMAC(data: Data, key: Data, algorithm: HMACAlgorithm, expectedHMAC: Data) -> Bool {
        let computedHMAC = createHMAC(data: data, key: key, algorithm: algorithm)
        return computedHMAC == expectedHMAC
    }
    
    enum HMACAlgorithm {
        case md5, sha1, sha224, sha256, sha384, sha512
        
        var algorithm: CCHmacAlgorithm {
            switch self {
            case .md5: return CCHmacAlgorithm(kCCHmacAlgMD5)
            case .sha1: return CCHmacAlgorithm(kCCHmacAlgSHA1)
            case .sha224: return CCHmacAlgorithm(kCCHmacAlgSHA224)
            case .sha256: return CCHmacAlgorithm(kCCHmacAlgSHA256)
            case .sha384: return CCHmacAlgorithm(kCCHmacAlgSHA384)
            case .sha512: return CCHmacAlgorithm(kCCHmacAlgSHA512)
            }
        }
        
        var digestLength: Int {
            switch self {
            case .md5: return Int(CC_MD5_DIGEST_LENGTH)
            case .sha1: return Int(CC_SHA1_DIGEST_LENGTH)
            case .sha224: return Int(CC_SHA224_DIGEST_LENGTH)
            case .sha256: return Int(CC_SHA256_DIGEST_LENGTH)
            case .sha384: return Int(CC_SHA384_DIGEST_LENGTH)
            case .sha512: return Int(CC_SHA512_DIGEST_LENGTH)
            }
        }
    }
}
```

### Certificate and Trust Evaluation
```swift
import Security

struct CertificateManager {
    
    func loadCertificate(from data: Data) throws -> SecCertificate {
        guard let certificate = SecCertificateCreateWithData(nil, data as CFData) else {
            throw CertificateError.invalidData
        }
        return certificate
    }
    
    func getCertificatePublicKey(_ certificate: SecCertificate) throws -> SecKey {
        var trust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        
        let status = SecTrustCreateWithCertificates(certificate, policy, &trust)
        guard status == errSecSuccess, let trust = trust else {
            throw CertificateError.trustCreationFailed(status)
        }
        
        var error: CFError?
        let publicKey = SecTrustCopyKey(trust)
        guard publicKey != nil else {
            throw CertificateError.publicKeyExtractionFailed
        }
        
        return publicKey!
    }
    
    func verifyCertificateChain(_ certificates: [SecCertificate], 
                               anchorCertificates: [SecCertificate]?) -> Bool {
        let policy = SecPolicyCreateBasicX509()
        var trust: SecTrust?
        
        let status = SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust)
        guard status == errSecSuccess, let trust = trust else {
            return false
        }
        
        if let anchors = anchorCertificates {
            SecTrustSetAnchorCertificates(trust, anchors as CFArray)
            SecTrustSetAnchorOnly(trust, true)
        }
        
        var error: CFError?
        return SecTrustEvaluateWithError(trust, &error)
    }
    
    func createSelfSignedCertificate(name: String, 
                                    daysValid: Int,
                                    keySize: Int = 2048) throws -> (certificate: Data, privateKey: Data) {
        // Note: Full implementation requires OpenSSL or similar
        // This is a simplified example
        let privateKey = try generateRSAKey(size: keySize)
        let certificate = try createCertificate(for: privateKey, commonName: name, daysValid: daysValid)
        
        return (certificate, privateKey)
    }
    
    private func generateRSAKey(size: Int) throws -> Data {
        // Implementation would use SecKeyGeneratePair
        throw CertificateError.notImplemented
    }
    
    private func createCertificate(for privateKey: Data, commonName: String, daysValid: Int) throws -> Data {
        throw CertificateError.notImplemented
    }
    
    enum CertificateError: Error {
        case invalidData
        case trustCreationFailed(OSStatus)
        case publicKeyExtractionFailed
        case notImplemented
    }
}
```

### TLS/SSL Configuration
```swift
import Security

struct TLSManager {
    
    func createServerTLSConfiguration(certificatePath: String, 
                                     keyPath: String) throws -> TLSConfiguration {
        let certificateData = try Data(contentsOf: URL(fileURLWithPath: certificatePath))
        let keyData = try Data(contentsOf: URL(fileURLWithPath: keyPath))
        
        var certificate: SecCertificate?
        certificate = SecCertificateCreateWithData(nil, certificateData as CFData)
        
        var privateKey: SecKey?
        privateKey = SecKeyCreateWithData(keyData as CFData, [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate
        ] as CFDictionary)
        
        guard let cert = certificate, let key = privateKey else {
            throw TLSError.invalidCertificateOrKey
        }
        
        var identity: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(nil, cert, &identity)
        guard identityStatus == errSecSuccess, let identity = identity else {
            throw TLSError.identityCreationFailed(identityStatus)
        }
        
        return TLSConfiguration(identity: identity, certificate: cert)
    }
    
    func createClientTLSConfiguration(verifyServer: Bool = true) -> TLSConfiguration {
        return TLSConfiguration(verifyServer: verifyServer)
    }
    
    struct TLSConfiguration {
        let identity: SecIdentity?
        let certificate: SecCertificate?
        let verifyServer: Bool
        
        init(identity: SecIdentity? = nil, certificate: SecCertificate? = nil, verifyServer: Bool = true) {
            self.identity = identity
            self.certificate = certificate
            self.verifyServer = verifyServer
        }
        
        func apply(to stream: InputStream & OutputStream) throws {
            let settings: [NSString: Any] = [
                kCFStreamSSLValidatesCertificateChain: verifyServer,
                kCFStreamSSLLevel: kCFStreamSocketSecurityLevelTLSv1_2,
                kCFStreamSSLPeerName: kCFNull
            ]
            
            stream.setProperty(settings, forKey: .socketSecurityLevelKey as Stream.PropertyKey)
            
            if let identity = identity, let cert = certificate {
                stream.setProperty(identity, forKey: .kCFStreamPropertySocketSecurityLevel as Stream.PropertyKey)
            }
        }
    }
    
    enum TLSError: Error {
        case invalidCertificateOrKey
        case identityCreationFailed(OSStatus)
        case configurationFailed
    }
}
```

---

## System Configuration Framework

### Overview
System Configuration framework provides APIs for network configuration, reachability monitoring, and network state management.

### Network Reachability
```swift
import SystemConfiguration

class NetworkReachability {
    private var reachabilityRef: SCNetworkReachability?
    
    init?(hostname: String? = nil) {
        if let host = hostname {
            reachabilityRef = SCNetworkReachabilityCreateWithName(nil, host)
        } else {
            var zeroAddress = sockaddr_in()
            zeroAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            zeroAddress.sin_family = sa_family_t(AF_INET)
            
            reachabilityRef = withUnsafePointer(to: &zeroAddress) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    SCNetworkReachabilityCreateWithAddress(nil, sockaddrPtr)
                }
            }
        }
        
        guard let ref = reachabilityRef else {
            return nil
        }
    }
    
    func startMonitoring() {
        var context = SCNetworkReachabilityContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        
        SCNetworkReachabilitySetCallback(reachabilityRef!, { _, flags, info in
            guard let info = info else { return }
            let reachability = Unmanaged<NetworkReachability>.fromOpaque(info).takeUnretainedValue()
            reachability.notifyStatusChanged(flags: flags)
        }, &context)
        
        SCNetworkReachabilityScheduleWithRunLoop(reachabilityRef!, 
                                                 CFRunLoopGetMain(), 
                                                 CFRunLoopMode.defaultMode.rawValue)
    }
    
    func stopMonitoring() {
        if let ref = reachabilityRef {
            SCNetworkReachabilityUnscheduleFromRunLoop(ref, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        }
    }
    
    private func notifyStatusChanged(flags: SCNetworkReachabilityFlags) {
        let status = getCurrentStatus(flags: flags)
        NotificationCenter.default.post(name: .networkReachabilityChanged, 
                                       object: nil, 
                                       userInfo: ["status": status])
    }
    
    func getCurrentStatus(flags: SCNetworkReachabilityFlags) -> NetworkStatus {
        if !flags.contains(.reachable) {
            return .notReachable
        }
        
        if flags.contains(.connectionRequired) && !flags.contains(.connectionOnTraffic) {
            return .notReachable
        }
        
        if flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic) {
            if !flags.contains(.interventionRequired) {
                return .reachableViaWiFi
            }
        }
        
        if flags.contains(.isWWAN) {
            return .reachableViaCellular
        }
        
        return .reachableViaWiFi
    }
    
    func isReachable() -> Bool {
        guard let ref = reachabilityRef else { return false }
        var flags = SCNetworkReachabilityFlags()
        SCNetworkReachabilityGetFlags(ref, &flags)
        return getCurrentStatus(flags: flags).isReachable
    }
    
    enum NetworkStatus {
        case notReachable
        case reachableViaWiFi
        case reachableViaCellular
        
        var isReachable: Bool {
            switch self {
            case .notReachable: return false
            default: return true
            }
        }
    }
}

extension Notification.Name {
    static let networkReachabilityChanged = Notification.Name("NetworkReachabilityChanged")
}
```

### Network Configuration
```swift
import SystemConfiguration

class NetworkConfigurationManager {
    
    func getCurrentNetworkConfiguration() -> [String: Any]? {
        guard let store = SCDynamicStoreCreate(nil, "NetworkConfig" as CFString, nil, nil) else {
            return nil
        }
        
        let ipv4Key = "State:/Network/Service/.*/IPv4"
        let ipv6Key = "State:/Network/Service/.*/IPv6"
        let dnsKey = "State:/Network/Service/.*/DNS"
        
        guard let ipv4Keys = SCDynamicStoreCopyKeyList(store, ipv4Key as CFString) else {
            return nil
        }
        
        var config: [String: Any] = [:]
        
        let keys = ipv4Keys as? [String] ?? []
        for key in keys {
            if let dynamicStore = SCDynamicStoreCopyValue(store, key as CFString) {
                config[key] = dynamicStore
            }
        }
        
        return config
    }
    
    func getActiveInterface() -> (name: String, type: String)? {
        guard let store = SCDynamicStoreCreate(nil, "InterfaceInfo" as CFString, nil, nil) else {
            return nil
        }
        
        let pattern = "State:/Network/Interface/.*/IPv[46]"
        guard let keys = SCDynamicStoreCopyKeyList(store, pattern as CFString) else {
            return nil
        }
        
        for key in keys as? [String] ?? [] {
            if let keyString = key as String?,
               let range = keyString.range(of: "Network/Interface/"),
               let endRange = keyString[range.upperBound...].range(of: "/") {
                let interfaceName = String(keyString[range.upperBound..<endRange.lowerBound])
                let ipVersion = keyString.contains("IPv6") ? "IPv6" : "IPv4"
                return (interfaceName, ipVersion)
            }
        }
        
        return nil
    }
    
    func setDNSServers(_ servers: [String], for interface: String? = nil) throws {
        // Requires root privileges - typically done via launchd or helper tool
        throw NetworkConfigError.requiresRootPrivileges
    }
    
    func getDNSServers() -> [String] {
        var resInfo: ResolverInfo?
        if #available(macOS 12.0, *) {
            // Use newer API if available
        }
        
        // Fallback: parse resolv.conf
        let path = "/etc/resolv.conf"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return []
        }
        
        var servers: [String] = []
        for line in content.components(separatedBy: .newlines) {
            if line.hasPrefix("nameserver ") {
                let server = line.replacingOccurrences(of: "nameserver ", with: "").trimmingCharacters(in: .whitespaces)
                servers.append(server)
            }
        }
        
        return servers
    }
    
    enum NetworkConfigError: Error {
        case requiresRootPrivileges
        case configurationFailed
    }
}
```

### Proxies and Network Settings
```swift
import SystemConfiguration

class ProxyConfigurationManager {
    
    func getProxyConfiguration() -> ProxySettings {
        var settings = ProxySettings()
        
        guard let store = SCDynamicStoreCreate(nil, "ProxyConfig" as CFString, nil, nil) else {
            return settings
        }
        
        let proxyKeys = [
            "State:/Network/Global/Proxies",
            "State:/Network/Service/.*/Proxies"
        ]
        
        for keyPattern in proxyKeys {
            guard let keys = SCDynamicStoreCopyKeyList(store, keyPattern as CFString) else {
                continue
            }
            
            for key in keys as? [String] ?? [] {
                if let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] {
                    parseProxySettings(value, into: &settings)
                }
            }
        }
        
        return settings
    }
    
    private func parseProxySettings(_ dict: [String: Any], into settings: inout ProxySettings) {
        if let httpEnabled = dict["HTTPEnable"] as? Int, httpEnabled == 1 {
            settings.httpEnabled = true
            settings.httpServer = dict["HTTPProxy"] as? String ?? ""
            settings.httpPort = (dict["HTTPPort"] as? Int) ?? 0
        }
        
        if let httpsEnabled = dict["HTTPSEnable"] as? Int, httpsEnabled == 1 {
            settings.httpsEnabled = true
            settings.httpsServer = dict["HTTPSProxy"] as? String ?? ""
            settings.httpsPort = (dict["HTTPSPort"] as? Int) ?? 0
        }
        
        if let ftpEnabled = dict["FTPEnable"] as? Int, ftpEnabled == 1 {
            settings.ftpEnabled = true
            settings.ftpServer = dict["FTPProxy"] as? String ?? ""
            settings.ftpPort = (dict["FTPPort"] as? Int) ?? 0
        }
        
        if let exceptions = dict["ProxyAutoConfigJavaScript"] as? String {
            settings.pacURL = exceptions
        }
        
        if let exceptions = dict["ProxyAutoConfigEnable"] as? Int, exceptions == 1 {
            settings.autoConfigEnabled = true
        }
    }
    
    struct ProxySettings {
        var httpEnabled = false
        var httpServer = ""
        var httpPort = 0
        
        var httpsEnabled = false
        var httpsServer = ""
        var httpsPort = 0
        
        var ftpEnabled = false
        var ftpServer = ""
        var ftpPort = 0
        
        var autoConfigEnabled = false
        var pacURL = ""
        
        var bypassList: [String] = []
    }
}
```

---

## LaunchDaemons and Background Execution

### Overview
launchd is the macOS init system responsible for starting, stopping, and managing background processes and daemons.

### LaunchDaemon Configuration
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.myserver</string>
    
    <key>Program</key>
    <string>/usr/local/bin/myserver</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/myserver</string>
        <string>--config</string>
        <string>/etc/myserver.conf</string>
        <string>--port</string>
        <string>8080</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <true/>
    
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>NetworkState</key>
        <true/>
    </dict>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>/var/log/myserver/stdout.log</string>
    
    <key>StandardErrorPath</key>
    <string>/var/log/myserver/stderr.log</string>
    
    <key>WorkingDirectory</key>
    <string>/var/lib/myserver</string>
    
    <key>UserName</key>
    <string>_myserver</string>
    
    <key>GroupName</key>
    <string>_myserver</string>
    
    <key>InitGroups</key>
    <true/>
    
    <key>Umask</key>
    <integer>022</integer>
    
    <key>Nice</key>
    <integer>10</integer>
    
    <key>ProcessType</key>
    <string>Background</string>
    
    <key>LowPriorityIO</key>
    <true/>
    
    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>1024</integer>
        <key>MemoryLock</key>
        <integer>52428800</integer>
        <key>NumberOfProcesses</key>
        <integer>256</integer>
    </dict>
    
    <key>HardResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>2048</integer>
        <key>MemoryLock</key>
        <integer>104857600</integer>
    </dict>
    
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
        <key>LANG</key>
        <string>en_US.UTF-8</string>
        <key>MY_SERVER_CONFIG</key>
        <string>/etc/myserver.conf</string>
    </dict>
    
    <key>WatchPaths</key>
    <array>
        <string>/etc/myserver.conf</string>
    </array>
    
    <key>StartInterval</key>
    <integer>300</integer>
    
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    
    <key>Sockets</key>
    <dict>
        <key>Listeners</key>
        <dict>
            <key>SockServiceName</key>
            <string>8080</string>
            <key>SockType</key>
            <string>stream</string>
            <key>SockFamily</key>
            <string>IPv4</string>
        </dict>
    </dict>
    
    <key>MachServices</key>
    <dict>
        <key>com.example.myserver.mach</key>
        <true/>
    </dict>
</dict>
</plist>
```

### Launch Agent (Per-User)
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.myserver-agent</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/Users/user/bin/myserver</string>
        <string>--user-mode</string>
    </array>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>KeepAlive</key>
    <dict>
        <key>PathState</key>
        <dict>
            <key>/Users/user/.myserver/enabled</key>
            <true/>
        </dict>
    </dict>
    
    <key>StandardOutPath</key>
    <string>/Users/user/Library/Logs/myserver/stdout.log</string>
    
    <key>StandardErrorPath</key>
    <string>/Users/user/Library/Logs/myserver/stderr.log</string>
    
    <key>WorkingDirectory</key>
    <string>/Users/user</string>
</dict>
</plist>
```

### Socket Activation
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.example.socket-activated-server</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/myserver</string>
        <string>--socket-activated</string>
    </array>
    
    <key>RunAtLoad</key>
    <false/>
    
    <key>KeepAlive</key>
    <false/>
    
    <key>Sockets</key>
    <dict>
        <key>Listeners</key>
        <dict>
            <key>SockServiceName</key>
            <string>http</string>
            <key>SockType</key>
            <string>stream</string>
            <key>SockFamily</key>
            <string>IPv4</string>
            <key>Bonjour</key>
            <array>
                <string>_http._tcp</string>
            </array>
        </dict>
        
        <key>SecureListeners</key>
        <dict>
            <key>SockServiceName</key>
            <string>https</string>
            <key>SockType</key>
            <string>stream</string>
            <key>SockFamily</key>
            <string>IPv4</string>
            <key>Bonjour</key>
            <array>
                <string>_https._tcp</string>
            </array>
        </dict>
    </dict>
    
    <key>inetdCompatibility</key>
    <dict>
        <key>Wait</key>
        <false/>
    </dict>
</dict>
</plist>
```

### Managing LaunchDaemons
```swift
import Foundation

class LaunchdManager {
    
    func loadDaemon(plistPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", "-w", plistPath]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw LaunchdError.loadFailed
        }
    }
    
    func unloadDaemon(plistPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", "-w", plistPath]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw LaunchdError.unloadFailed
        }
    }
    
    func startDaemon(label: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["start", label]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw LaunchdError.startFailed
        }
    }
    
    func stopDaemon(label: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["stop", label]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw LaunchdError.stopFailed
        }
    }
    
    func listDaemons() throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        var daemons: [String] = []
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("-") || line.hasPrefix(" ") {
                continue
            }
            if !line.isEmpty {
                let parts = line.components(separatedBy: "\t")
                if parts.count >= 3 {
                    daemons.append(parts[2])
                }
            }
        }
        
        return daemons
    }
    
    func getDaemonStatus(label: String) throws -> DaemonStatus {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["list", label]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        try process.run()
        process.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        // Parse output to get status
        return DaemonStatus(label: label, output: output)
    }
    
    enum LaunchdError: Error {
        case loadFailed
        case unloadFailed
        case startFailed
        case stopFailed
    }
    
    struct DaemonStatus {
        let label: String
        let output: String
        var isRunning: Bool {
            output.contains("\"PID\"")
        }
    }
}
```

### XPC Services for Daemon Communication
```swift
import Foundation

@main
class XPCServer {
    private var listener: NSXPCListener?
    
    func run() async {
        let exportedObject = ServerExportedObject()
        
        listener = NSXPCListener.service()
        listener?.delegate = self
        listener?.resume()
        
        await withCheckedContinuation { continuation in
            // Keep the server running
            DispatchQueue.main.asyncAfter(deadline: .now() + .hours(24)) {
                continuation.resume()
            }
        }
    }
}

extension XPCServer: NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, 
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        let exportedObject = ServerExportedObject()
        newConnection.exportedObject = exportedObject
        newConnection.resume()
        return true
    }
}

class ServerExportedObject: NSObject, ServerProtocol {
    func getServerStatus(completion: @escaping (ServerStatus) -> Void) {
        let status = ServerStatus(
            version: "1.0.0",
            uptime: ProcessInfo.processInfo.systemUptime,
            connections: 5
        )
        completion(status)
    }
    
    func shutdown(completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            exit(0)
        }
        completion(true)
    }
}

protocol ServerProtocol: AnyObject {
    func getServerStatus(completion: @escaping (ServerStatus) -> Void)
    func shutdown(completion: @escaping (Bool) -> Void)
}

struct ServerStatus: Codable {
    let version: String
    let uptime: TimeInterval
    let connections: Int
}
```

### XPC Client Connection
```swift
import Foundation

class XPCClient {
    private var connection: NSXPCConnection?
    
    func connect() {
        connection = NSXPCConnection(serviceName: "com.example.myserver")
        connection?.remoteObjectInterface = NSXPCInterface(with: ServerProtocol.self)
        connection?.resume()
    }
    
    func getStatus(completion: @escaping (ServerStatus?) -> Void) {
        guard let proxy = connection?.remoteObjectProxy as? ServerProtocol else {
            completion(nil)
            return
        }
        
        proxy.getServerStatus { status in
            completion(status)
        }
    }
    
    func shutdown() {
        guard let proxy = connection?.remoteObjectProxy as? ServerProtocol else {
            return
        }
        
        proxy.shutdown { _ in
            self.connection?.invalidate()
        }
    }
}
```

---

## Modern Server Frameworks and Patterns

### SwiftNIO (Apple's Event-Driven Framework)
```swift
import NIOCore
import NIOPosix
import NIOHTTP1

class SwiftNIOServer {
    private var group: MultiThreadedEventLoopGroup
    private var serverChannel: Channel?
    
    init() {
        group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    func start(host: String, port: Int) async throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true)
                    .flatMap { channel.pipeline.addHandler(HTTPRequestHandler()) }
            }
        
        serverChannel = try await bootstrap.bind(host: host, port: port)
        
        print("Server started on \(host):\(port)")
        
        // Keep the server running
        if let channel = serverChannel {
            try await channel.closeFuture.get()
        }
    }
    
    func stop() throws {
        try group.syncShutdownGracefully()
    }
}

class HTTPRequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = unwrapInboundIn(data)
        
        switch reqPart {
        case .head(let requestHead):
            handleRequestHead(requestHead, context: context)
        case .body(let buffer):
            // Handle body
            _ = buffer
        case .end(let headers):
            // End of request
            _ = headers
        }
    }
    
    private func handleRequestHead(_ head: HTTPRequestHead, context: ChannelHandlerContext) {
        let responseHead = HTTPResponseHead(
            version: .http1_1,
            status: .ok,
            headers: HTTPHeaders([
                ("Content-Type", "text/plain"),
                ("Connection", "close")
            ])
        )
        
        context.write(wrapOutboundOut(.head(responseHead)))
        
        let responseBody = ByteBuffer(string: "Hello from SwiftNIO!")
        context.write(wrapOutboundOut(.body(.byteBuffer(responseBody))))
        
        context.writeAndFlush(wrapOutboundOut(.end(nil)))
            .whenComplete { _, _ in
                context.close(promise: nil)
            }
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Error: \(error)")
        context.close(promise: nil)
    }
}
```

### SwiftNIO with TLS
```swift
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOSSL

class SwiftNIOTLSServer {
    private var group: MultiThreadedEventLoopGroup
    private let tlsConfig: TLSConfiguration
    
    init(tlsConfig: TLSConfiguration) {
        self.tlsConfig = tlsConfig
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    func startWithTLS(host: String, port: Int, certificatePath: String, keyPath: String) async throws {
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                let serverHandler = HTTPServerHandler()
                
                do {
                    try channel.pipeline.addHandler(NIOSSLServerHandler(context: sslContext))
                        .flatMap { channel.pipeline.addHandler(serverHandler) }
                } catch {
                    channel.close(promise: nil)
                }
            }
        
        _ = try await bootstrap.bind(host: host, port: port)
    }
    
    func stop() throws {
        try group.syncShutdownGracefully()
    }
    
    struct TLSConfiguration {
        let certificatePath: String
        let keyPath: String
        
        var configuration: NIOSSLConfiguration {
            NIOSSLConfiguration(
                certificateChain: .file(certificatePath),
                privateKey: .file(keyPath)
            )
        }
    }
}
```

### SwiftNIO HTTP/2 Server
```swift
import NIOCore
import NIOPosix
import NIOHTTP2
import NIOSSL

class SwiftNIOHTTP2Server {
    private var group: MultiThreadedEventLoopGroup
    private var bootstrap: ServerBootstrap
    
    init() {
        group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        bootstrap = ServerBootstrap(group: group)
    }
    
    func startHTTP2(host: String, port: Int, tlsConfig: NIOSSLConfiguration) async throws {
        let sslContext = try NIOSSLContext(configuration: tlsConfig)
        
        bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                do {
                    let tlsHandler = try NIOSSLServerHandler(context: sslContext)
                    try channel.pipeline.addHandler(tlsHandler).flatMap {
                        channel.pipeline.configureHTTP2Pipeline(mode: .server) { channel in
                            channel.pipeline.addHandlers([
                                HTTP2FramePayloadToHTTPServerCodec(),
                                HTTP2RequestHandler()
                            ])
                        }
                    }
                } catch {
                    channel.close(promise: nil)
                }
            }
        
        _ = try await bootstrap.bind(host: host, port: port)
    }
}

class HTTP2RequestHandler: ChannelInboundHandler {
    typealias InboundIn = HTTP2FramePayload
    typealias OutboundOut = HTTP2FramePayload
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let payload = unwrapInboundIn(data)
        
        switch payload {
        case .headers(let headers):
            handleHeaders(headers, context: context)
        case .data(let data):
            handleData(data, context: context)
        }
    }
    
    private func handleHeaders(_ headers: HTTPHeaders, context: ChannelHandlerContext) {
        // Process HTTP/2 headers
    }
    
    private func handleData(_ data: IOData, context: ChannelHandlerContext) {
        // Process HTTP/2 data
    }
}
```

### Vapor Framework (Popular Server-Side Swift)
```swift
import Vapor

@main
class App {
    static func main() async throws {
        var env = try Environment.detect()
        let app = Application(env)
        defer { app.shutdown() }
        
        // Register routes
        app.get("hello") { req -> String in
            return "Hello, World!"
        }
        
        app.get("api", ":id") { req -> String in
            guard let id = req.parameters.get("id") else {
                throw Abort(.badRequest)
            }
            return "User ID: \(id)"
        }
        
        app.post("data") { req -> Response in
            // Parse request body
            struct CreateData: Content {
                let name: String
                let value: Int
            }
            
            let data = try req.content.decode(CreateData.self)
            
            // Return response
            return Response(
                status: .created,
                content: [
                    "received": data.name,
                    "value": data.value
                ]
            )
        }
        
        // Configure middleware
        app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
        app.middleware.use(CORSMiddleware(configuration: app.corsConfiguration))
        
        // Start server
        try await app.run()
    }
}
```

### Hummingbird Framework
```swift
import Hummingbird
import Foundation

struct App {
    static func main() async throws {
        let app = Application()
        
        app.router.get("/") { request -> String in
            return "Hello from Hummingbird!"
        }
        
        app.router.get("/users/:id") { request -> String in
            guard let id = request.parameters.get("id") else {
                throw HTTPError(.badRequest)
            }
            return "User: \(id)"
        }
        
        app.router.post("/data") { request -> String in
            struct RequestData: Decodable {
                let name: String
                let value: Int
            }
            
            let data = try await request.decode(RequestData.self)
            return "Received: \(data.name) = \(data.value)"
        }
        
        // Add TLS
        app.server.tlsConfiguration = .some(
            TLSConfiguration.forServer(
                certificateChain: .file("/path/to/cert.pem"),
                privateKey: .file("/path/to/key.pem")
            )
        )
        
        try await app.start()
    }
}
```

### Noze.io (Event-Based Framework)
```swift
import http

http.createServer { req, res in
    res.writeHead(200, [("Content-Type", "text/html")])
    res.end("<h1>Hello from Noze.io!</h1>")
}.listen(1337)

dispatchMain()
```

### Embassy (Async I/O Framework)
```swift
import Embassy
import Foundation

class HTTPServer {
    private let eventLoop: SelectorEventLoop
    private let server: DefaultHTTPServer
    
    init(port: Int = 8080) throws {
        eventLoop = try SelectorEventLoop(selector: try KqueueSelector())
        server = DefaultHTTPServer(
            eventLoop: eventLoop,
            port: port
        ) { environ, startResponse, sendBody in
            let pathInfo = environ["PATH_INFO"] as! String
            
            let responseBody = "Path: \(pathInfo)".data(using: .utf8)!
            
            startResponse("200 OK", [])
            sendBody(Data(responseBody))
            sendBody(Data())
        }
    }
    
    func start() throws {
        try server.start()
        eventLoop.runForever()
    }
    
    func stop() {
        server.stop()
    }
}
```

### Best Practices for Modern macOS Server Development

#### Error Handling
```swift
struct ServerError: Error, CustomStringConvertible {
    enum ErrorKind {
        case startupFailed
        case connectionFailed
        case protocolError
        case authenticationFailed
        case resourceExhausted
    }
    
    let kind: ErrorKind
    let message: String
    let underlying: Error?
    
    var description: String {
        "\(kind): \(message)"
    }
}

extension ServerError {
    static func startupFailed(underlying: Error? = nil) -> ServerError {
        ServerError(kind: .startupFailed, 
                   message: "Failed to start server", 
                   underlying: underlying)
    }
}
```

#### Health Checks
```swift
class HealthCheckEndpoint {
    private let server: HTTPServer
    
    init(server: HTTPServer) {
        self.server = server
    }
    
    func registerRoutes(on router: Router) {
        router.get("/health") { request -> HealthStatus in
            HealthStatus(
                status: .healthy,
                uptime: self.server.uptime,
                connections: self.server.activeConnectionCount,
                memoryUsage: self.server.memoryUsage,
                lastError: self.server.lastError
            )
        }
        
        router.get("/health/ready") { request -> HealthStatus in
            if self.server.isReady {
                return HealthStatus(status: .healthy)
            } else {
                throw HTTPError(.serviceUnavailable)
            }
        }
        
        router.get("/health/live") { request in
            // Simple liveness check
            return "OK"
        }
    }
}

struct HealthStatus: Encodable {
    let status: Status
    let uptime: TimeInterval?
    let connections: Int?
    let memoryUsage: Int?
    let lastError: String?
    
    enum Status: String, Encodable {
        case healthy
        case unhealthy
        case degraded
    }
}
```

#### Metrics Collection
```swift
import Metrics

class ServerMetrics {
    private let connectionCounter: Counter
    private let requestLatency: Timer
    private let activeConnections: Gauge
    
    init() {
        let metricsSystem = MetricsSystem.bootstap()
        
        connectionCounter = Counter(label: "server_connections_total",
                                   dimensions: [("protocol", "http")])
        
        requestLatency = Timer(label: "server_request_duration",
                              dimensions: [("method", "unknown")])
        
        activeConnections = Gauge(label: "server_active_connections")
    }
    
    func recordConnection(opened: Bool) {
        if opened {
            connectionCounter.increment()
            activeConnections.increment()
        } else {
            connectionCounter.increment(dimension: "outcome", value: "closed")
            activeConnections.decrement()
        }
    }
    
    func recordRequest(method: String, latency: TimeInterval) {
        requestLatency.recordSeconds(latency, dimensions: [("method", method)])
    }
}
```

---

## Conclusion

This  guide covers the major APIs and frameworks available for building network server applications on macOS:

### Recommended Stack for Modern macOS Servers

1. **Network Layer**: Use `Network.framework` for new projects (available macOS 10.15+), or `SwiftNIO` for cross-platform compatibility and advanced features
2. **Service Discovery**: `NSNetService` for simple cases, DNS-SD API for advanced scenarios
3. **Security**: `Security` framework with `Keychain Services` for credentials, `CommonCrypto` for cryptographic operations
4. **Deployment**: `launchd` with proper plist configuration for production deployments
5. **High-Level Frameworks**: Consider `Vapor` or `Hummingbird` for rapid development with full HTTP server capabilities

### Key Considerations

- **Permissions**: Server applications may require special entitlements (`com.apple.security.network.server`)
- **Sandboxing**: Determine if your app needs to run sandboxed or with elevated privileges
- **Network Security**: Implement TLS for all production communications
- **Monitoring**: Use `Network.framework`'s `NWPathMonitor` for adaptive behavior
- **Background Execution**: Properly configure `launchd` for reliability and restart behavior

### References

- [Apple's Network Framework Documentation](https://developer.apple.com/documentation/network)
- [SwiftNIO GitHub Repository](https://github.com/apple/swift-nio)
- [Network.framework WWDC Sessions](https://developer.apple.com/videos/play/wwdc2019/713/)
- [Security Framework Reference](https://developer.apple.com/documentation/security)
- [Daemons and Services Programming Guide](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html)
- [Bonjour Programming Guide](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/NetServices/Introduction.html)

## Related Documentation

- **[Objective-C Tips](objective_c_tips.md)** - Memory management and GCD patterns
- **[Developer Guide](DEVELOPER_GUIDE.md)** - Project structure and build system
- **[Deployment Guide](DEPLOYMENT.md)** - Production deployment with launchd
- **[Architecture Analysis](../architecture/ARCHITECTURE_ANALYSIS.md)** - System components
- **[Security Plan](../security/SECURITY_PLAN.md)** - Security hardening
- **[OAuth 2.0 Implementation](../oauth2/README.md)** - TLS and authentication
