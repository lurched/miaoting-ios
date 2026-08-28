//  StreamClient.swift
//  HTTP-FLV 流客户端
//
//  从 Android P 类的 HttpURLConnection 流读取逻辑反编译重写
//  负责建立连接并持续读取 FLV 数据流
//

import Foundation

class StreamClient: NSObject, URLSessionDataDelegate {

    // 回调
    var onData: ((Data) -> Void)?
    var onError: ((String) -> Void)?
    var onStatus: ((String) -> Void)?

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var isCancelled = false

    // 统计
    private(set) var totalBytesReceived: Int = 0
    private(set) var startTime: Date?

    // 超时
    private let connectTimeout: TimeInterval = 10
    private let readTimeout: TimeInterval = 0  // 0 = 无超时（流式）

    // MARK: - 开始连接
    func startStreaming(url: String) {
        guard let url = URL(string: url) else {
            onError?("无效的流地址")
            return
        }

        isCancelled = false
        startTime = Date()
        totalBytesReceived = 0

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = connectTimeout
        request.setValue(PlatformDetector.userAgent(for: url.absoluteString), forHTTPHeaderField: "User-Agent")
        request.setValue(PlatformDetector.referer(for: url.absoluteString), forHTTPHeaderField: "Referer")
        request.setValue("close", forHTTPHeaderField: "Connection")

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = connectTimeout
        config.timeoutIntervalForResource = .infinity  // 流不超时
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 1

        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.task = session?.dataTask(with: request)
        task?.resume()

        onStatus?("正在连接直播流...")
    }

    // MARK: - 停止
    func stop() {
        isCancelled = true
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    // MARK: - URLSessionDataDelegate
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard !isCancelled else {
            completionHandler(.cancel)
            return
        }

        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode != 200 {
                onError?("HTTP \(httpResponse.statusCode): 流连接失败")
                completionHandler(.cancel)
                return
            }

            let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
            onStatus?("流已连接 (Content-Type: \(contentType))")
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isCancelled else { return }

        totalBytesReceived += data.count
        onData?(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if isCancelled { return }

        if let error = error {
            let nsError = error as NSError
            if nsError.code != NSURLErrorCancelled {
                onError?("流断开: \(error.localizedDescription)")
            }
        } else {
            onStatus?("流已结束")
        }
    }

    // MARK: - 统计
    var dataRate: Double {
        guard let startTime = startTime, startTime.timeIntervalSinceNow < 0 else { return 0 }
        let elapsed = -startTime.timeIntervalSinceNow
        return Double(totalBytesReceived) / elapsed
    }
}
