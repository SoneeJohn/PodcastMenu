//
//  OvercastController.swift
//  PodcastMenu
//
//  Created by Guilherme Rambo on 10/05/16.
//  Copyright © 2016 Guilherme Rambo. All rights reserved.
//

import Cocoa
import WebKit

protocol OvercastLoudnessDelegate {
    func loudnessDidChange(_ value: Double)
}

protocol OvercastNavigationDelegate: class {
    func navigateToPlayback()
    func requestPlaybackAudio(at url: URL)
    func dismissPlayback(navigateTo url: URL?)
}

extension Notification.Name {
    static let OvercastDidPlay = Notification.Name("OvercastDidPlay")
    static let OvercastDidPause = Notification.Name("OvercastDidPause")
    static let OvercastDidCapturePlaybackURL = Notification.Name("OvercastDidCapturePlaybackURL")
    static let OvercastShouldUpdatePlaybackInfo = Notification.Name("OvercastShouldUpdatePlaybackInfo")
    static let OvercastIsNotOnEpisodePage = Notification.Name("OvercastIsNotOnEpisodePage")
    static let OvercastCommandTogglePlaying = Notification.Name("OvercastCommandTogglePlaying")
}

class OvercastController: NSObject, WKNavigationDelegate {
    
    var loudnessDelegate: OvercastLoudnessDelegate?
    
    weak var navigationDelegate: OvercastNavigationDelegate?
    
    fileprivate let webView: WKWebView
    fileprivate let bridge: OvercastJavascriptBridge
    
    //The last Overcast URL (any valid Overcast URL that isn't a episode URL)
    fileprivate var latestOvercastURL: URL?
    
    fileprivate var mediaKeysHandler = MediaKeysHandler()
    
    fileprivate lazy var userScript: WKUserScript = {
        let source = try! String(contentsOf: Bundle.main.url(forResource: "overcast", withExtension: "js")!)
        
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }()
    
    fileprivate lazy var lookUserScript: WKUserScript = {
        let source = try! String(contentsOf: Bundle.main.url(forResource: "look", withExtension: "js")!)
        
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
    }()
    
    init(webView: WKWebView) {
        self.webView = webView
        self.bridge = OvercastJavascriptBridge(webView: webView)
        
        super.init()
        
        self.bridge.callback = callLoudnessDelegate
        
        webView.navigationDelegate = self
        
        mediaKeysHandler.playPauseHandler = handlePlayPauseButton
        mediaKeysHandler.forwardHandler = handleForwardButton
        mediaKeysHandler.backwardHandler = handleBackwardButton
        
        webView.configuration.userContentController.addUserScript(lookUserScript)
        webView.configuration.userContentController.addUserScript(userScript)
        
        NotificationCenter.default.addObserver(forName: Notification.Name.OvercastDidPlay, object: nil, queue: nil) { [weak self] _ in
            self?.startActivityIfNeeded()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name.OvercastDidPause, object: nil, queue: nil) { [weak self] _ in
            self?.stopActivity()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name.OvercastCommandTogglePlaying, object: nil, queue: nil) { [weak self] _ in
            self?.handlePlayPauseButton()
        }
        NotificationCenter.default.addObserver(forName: Notification.Name.OvercastDidCapturePlaybackURL, object: nil, queue: nil) { [weak self] note in
            guard let url = note.object as? URL else { return }
            
            self?.navigationDelegate?.requestPlaybackAudio(at: url)
        }
        
        NotificationCenter.default.addObserver(forName: Notification.Name.PlaybackViewControllerDidRequestDismissal, object: nil, queue: nil) { [weak self] _ in
            self?.navigationDelegate?.dismissPlayback(navigateTo: self?.latestOvercastURL)
        }
    }
    
    func isValidOvercastURL(_ URL: Foundation.URL) -> Bool {
        guard let host = URL.host else { return false }
        
        return Constants.allowedHosts.contains(host)
    }
    
