//
//  EpisodeDownloadOperation.swift
//  PodcastMenu
//
//  Created by Soneé John on 11/8/17.
//  Copyright © 2017 Guilherme Rambo. All rights reserved.
//

import Foundation

//MARK: - Operation

extension EpisodeDownloadOperation {
    
    override var isExecuting: Bool { return state == .executing }
    override var isFinished: Bool { return state == .finished }
    
    fileprivate enum State: String {
        case ready = "Ready"
        case executing = "Executing"
        case finished = "Finished"
        fileprivate var keyPath: String { return "is" + self.rawValue }
    }
    
    
    override func start() {
        guard isCancelled == false else { return }
        state = .executing
        self.startRequest(url: episode.link!, type: .PlayPage)
    }
    
    override var isAsynchronous: Bool {
        get {
            return true
        }
    }
    
    override func cancel() {
        guard isCancelled == false || isFinished == false else { return }
        
        downloadTask?.cancel()
        dataTask?.cancel()
    }
    
}

extension EpisodeDownloadOperation {
    
    fileprivate enum RequestType: Int {
        case PlayPage = 0
        case Audio = 1
    }
}

extension EpisodeDownloadOperation: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try FileManager.default.moveItem(at: location, to: saveLocation)
        } catch  {
            //TODO: Finish with error
        }

         state = .finished
    }
}

class EpisodeDownloadOperation: Operation, NSCoding {
    func encode(with coder: NSCoder) {
        coder.encode(state, forKey: "state")
        coder.encode(episode, forKey: "episode")
        coder.encode(saveLocation, forKey: "saveLocation")
        coder.encode(identifier, forKey: "identifier")
    }
    
    required init?(coder decoder: NSCoder) {
        self.episode = decoder.decodeObject(forKey: "episode") as! Episode
        self.saveLocation = decoder.decodeObject(forKey: "saveLocation") as! URL
        self.state = decoder.decodeObject(forKey: "identifier") as! State
        self.identifier = decoder.decodeObject(forKey: "identifier") as! String
    }
    
    //MARK: - Properties
    
    public let episode: Episode
    public let saveLocation: URL
    fileprivate lazy var session: URLSession = {
        return URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)
    }()
    
    fileprivate var dataTask: URLSessionDataTask?
    fileprivate var downloadTask: URLSessionDownloadTask?
    
    public let identifier: String
    
    fileprivate var state = State.ready {
        willSet {
            willChangeValue(forKey: state.keyPath)
            willChangeValue(forKey: newValue.keyPath)
        }
        didSet {
            didChangeValue(forKey: state.keyPath)
            didChangeValue(forKey: oldValue.keyPath)
        }
    }
    
    //MARK: - Init
    
    init?(episode: Episode, saveLocation: URL) {
        guard episode.link != nil else { return nil }
        self.episode = episode
        self.saveLocation = saveLocation
        self.identifier = episode.link!.lastPathComponent
        super.init()

    }
    
    //MARK: - Request Dispatch
    
    fileprivate func startRequest(url: URL, type: RequestType) {
        guard type == .PlayPage else {
            //Create folder to store file
            do {
                try FileManager.default.createDirectory(at: saveLocation.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            } catch {
                //Folder couldn't be created, it makes no sense to continue operation
                //TODO: Finish with error
                return
            }
            
            downloadTask = session.downloadTask(with: url)
            downloadTask?.resume()
            return
        }
        
        dataTask = session.dataTask(with: url) { (data, response, error) in
            guard self.isCancelled == false else { return }
            guard error == nil else {
                 //TODO: Return and report error
                return
            }
            self.processResponse(response, data: data, error: error, type: type)
        }
        
        dataTask?.resume()
    }
    
    //MARK: - Response Dispatch
    
    fileprivate func processResponse(_ response: URLResponse?, data: Data?, error: Error?, type: RequestType) {
        guard data != nil else {
            //TODO: Return and report error
            return
        }
        
        guard error == nil else {
            //TODO: Return and report error
            return
        }
        self.processPlayPage(data: data, response: response!)
    }
    
    fileprivate func processPlayPage(data: Data?, response: URLResponse) {
        guard data != nil else { return /* TODO: Return and report error */ }
        guard response.textEncodingName != nil else { return /* TODO: Return and report error */ }
        
        let encoding = CFStringConvertIANACharSetNameToEncoding(response.textEncodingName! as CFString)
        let HTMLString = String(data: data!, encoding: String.Encoding(rawValue: UInt(encoding)))
        
        guard HTMLString != nil else { return /* TODO: Return and report error */ }
        
        let document = HTMLDocument.init(string: HTMLString!)
        let nodes = document.nodes(matchingSelector: "source")
        
        var audioURL: URL?
        
        nodes.forEach { (element) in
            let type = element.attributes["type"]
            guard type?.range(of: "audio") != nil else { return }
            guard let URLString = element.attributes["src"] else { return }
            guard let url = URL(string: URLString) else { return }
            
            audioURL = url
        }
        
        guard audioURL != nil else { return /* TODO: Return and report error */ }
        
        startRequest(url: audioURL!, type: .Audio)
    }
    
    //MARK:- NSObject
    
    override func isEqual(_ object: Any?) -> Bool {
        guard object != nil else { return false }
        guard object is EpisodeDownloadOperation == true else { return false }
        
        let obj = object as! EpisodeDownloadOperation
        return self.identifier == obj.identifier
   }
    
    override var hash : Int {
        return identifier.hashValue
    }
}
