import Foundation

/// 拉取 FLV 直播流（长连接，边收边吐）。
///
/// 对应 Android 端 `Lq.run()` 里那段 `HttpURLConnection` + `BufferedInputStream`：
///   - UA 伪装成移动端浏览器
///   - Referer 按平台切换（douyin / xiaohongshu / kuaishou / taobao）
///   - 200 才开始读，其余一律视为“暂未开播”
final class FLVStreamLoader: NSObject {

    var onData: ((Data) -> Void)?
    var onFinished: ((Error?) -> Void)?

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var responseChecked = false
    private var finished = false

    /// 与 Android 端 `Lq` 拉流时用的 UA 完全一致。
    static let mobileUA = "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Mobile Safari/537.36"

    func start(url: URL, referer: String?) {
        cancel()
        finished = false
        responseChecked = false

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = .greatestFiniteMagnitude
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpShouldUsePipelining = false

        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: url)
        request.setValue(Self.mobileUA, forHTTPHeaderField: "User-Agent")
        request.setValue("video/x-flv,*/*", forHTTPHeaderField: "Accept")
        if let referer, !referer.isEmpty {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }

        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    func cancel() {
        finished = true
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func finish(_ error: Error?) {
        guard !finished else { return }
        finished = true
        task = nil
        session?.finishTasksAndInvalidate()
        session = nil
        onFinished?(error)
    }
}

extension FLVStreamLoader: URLSessionDataDelegate {

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        responseChecked = true
        if code == 200 {
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
            finish(StreamError.notLive(code))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        onData?(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).code == NSURLErrorCancelled, finished { return }
        finish(error)
    }
}

enum StreamError: LocalizedError {
    case notLive(Int)
    case emptyStream

    var errorDescription: String? {
        switch self {
        case .notLive(let code): return "直播间暂未开播（HTTP \(code)）。"
        case .emptyStream: return "直播音频流为空，请稍后重试。"
        }
    }
}
