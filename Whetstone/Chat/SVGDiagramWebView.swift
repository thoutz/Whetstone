import SwiftUI
import WebKit

enum SVGDiagramSanitizer {
    /// Strips `<script>` tags so embedded SVG cannot ship executable script blocks into WKWebView.
    static func embeddedFragment(_ raw: String) -> String {
        var s = raw
        while let start = s.range(of: "<script", options: .caseInsensitive) {
            if let end = s.range(of: "</script>", options: .caseInsensitive, range: start.upperBound..<s.endIndex) {
                s.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                s.removeSubrange(start.lowerBound..<s.endIndex)
                break
            }
        }
        return s
    }
}

/// Renders mentor `render_construction` SVG using WebKit (JavaScript off). Fits alongside chat prose.
struct SVGDiagramWebView: UIViewRepresentable {

    let svgFragment: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(Self.htmlDocument(embedding: svgFragment), baseURL: nil)
    }

    private static func htmlDocument(embedding svg: String) -> String {
        """
        <!DOCTYPE html>
        <html lang="en"><head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1"/>
        <style>
          html, body { margin:0; padding:0; background:transparent; }
          body { display:flex; justify-content:center; align-items:flex-start; }
          svg { max-width:100%; height:auto; display:block; }
        </style>
        </head><body>\(svg)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
