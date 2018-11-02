# UIWebView To WKWebView
將UIWebView轉換到WKWebView的過程記錄

||UIWebView|WKWebView|
|---|---|---|
|delegate|delegate|navigationDelegate / UIDelegate|
|didFailLoad|didFailLoadWithError|didFailNavigation|
|didFinishLoad|webViewDidFinishLoad|didFinishNavigation|
|didStartLoad|webViewDidStartLoad|didStartProvisionalNavigation|
|shouldLoadRequest|shouldStartLoadWithRequest|decidePolicyForNavigationAction|
|Snapshot|需自行處理|takeSnapshotWithConfiguration|
|storyboard|可|在iOS11前initWithCoder會有問題|
|javascript|stringByEvaluatingJavaScriptFromString|evaluateJavaScript/WKUSerScript|
|取得Web title|via javascript|webview.title|
|取得Web URL|webview.request.url|webview.url|


其他介面大多共通，諸如 `scrollview`,`canGoBack/Forward`,`loadRequest`

# init
如果在deploy target低於iOS的情況下於xib/storyboard中使用WKWebView會出現error
`wkwebview before ios 11.0 (nscoding support was broken in previous versions)` ref: [stackoverflow](https://stackoverflow.com/questions/46221577/xcode-9-gm-wkwebview-nscoding-support-was-broken-in-previous-versions)

另外WKWebView的init有`configuration: WKWebViewConfiguration`參數，如果需要某些property的，如`allowsInlineMediaPlayback`需在此設定

# shouldLoadRequest
在UIWebView中是用`return value`決定shouldLoadRequest, WKWebKit則是`closure(.allow/.cancel)`

**UIWebView**
```Swift
webView(_ webView: UIWebView, shouldStartLoadWith request: URLRequest, navigationType: UIWebView.NavigationType) -> Bool
    if blah return false
    return true
}
```
**WKWebView**
```Swift
webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
    if blah decisionHandler(.cancel)
    decisionHandler(.allow)
}
```

# javascript
在UIWebView中`stringByEvaluatingJavaScriptFromString`會直接return value，在WKWebView中`evaluateJavaScript`則是以closure的方式呈現；並且多了`WKUSerScript`來幫助處理每次都需要注入的常規js

**UIWebVew**
```Swift
let result = webview.stringByEvaluatingJavaScriptFromString(js)
if result == nil {
    print("error")
}
print(result)
```

**WKWebView**
```Swift
webview.evaluateJavaScript(js) { (result, error) in
    print(error)
    print(result)
}
````

**WKWebView-WKUserScript**
```Swift
let config = webView.configuration
config.userContentController.removeAllUserScripts()
let javascript = "SOME REGULAR JS"
let script = WKUserScript(source: javascript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
config.userContentController.addUserScript(script)
```

ref: [Migrating from UIWebView to WKWebView StackOverflow](https://stackoverflow.com/questions/37509990/migrating-from-uiwebview-to-wkwebview)
