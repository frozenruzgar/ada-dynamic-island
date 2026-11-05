import AdaCore
import Foundation

/// Safety: bytes/completed/rejected are confined to the serial delegate queue.
/// Cross-queue task/session access is locked. URL/identifier/completion are
/// immutable before start. Completion transfers Data; images stay on MainActor.
final class MediaArtworkRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    static let maximumBytes = 3 * 1024 * 1024
    let identifier: String
    private let url: URL
    private let completion: @Sendable (Data?) -> Void
    private var bytes = Data()
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private let taskLock = NSLock()
    private var completed = false
    private var rejected = false

    init(identifier: String, url: URL, completion: @escaping @Sendable (Data?) -> Void) {
        self.identifier = identifier
        self.url = url
        self.completion = completion
    }
    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        let task = session.dataTask(with: url)
        taskLock.lock()
        self.session = session
        self.task = task
        taskLock.unlock()
        task.resume()
    }
    func cancel() {
        taskLock.lock()
        let task = self.task
        taskLock.unlock()
        task?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(NowPlayingPolicy.artworkURLAllowed) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let validStatus = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
        let isImage = response.mimeType?.lowercased().hasPrefix("image/") == true
        rejected = !validStatus || !isImage || response.expectedContentLength > Int64(Self.maximumBytes)
        completionHandler(rejected ? .cancel : .allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= Self.maximumBytes else { rejected = true; dataTask.cancel(); return }
        bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed else { return }
        completed = true
        completion(error == nil && !rejected ? bytes : nil)
        session.finishTasksAndInvalidate()
        taskLock.lock()
        self.session = nil
        self.task = nil
        taskLock.unlock()
    }
}
