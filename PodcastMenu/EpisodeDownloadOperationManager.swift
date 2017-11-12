//
//  EpisodeDownloadOperationManager.swift
//  PodcastMenu
//
//  Created by Soneé John on 11/11/17.
//  Copyright © 2017 Guilherme Rambo. All rights reserved.
//

import Foundation

class EpisodeDownloadOperationManager: NSObject {

    //MARK:- Properties
    
    fileprivate var operationsBacking: [EpisodeDownloadOperation]
    fileprivate let operationQueue: OperationQueue
    fileprivate let lock: NSRecursiveLock
    fileprivate let saveDirectory: URL
    
    var OperationDidChange: ((EpisodeDownloadOperation)->Void)?
    //MARK:- Init
    
     init?(saveDirectory: URL) {
        guard saveDirectory.hasDirectoryPath else { return nil }
        self.saveDirectory = saveDirectory
        operationsBacking = []
        operationQueue = OperationQueue()
        operationQueue.name = "EpisodeDownloadOperationManager Queue"
        lock = NSRecursiveLock()
        lock.name = "EpisodeDownloadOperationManager Lock"
        super.init()
    }
    
    public func addEpisode(_ episode: Episode, saveLocation: URL?) {
        let operation = EpisodeDownloadOperation(episode: episode, saveLocation: saveLocation ?? saveDirectory.appendingPathComponent("\(episode.title)"))
        guard operation != nil else { return }
        
        operation?.completionBlock = {
            self.evaluateFinishedOperation(operation!)
        }
        
        operationsBacking.append(operation!)
        operationQueue.addOperation(operation!)
    }
    
    fileprivate func evaluateFinishedOperation(_ operation: EpisodeDownloadOperation) {
      OperationDidChange?(operation)
    }
}
