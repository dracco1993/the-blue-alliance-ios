//
//  PlayerView.swift
//  the-blue-alliance-ios
//
//  Created by Zach Orr on 5/22/17.
//  Copyright © 2017 The Blue Alliance. All rights reserved.
//

import Foundation
import UIKit
import youtube_ios_player_helper
import PureLayout

class PlayerView: UIView {
    
    public var media: Media? {
        didSet {
            configureView()
        }
    }
    
    private var youtubePlayerView: YTPlayerView = {
        let youtubePlayerView = YTPlayerView()
        youtubePlayerView.translatesAutoresizingMaskIntoConstraints = false
        return youtubePlayerView
    }()
    
    fileprivate var loadingActivityIndicator: UIActivityIndicatorView = {
        let activityIndicator = UIActivityIndicatorView()
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        return activityIndicator
    }()
    
    private func configureView() {
        if youtubePlayerView.superview == nil {
            youtubePlayerView.delegate = self
            addSubview(youtubePlayerView)
            youtubePlayerView.autoPinEdgesToSuperviewEdges()
        }
        
        if loadingActivityIndicator.superview == nil {
            addSubview(loadingActivityIndicator)
            loadingActivityIndicator.autoCenterInSuperview()
        }
        
        loadingActivityIndicator.startAnimating()
        
        if media?.type! == MediaType.youtubeVideo.rawValue {
            // TODO: Taking this from the Android app... need to finish this up
            /* Need to account for timestamps in youtube foreign key
             * Can be like <key>?start=1h15m3s or <key>?t=time or <key>#t=time
             * Since foreign key is first param in yt.com/watch?v=blah, others need to be &
             */
            /*
            keyForUrl = foreignKey.replace('?', '&').replace('#', '&');
            Matcher m = YOUTUBE_KEY_PATTERN.matcher(foreignKey);
            String cleanKey = m.find() ? m.group(1) : foreignKey;
            imageUrl = String.format(mediaType.getImageUrlPattern(), cleanKey);
             */
            if let key = media?.key {
                youtubePlayerView.load(withVideoId: key)
            }
            if let foreignKey = media?.foreignKey {
                youtubePlayerView.load(withVideoId: foreignKey)
            }
        }
    }
    
}

extension PlayerView: YTPlayerViewDelegate {

    func playerViewPreferredInitialLoading(_ playerView: YTPlayerView) -> UIView? {
        let view = UIView()
        view.backgroundColor = .black
        return view
    }
    
    func playerViewDidBecomeReady(_ playerView: YTPlayerView) {
        loadingActivityIndicator.stopAnimating()
    }

}
