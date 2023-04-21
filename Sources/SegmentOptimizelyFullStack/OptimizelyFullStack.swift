//
//  OptimizelyFullStackDestination.swift
//  OptimizelyFullStackDestination
//
//  Created by Komal Dhingra on 11/15/22.

// MIT License
//
// Copyright (c) 2021 Segment
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import Foundation
import Segment
import Optimizely

@objc(SEGOptimizelyFullStackDestination)
public class ObjCSegmentOptimizelyFullStack: NSObject, ObjCPlugin, ObjCPluginShim {
    private var optimizelyKey: String!
    private var experimentKey: String? = ""
    
    //call this function then call instance always
    public func initializeOptimizely(optimizelyKey: String, experimentKey: String? = ""){
        self.optimizelyKey = optimizelyKey
        self.experimentKey = experimentKey
    }
    
    public func instance() -> EventPlugin { return OptimizelyFullStack(optimizelyKey: optimizelyKey) }

}

public class OptimizelyFullStack: EventPlugin {
    
    public let timeline = Timeline()
    public let type = PluginType.enrichment
    public let key = "Optimizely X"
    public var analytics: Analytics? = nil
    
    private var optimizelySettings: OptimizelySettings?
    private var optimizelyClient: OptimizelyClient!
    private var userContext: OptimizelyUserContext!
    private var experimentationKey: String!
    
    public init(optimizelyKey: String, experimentKey: String? = "") {
        optimizelyClient = OptimizelyClient(sdkKey: optimizelyKey, defaultLogLevel: .debug)
        if let experimentKey = experimentKey {
            experimentationKey = experimentKey
        }
    }
    
    public func update(settings: Settings, type: UpdateType) {
        guard type == .initial else { return }
        
        guard let tempSettings: OptimizelySettings = settings.integrationSettings(forKey: key) else {
            return
        }

        optimizelySettings = tempSettings
        
        initializeOptimizelySDKAsynchronous()
    }
    
    private func initializeOptimizelySDKAsynchronous() {
                        
        addNotificationListeners()
        
        optimizelyClient.start { result in
            switch result {
            case .failure(let error):
                debugPrint("Optimizely SDK initiliazation failed: \(error)")
            case .success:
                debugPrint("Optimizely SDK initialized successfully!")
            }
        }
    }
    
    private func addNotificationListeners() {
        // notification listeners
        let notificationCenter = optimizelyClient.notificationCenter!
        
        if optimizelySettings?.listen == true {
            _ = notificationCenter.addDecisionNotificationListener(decisionListener: { (type, userId, attributes, decisionInfo) in
                let decisionInfoStr = (decisionInfo.compactMap({ (key, value) -> String in
                            return "\(key)=\(value)"
                        }) as Array).joined(separator: ";")
                let attributesStr = ((attributes?.compactMap({ (key, value) -> String in
                    return "\(key)=\(String(describing: value))"
                }) ?? []) as Array).joined(separator: ";")
                let properties: [String: Codable] = ["type": type,
                                                 "userId": userId,
                                                 "attributes": attributesStr,
                                                 "decisionInfo": decisionInfoStr]
                
                self.analytics?.track(name: "Experiment Viewed", properties: properties)
            })
        }
        
        _ = notificationCenter.addTrackNotificationListener(trackListener: { (eventKey, userId, attributes, eventTags, event) in
            debugPrint("Received track notification: \(eventKey) \(userId) \(String(describing: attributes)) \(String(describing: eventTags)) \(event)")
        })
        
        _ = notificationCenter.addDatafileChangeNotificationListener(datafileListener: { _ in
            if let optConfig = try? self.optimizelyClient.getOptimizelyConfig() {
                debugPrint("[OptimizelyConfig] revision = \(optConfig.revision)")
            }
        })
    }
    
    public func identify(event: IdentifyEvent) -> IdentifyEvent? {
        if let currentUserId = event.userId {
            userContext = self.optimizelyClient.createUserContext(userId: currentUserId)
        }
        
        return event
    }
    
    public func track(event: TrackEvent) -> TrackEvent? {
        
        let trackKnownUsers = optimizelySettings?.trackKnownUsers
        var userId = event.userId
        
        if userId == nil && (trackKnownUsers != nil && trackKnownUsers == true) {
            debugPrint("Segment will only track users associated with a userId when the trackKnownUsers setting is enabled.")
        }
        
        if trackKnownUsers == false {
            userId = event.anonymousId
        }
        
        if let userID = userId {
            //create user context and then call track
            userContext = optimizelyClient.createUserContext(userId: userID)
            trackUser(trackEvent: event)
            
            //To prevent loop of calling decide method, we are restricting it by below condition
            if event.event != "Experiment Viewed" {
                _ = userContext.decide(key: experimentationKey)
            }            
        }
        
        return event
    }
    
    private func trackUser(trackEvent: TrackEvent) {
        
        if let eventTags = trackEvent.properties?.dictionaryValue {
            do {
                try userContext.trackEvent(eventKey: trackEvent.event,
                                           eventTags: eventTags)
            } catch {
                
            }
        }
        else {
            do {
                try userContext.trackEvent(eventKey: trackEvent.event)
            } catch {
            }
        }
    }
    
    public func reset() {
        if optimizelyClient == nil {
            return
        }
        else {
            optimizelyClient.notificationCenter?.clearAllNotificationListeners()
        }
    }
}

extension OptimizelyFullStack: VersionedPlugin {
    public static func version() -> String {
        return __destination_version
    }
}

private struct OptimizelySettings: Codable {
    let periodicDownloadInterval: Int?
    let trackKnownUsers: Bool
    let listen: Bool
}
