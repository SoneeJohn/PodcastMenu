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
    override var isExecuting : Bool {
        get { return _executing }
    }
    
    override var isFinished : Bool {
        get { return _finished }
    }
    
    override func start() {
        guard isCancelled == false else { return }
        _executing = true
        
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

//MARK:- KVO

extension EpisodeDownloadOperation {
    override class func automaticallyNotifiesObservers(forKey key: String) -> Bool {
   
        if key == "isExecuting" || key == "isFinished" {
            return true
        }
        
        return super.automaticallyNotifiesObservers(forKey: key)
    }
}

extension EpisodeDownloadOperation {
    
    fileprivate enum RequestType: Int {
        case PlayPage = 0
        case Audio = 1
    }
}

extension Equatable {
    static func == (lhs: EpisodeDownloadOperation, rhs: EpisodeDownloadOperation) -> Bool {
        return lhs.identifier == rhs.identifier && lhs.episode == rhs.episode
    }
}

extension EpisodeDownloadOperation: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            try FileManager.default.moveItem(at: location, to: saveLocation)
        } catch  {
            //TODO: Finish with error
        }
        
         _finished = true
         _executing = false
    }
}

class EpisodeDownloadOperation: Operation, NSCoding {
    func encode(with coder: NSCoder) {
        coder.encode(_executing, forKey: "_executing")
        coder.encode(_finished, forKey: "_finished")
        coder.encode(episode, forKey: "episode")
        coder.encode(saveLocation, forKey: "saveLocation")
        coder.encode(identifier, forKey: "identifier")
    }
    
    required init?(coder decoder: NSCoder) {
        self.episode = decoder.decodeObject(forKey: "episode") as! Episode
        self._executing = decoder.decodeBool(forKey: "_executing")
        self._finished = decoder.decodeBool(forKey: "_finished")
        self.saveLocation = decoder.decodeObject(forKey: "saveLocation") as! URL
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

    fileprivate var _executing : Bool = false
    fileprivate var _finished : Bool = false
    
    public let identifier: String
    
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
                try FileManager.default.createDirectory(at: saveLocation, withIntermediateDirectories: true, attributes: nil)
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
