//
//  File.swift
//
//
//  Created by Carson Katri on 6/30/19.
//

import Foundation
import Json
import SwiftUI
import Combine

/// The building block for making an HTTP request
///
/// Built using a `@resultBuilder`, available in Swift 5.4
///
/// *Example*:
///
///     Request {
///         Url("https://api.example.com/todos")
///     }
///
/// To make the `Request`, use the method `call`
///
/// To accept data from the `Request`, use `onData`, `onString`, and `onJson`.
///
/// **See Also:**
/// `Url`, `Method`, `Header`, `Query`, `Body`
///
/// - Precondition: The `Request` body must contain **exactly one** `Url`
public typealias Request = AnyRequest<Data>

/// Tha base class of `Request` to be used with a `Codable` `ResponseType` when using the `onObject` callback
///
/// *Example*:
///
///     AnyRequest<[MyCodableStruct]> {
///         Url("https://api.example.com/myData")
///     }
///     .onObject { myCodableStructs in
///         ...
///     }
public struct AnyRequest<ResponseType> where ResponseType: Decodable {
    public let combineIdentifier = CombineIdentifier()

    internal var rootParam: RequestParam
    
    internal var onData: ((Data) -> Void)?
    internal var onString: ((String) -> Void)?
    internal var onJson: ((Json) -> Void)?
    internal var onObject: ((ResponseType) -> Void)?
    internal var onError: ((Error) -> Void)?
    internal var onStatusCode: ((Int) -> Void)?
    internal var updatePublisher: AnyPublisher<Void,Never>?
    
    public init(@RequestBuilder builder: () -> RequestParam) {
        rootParam = builder()
    }
    
    internal init(rootParam: RequestParam) {
        self.rootParam = rootParam
    }
    
    internal func modify(_ modify: (inout Self) -> Void) -> Self {
        var mutableSelf = self
        modify(&mutableSelf)
        return mutableSelf
    }
    
    /// Sets the `onData` callback to be run whenever `Data` is retrieved
    public func onData(_ callback: @escaping (Data) -> Void) -> Self {
        modify { $0.onData = callback }
    }

    /// Sets the `onString` callback to be run whenever a `String` is retrieved
    public func onString(_ callback: @escaping (String) -> Void) -> Self {
        modify { $0.onString = callback }
    }

    /// Sets the `onData` callback to be run whenever `Json` is retrieved
    public func onJson(_ callback: @escaping (Json) -> Void) -> Self {
        modify { $0.onJson = callback }
    }

    /// Sets the `onObject` callback to be run whenever `Data` is retrieved
    public func onObject(_ callback: @escaping (ResponseType) -> Void) -> Self {
        modify { $0.onObject = callback }
    }

    /// Handle any `Error`s thrown by the `Request`
    public func onError(_ callback: @escaping (Error) -> Void) -> Self {
        modify { $0.onError = callback }
    }
    
    /// Sets the `onStatusCode` callback to be run whenever a `HTTPStatus` is retrieved
    public func onStatusCode(_ callback: @escaping (Int) -> Void) -> Self {
        modify { $0.onStatusCode = callback }
    }
    
    /// Modifies self to contain the procided Auth struct in its headers
    public mutating func withAuthorization(_ authorization: Auth) -> Self {
        self.rootParam = CombinedParams(children: [Header.Authorization(authorization),
                                                   rootParam])
        return self
    }
    
    /// Performs the `Request`, and calls the `onData`, `onString`, `onJson`, and `onError` callbacks when appropriate.
    public func call() {
        buildPublisher()
            .subscribe(self)
        if let updatePublisher = self.updatePublisher {
            updatePublisher
                .subscribe(UpdateSubscriber(request: self))
        }
    }

    internal func buildSession() -> (configuration: URLSessionConfiguration, request: URLRequest) {
        var request = URLRequest(url: URL(string: "https://")!)
        let configuration = URLSessionConfiguration.default

        rootParam.buildParam(&request)
        (rootParam as? SessionParam)?.buildConfiguration(configuration)
        
        return (configuration, request)
    }
    
    internal func buildPublisher() -> AnyPublisher<(data: Data, response: URLResponse), Error> {
        // PERFORM REQUEST
        let session = buildSession()
        return URLSession(configuration: session.configuration).dataTaskPublisher(for: session.request)
            .mapError { $0 }
            .eraseToAnyPublisher()
    }

    /// Sets the `Request` to be performed additional times after the initial `call`
    public func update<T: Publisher>(publisher: T) -> Self {
        modify {
            $0.updatePublisher = publisher
                .map {_ in  }
                .assertNoFailure()
                .merge(with: self.updatePublisher ?? Empty().eraseToAnyPublisher())
                .eraseToAnyPublisher()
        }
    }

    /// Sets the `Request` to be repeated periodically after the initial `call`
    public func update(every seconds: TimeInterval) -> Self {
        self.update(publisher: Timer.publish(every: seconds, on: .main, in: .common).autoconnect())
    }
}

extension AnyRequest: Identifiable {
    public var id: String {
        buildSession().request.url!.absoluteString
    }
}

extension AnyRequest: Equatable {
    public static func == (lhs: AnyRequest<ResponseType>, rhs: AnyRequest<ResponseType>) -> Bool {
        let lhsSession = lhs.buildSession()
        let rhsSession = rhs.buildSession()
        return lhsSession.configuration == rhsSession.configuration && lhsSession.request == rhsSession.request
    }
}

extension AnyRequest {
    public func prettyJson() -> String {
        
        let session = self.buildSession()
        let request = session.request
        let method = request.httpMethod ?? "WTF"
        let url = request.url?.absoluteString ?? ""
        let headers = request.allHTTPHeaderFields
        let body = request.httpBody ?? Data()
        let jh = Json(headers ?? [:]).stringified ?? "No Headers"

        return """
               Beginning of Request.
               ----------------------------------
               Endpoint: \(method.uppercased()) \(url)
               __________________________________
               Headers: \(jh)
               __________________________________
               Body: \(body.prettyJSON())
               ___________________________________
               End Of Request.
               """
        
    }
}

extension Data {
    func toString() -> String {
        return String(data:self, encoding: .utf8) ?? ""
    }
    func prettyJSON() -> String {
        do {
            let json = try JSONSerialization.jsonObject(with: self, options: [])
            let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                print("Inavlid data")
                return ""
            }
            return jsonString
        } catch {
            print("Data+prettyJSON | Error: \(error.localizedDescription)")
        }
        return ""
    }
}
