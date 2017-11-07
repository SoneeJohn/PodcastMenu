//
//  PlaybackViewController.swift
//  PodcastMenu
//
//  Created by Guilherme Rambo on 01/10/17.
//  Copyright © 2017 Guilherme Rambo. All rights reserved.
//

import Cocoa
import AVKit

extension Notification.Name {
    static let PlaybackViewControllerDidRequestDismissal = Notification.Name("PlaybackViewControllerDidRequestDismissal")
}

final class PlaybackViewController: NSViewController {

    var playbackURL: URL? {
        didSet {
            guard oldValue != playbackURL else { return }
            playerView.player = AVPlayer(url: playbackURL!)
        }
    }
    @IBOutlet weak var playerView: AVPlayerView!
    
    static func instantiate() -> PlaybackViewController {
        let storyboard = NSStoryboard(name: "Playback", bundle: nil)
        
        return storyboard.instantiateInitialController() as! PlaybackViewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
    }
    
    @objc func play() {
        guard let url = playbackURL else { return }
        
        PlaybackManager.shared.play(from: url)
    }
    
    @objc func pause() {
        PlaybackManager.shared.pause()
    }
    @IBAction func dismissAction(_ sender: NSButton) {
        NotificationCenter.default.post(name: .PlaybackViewControllerDidRequestDismissal, object: nil)
    }
    
}
