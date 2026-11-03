import Foundation
import UIKit
import WebKit

/// 用隐藏的 `WKWebView` 打开抖音短链，等它跳转到直播间页，再把渲染后的 HTML 取回来。
///
/// 为什么必须走浏览器：`v.douyin.com/xxx` 的 302 目标依赖 JS 写入的 Cookie
/// （`__ac_nonce` / `__ac_signature`）。纯 `URLSession` 请求只能拿到 302 到
/// `www.douyin.com` 首页，页面里没有任何流地址；浏览器执行完 JS 后才会跳到
/// `webcast.amemv.com/douyin/webcast/reflow/<room>?...`，那一页里明文写着 flv。
@MainActor
final class WebPageLoader: NSObject {

    static let shared = WebPageLoader()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<(html: String, finalURL: URL?, captured: [String])?, Never>?
    private var settled = false
    private var captured: [String] = []

    /// 注入到页面里的探针：抖音的直播流地址是播放器用 XHR/fetch 拉的，
    /// 不在 SSR 的 HTML 里。这里把请求过的 URL 都回传给原生。
    private static let probeJS = """
    (function(){
      if (window.__mtHooked) return; window.__mtHooked = true;
      function send(u){ try { window.webkit.messageHandlers.mtCapture.postMessage(String(u)); } catch(e){} }
      var open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function(m, u){ send(u); return open.apply(this, arguments); };
      if (window.fetch) {
        var f = window.fetch;
        window.fetch = function(i){ try { send(i && i.url ? i.url : i); } catch(e){} return f.apply(this, arguments); };
      }
      var desc = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
      if (desc && desc.set) {
        Object.defineProperty(HTMLMediaElement.prototype, 'src', {
          set: function(v){ send(v); return desc.set.call(this, v); },
          get: desc.get, configurable: true
        });
      }
    })();
    """

    private static let safariUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    func load(_ url: URL, timeout: TimeInterval = 18) async -> (html: String, finalURL: URL?, captured: [String])? {
        teardown()

        guard let host = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) else {
            return nil
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        captured = []

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: Self.probeJS,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        controller.add(self, name: "mtCapture")
        configuration.userContentController = controller

        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        web.customUserAgent = Self.safariUA
        web.navigationDelegate = self
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        host.addSubview(web)
        webView = web

        let result: (html: String, finalURL: URL?, captured: [String])? = await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.settled = false

            web.load(URLRequest(url: url))

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(nil)
            }
        }

        teardown()
        return result
    }

    private func finish(_ value: (html: String, finalURL: URL?, captured: [String])?) {
        guard !settled else { return }
        settled = true
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: value)
    }

    private func teardown() {
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
    }

    /// 判断当前落地页是不是已经到了直播间。
    private func isLivePage(_ url: URL?) -> Bool {
        guard let url else { return false }
        let text = url.absoluteString
        return text.contains("webcast.amemv.com") && text.contains("/reflow/")
    }

    private func grabHTML(_ web: WKWebView, finalURL: URL?) {
        web.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            guard let self else { return }
            let html = (result as? String) ?? ""
            Task { @MainActor in
                // 再给播放器一点时间发请求
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                self.finish((html: html, finalURL: finalURL, captured: self.captured))
            }
        }
    }
}

extension WebPageLoader: WKScriptMessageHandler {
    nonisolated func userContentController(_ userContentController: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        Task { @MainActor in
            if self.captured.count < 200 { self.captured.append(text) }
        }
    }
}

extension WebPageLoader: WKNavigationDelegate {

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // 短链会先落到 douyin.com 首页，再跳 reflow；只有后者才有流地址。
            if self.isLivePage(webView.url) {
                // 给页面一点时间把 SSR 数据写完
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self.grabHTML(webView, finalURL: webView.url)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}
