//
//  DAWebRTCModels.swift
//  DAWebRTC
//
//  Created by Jekil Dabhoya on 29/04/25.
//

import Foundation
import WebRTC

public struct ICECandidateShare {
    let userId: String
    var candidate: [RTCIceCandidate] = []
}

public struct CallParticipant {
    public let id: String
    public let name: String?
    public internal(set) var isConnected: Bool
    
    public init(id: String, name: String? = nil, isConnected: Bool = false) {
        self.id = id
        self.name = name
        self.isConnected = isConnected
    }
}