    func isValidOvercastEpisodeURL(_ URL: Foundation.URL) -> Bool {
         return URL.path.hasPrefix(Constants.episodePrefixPath)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // the default is to allow the navigation
        var decision = WKNavigationActionPolicy.allow
        
        defer { decisionHandler(decision) }
        
        guard navigationAction.navigationType == .linkActivated else { return }
        
        guard let url = navigationAction.request.url else { return }
        
        // if the user clicked a link to another website, open with the default browser instead of navigating inside the app
        guard isValidOvercastURL(url) else {
            decision = .cancel
            NSWorkspace.shared().open(url)
            return
        }
        
        guard isValidOvercastEpisodeURL(url) else { return }
        
        navigationDelegate?.navigateToPlayback()
        
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.async {
            if webView.url?.path != Constants.homePath {
                self.startPlaybackInfoTimer()
            } else {
                NotificationCenter.default.post(name: .OvercastIsNotOnEpisodePage, object: nil)
                self.stopPlaybackInfoTimer()
            }
            guard let url = webView.url else { return }
            
            if self.isValidOvercastEpisodeURL(url) == false {
                self.latestOvercastURL = url
            }
        }
    }
    
    // MARK: - Playback Info
    
    private var playbackInfoTimer: Timer?
    
    fileprivate func startPlaybackInfoTimer() {
//        playbackInfoTimer?.invalidate()
//
//        playbackInfoTimer = Timer.scheduledTimer(timeInterval: 1,
//                                                 target: self,
//                                                 selector: #selector(updatePlaybackInfo(_:)),
//                                                 userInfo: nil,
//                                                 repeats: true)
    }
    
    fileprivate func stopPlaybackInfoTimer() {
        playbackInfoTimer?.invalidate()
        playbackInfoTimer = nil
    }
    
    @objc fileprivate func updatePlaybackInfo(_ sender: Timer) {
        guard !isPaused else { return }
        
        NotificationCenter.default.post(name: .OvercastShouldUpdatePlaybackInfo, object: nil)
    }
    
    fileprivate var isPaused = false
    
    // WKWebView has a bug where javascript will not be evaluated in some circumstances (Radar #26290876)
    fileprivate func fakeOrderFrontToWorkaround26290876() {
        guard !NSApp.isActive else { return }
        
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current().duration = 0.0
        webView.window?.orderFrontRegardless()
        webView.window?.alphaValue = 0.0
        NSAnimationContext.endGrouping()
    }
    
    fileprivate func undoFakeOrderFront() {
        guard !NSApp.isActive else { return }
        
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current().duration = 0.0
        webView.window?.orderOut(nil)
        NSAnimationContext.endGrouping()
    }
    
    fileprivate func handlePlayPauseButton() {
        fakeOrderFrontToWorkaround26290876()
        
        if isPaused {
            webView.evaluateJavaScript("document.querySelector('audio').play()") { [unowned self] _, _ in
                DispatchQueue.main.async(execute: self.undoFakeOrderFront);
            }
        } else {
            webView.evaluateJavaScript("document.querySelector('audio').pause()") { [unowned self] _, _ in
                DispatchQueue.main.async(execute: self.undoFakeOrderFront);
            }
        }
        
        isPaused = !isPaused
    }
    
    fileprivate func handleForwardButton() {
        fakeOrderFrontToWorkaround26290876()
        
        webView.evaluateJavaScript("document.querySelector('#seekforwardbutton').click()") { [unowned self] _, _ in
            DispatchQueue.main.async(execute: self.undoFakeOrderFront);
        }
    }
    
    fileprivate func handleBackwardButton() {
        fakeOrderFrontToWorkaround26290876()
        
        webView.evaluateJavaScript("document.querySelector('#seekbackbutton').click()") { [unowned self] _, _ in
            DispatchQueue.main.async(execute: self.undoFakeOrderFront);
        }
    }
    
    fileprivate func callLoudnessDelegate(_ value: Double) {
        loudnessDelegate?.loudnessDidChange(value)
    }
    
    // MARK: - Activity
    
    fileprivate var activity: NSObjectProtocol?
    
