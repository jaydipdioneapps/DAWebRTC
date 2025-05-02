//
//  DAWebRTCDelegate.swift
//  DAWebRTC
//
//  Created by Jekil Dabhoya on 29/04/25.
//

import Foundation

public protocol DAWebRTCDelegate: AnyObject {
    func daWebRTC(_ manager: DAWebRTC, didSendOffer channelName: String, arrOffer: [[String: String]], groupId: String?, type: CallType, isInviting: Bool)
    func daWebRTC(_ manager: DAWebRTC, didCreateAnswer channelName: String, sdp: String, recieverId: String)
    func daWebRTC(_ manager: DAWebRTC, didGenerateCandidate channelName: String, recieverId: String, candidate: [String: Any])
    func daWebRTC(_ manager: DAWebRTC, pendingHandleOffer userId: String, isInviting: Bool, sdp: String, isRejoin: Bool, groupId: String)
    func daWebRTC(_ manager: DAWebRTC, didCreateOffer channelName: String, sdp: String, recieverId: String, isAudioToVideo: String, videoCallRequestAccepted: String)
    func daWebRTC(_ manager: DAWebRTC, sendOfferFromSDP channelName: String, sdp: String, recieverId: String)
    func daWebRTC(_ manager: DAWebRTC, callCut channelName: String, recieverId: String)
    func daWebRTC(_ manager: DAWebRTC, didDisconnectedUser channelName: String, userId: String, duration: Int)
    func daWebRTC(_ manager: DAWebRTC, sendAudioMuteStatus channelName: String, recieverId: String, audioMuted: String)
    func daWebRTC(_ manager: DAWebRTC, sendVideoMuteStatus channelName: String, recieverId: String, videoMuted: String)
    func daWebRTC(_ manager: DAWebRTC, updateUserCallStatus channelName: String, userId: String, joinedStatus: Bool, isActive: Bool)
    func daWebRTC(_ manager: DAWebRTC, callEnded isCallEnded: Bool)
    func daWebRTC(_ manager: DAWebRTC, handleParticipantIsLeave channelName: String, userId: String, isLeave: Bool)
}