    fileprivate func startActivityIfNeeded() {
        guard activity == nil else { return }
        
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .automaticTerminationDisabled, .suddenTerminationDisabled, .idleSystemSleepDisabled], reason: "PodcastMenu")
        
        #if DEBUG
        NSLog("[OvercastController] Started activity \(String(describing: activity))")
        #endif
    }
    fileprivate func stopActivity() {
        guard let activity = activity else { return }
        
        #if DEBUG
        NSLog("[OvercastController] Stopping activity \(activity)")
        #endif
        
        ProcessInfo.processInfo.endActivity(activity)
        
        self.activity = nil
    }
    
    // MARK: - Error handling
    
    fileprivate var errorViewController: ErrorViewController!
    
    @objc fileprivate func reload() {
        let currentURL = webView.url ?? Constants.webAppURL as URL
        webView.load(URLRequest(url: currentURL))
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        DispatchQueue.main.async {
            self.hideErrorViewController()
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        let delayTime = DispatchTime.now() + Double(Int64(Constants.retryIntervalAfterError * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
        DispatchQueue.main.asyncAfter(deadline: delayTime) { [weak self] in
            self?.reload()
        }
        
        DispatchQueue.main.async {
            self.showErrorViewControllerWithError(error as NSError)
        }
    }
    
    fileprivate func showErrorViewControllerWithError(_ error: NSError) {
        if errorViewController == nil {
            errorViewController = ErrorViewController(error: error)
            
            if let superview = webView.superview {
                errorViewController.view.frame = NSRect(x: 0.0, y: superview.bounds.height - Metrics.errorBarHeight, width: superview.bounds.width, height: Metrics.errorBarHeight)
                errorViewController.view.alphaValue = 0.0
                errorViewController.view.autoresizingMask = [.viewWidthSizable, .viewMinYMargin]
                superview.addSubview(errorViewController.view)
            }
            
            errorViewController.reloadHandler = { [weak self] in
                self?.reload()
            }
        }
        
        errorViewController.view.isHidden = false
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            self.errorViewController.view.animator().alphaValue = 1.0
            }, completionHandler: nil)
    }
    
    fileprivate func hideErrorViewController() {
        guard errorViewController != nil else { return }
        
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            self.errorViewController.view.animator().alphaValue = 0.0
            }, completionHandler: { self.errorViewController.view.isHidden = true })
    }
    
}

private class OvercastJavascriptBridge: NSObject, WKScriptMessageHandler {
    
    var callback: (Double) -> () = { _ in }
    
    fileprivate var fakeGenerator: FakeLoudnessDataGenerator!
    
    init(webView: WKWebView) {
        super.init()
        
        webView.configuration.userContentController.add(self, name: Constants.javascriptBridgeName)
    }
    
    @objc fileprivate func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let msg = message.body as? String else { return }
        guard let msgData = msg.data(using: .utf8) else { return }
        
        do {
            guard let msgDict = try JSONSerialization.jsonObject(with: msgData, options: []) as? [String: String] else { return }
            
            guard let msgName = msgDict["name"] else { return }
            
            DispatchQueue.main.async {
                switch msgName {
                case "audioURL":
                    guard let audioStr = msgDict["url"], let audioURL = URL(string: audioStr) else { return }
                    
                    self.didCapturePlaybackURL(audioURL)
                default: break;
                }
            }
        } catch {
            NSLog("Failed to parse javascript bridge message: \(error.localizedDescription)")
        }
    }
    
    fileprivate func didPause() {
        guard fakeGenerator != nil else { return }
        
        NotificationCenter.default.post(name: Notification.Name.OvercastDidPause, object: self)
        
        DispatchQueue.main.async {
            self.fakeGenerator.suspend()
        }
    }
    
    fileprivate func didPlay() {
        if fakeGenerator == nil { fakeGenerator = FakeLoudnessDataGenerator(callback: callback) }
        
        NotificationCenter.default.post(name: Notification.Name.OvercastDidPlay, object: self)
        
        DispatchQueue.main.async {
            self.fakeGenerator.resume()
        }
    }
    
    fileprivate func didCapturePlaybackURL(_ url: URL) {
        NotificationCenter.default.post(name: .OvercastDidCapturePlaybackURL, object: url)
    }
    
}

private class FakeLoudnessDataGenerator {
    
    fileprivate let callback: (Double) -> ()
    fileprivate var timer: Timer!
    
    init(callback: @escaping (Double) -> ()) {
        self.callback = callback
    }
    
    func resume() {
        guard timer == nil else { return }
        
        timer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(generate), userInfo: nil, repeats: true)
    }
    
    func suspend() {
        guard timer != nil else { return }
        
        timer.invalidate()
        timer = nil
    }
    
    fileprivate var minValue = 22.0
    fileprivate var maxValue = 100.0
    fileprivate var stepValue = 4.0
    fileprivate var currentValue = 0.0
    fileprivate var direction = 1
    
    @objc fileprivate func generate() {
        let step = (stepValue + stepValue * drand48()) * Double(direction)
        currentValue += step
        
        if (currentValue >= maxValue) {
            direction = -1
        } else if (currentValue <= minValue) {
            direction = 1
        }
        
        callback(currentValue)
    }
}
