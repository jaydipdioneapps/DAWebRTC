// The Swift Programming Language
// https://docs.swift.org/swift-book


import Foundation
import WebRTC
import UIKit
import AVFoundation

public class DAWebRTC: NSObject {
    
    public weak var delegate: DAWebRTCDelegate?
    var peerConnectionFactory: RTCPeerConnectionFactory!
    var iceServers: [RTCIceServer] = []
    public var peerConnections: [String: RTCPeerConnection] = [:]
    var sdpConnection: [String: RTCSessionDescription] = [:]
    public var localVideoTrack: RTCVideoTrack?
    public var localAudioTrack: RTCAudioTrack?
    var streamId = "stream0"
    public var capturer: RTCCameraVideoCapturer?
    
    public var callInitiateType: CallInitiateType = .outgoing
    public var callType: CallType = .audio
    public var channelName: String? = nil
    public var isGroupId = ""
    public var isVideoMuted = false
    public var isAudioMuted = false
    public var isVideoEnabled : Bool = false
    public var isSpekerOn = false
    public var isHangOut = false
    public var arrIcCandidate: [ICECandidateShare] = []
    public var handlePendingHandleOffer: [String] = []
    var remoteDescriptionSet: Set<String> = []
    var pendingCandidates: [String: [RTCIceCandidate]] = [:]
    
    public var setRemoteVideoView: ((_ remoteVideoTrack: RTCVideoTrack) -> Void)?
    private var disconnectTimers: [String: Timer] = [:]
    public var remoteVideoViews: [String: RTCMTLVideoView] = [:]
    public var remoteVideoTracks: [String: RTCVideoTrack] = [:]
    public var secondsElapsed: Int = 0
    public var ringingTimer: Timer?
    public var selfTimer : Timer?
    public var timer: Timer?
    public var audioPlayer: AVAudioPlayer?
    public var giveTimerUpdateToUI = true
    public var updateCallTimer: (_ time: String) -> Void = { _  in }
    public var selfEndTimerObserver: (_ success: Bool) -> Void = { _ in }
    public var endCallWhenAllMemberLeaved: (_ success: Bool) -> Void = { _  in }
    
    public init(stunServer: String, turnServer: String, username: String, password: String, streamId: String) {
        super.init()
        setupPeerConnectionFactory()
        self.iceServers = [
            RTCIceServer(urlStrings: [stunServer]),
            RTCIceServer(urlStrings: [turnServer], username: username, credential: password),
        ]
        self.streamId = streamId
    }
    
    
    //MARK: - Setup peer connection factory
    private func setupPeerConnectionFactory() {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        peerConnectionFactory = RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }
    
    
    //MARK: - Create peer connection
    func createPeerConnection(for userId: String, type: CallType, isNeedToCreateNew : Bool = false) -> RTCPeerConnection? {
        if let peerConnection = peerConnections[userId], !isNeedToCreateNew {
            return peerConnection
        }
        
        let configuration = RTCConfiguration()
        configuration.iceServers = iceServers
        configuration.sdpSemantics = .unifiedPlan
        
        let constraints = RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": type == .video ? "true" : "false"
        ], optionalConstraints: nil)
        guard let peerConnection = self.peerConnectionFactory.peerConnection(with: configuration, constraints: constraints, delegate: nil) else {
            return nil
        }
        
        peerConnection.delegate = self
        
        if self.localAudioTrack == nil {
            self.localAudioTrack = self.peerConnectionFactory.audioTrack(withTrackId: "audio0")
        }
        peerConnection.add(self.localAudioTrack!, streamIds: [streamId])
        
        if type == .video {
            if self.localVideoTrack == nil {
                let videoSource = peerConnectionFactory.videoSource()
                self.localVideoTrack = peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
            }
            peerConnection.add(self.localVideoTrack!, streamIds: [streamId])
        }
        self.peerConnections[userId] = peerConnection
        return peerConnection
    }
    
    //MARK: - Setup local stream
    public func setupLocalStream(view: RTCMTLVideoView, type: CallType, isNeedToAddPeerConnection: Bool = false, user: String = "", completion: @escaping (Bool) -> Void) {
        if type == .audio {
            self.localAudioTrack = self.peerConnectionFactory.audioTrack(withTrackId: "audio0")
            completion(true)
        } else {
            let videoSource = peerConnectionFactory.videoSource()
            videoSource.adaptOutputFormat(toWidth: 640, height: 360, fps: 15)
            let cameraCapturer = RTCCameraVideoCapturer(delegate: videoSource)
            
            guard let camera = (RTCCameraVideoCapturer.captureDevices().first {
                $0.position == .front
            }) else {
                return
            }
            
            guard let format = camera.formats.last,
                  let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate else {
                completion(false)
                return
            }
            cameraCapturer.startCapture(with: camera, format: format, fps: Int(fps)) { error in
                if let error = error {
                    debugPrint("Error setting local description: \(error.localizedDescription)")
                    completion(false)
                } else {
                    self.capturer = cameraCapturer
                    self.localAudioTrack = self.peerConnectionFactory.audioTrack(withTrackId: "audio0")
                    self.localVideoTrack = self.peerConnectionFactory.videoTrack(with: videoSource, trackId: "video0")
                    if isNeedToAddPeerConnection {
                        if let peerConnection = self.peerConnections[user], let track = self.localVideoTrack {
                            peerConnection.add(track, streamIds: [self.streamId])
                        }
                    }
                    self.localVideoTrack?.add(view)
                    completion(true)
                }
            }
        }
    }
    
    //MARK: -  Create group call offer
    
    public func startCall(participants: [CallParticipant], channelName: String, groupId: String,
                       type: CallType, callInitiateType: CallInitiateType,
                       isInviting: Bool = false) {
        // Initialize call settings
        self.callInitiateType = callInitiateType
        self.callType = type
        self.channelName = channelName
        self.isGroupId = groupId
        
        // Create a dispatch group to synchronize offer creation
        let offerGroup = DispatchGroup()
        var arrOffer: [[String: String]] = []
        var offerErrors: [Error] = []
        
        // 1. First create all peer connections
        for participant in participants {
            _ = createPeerConnection(for: participant.id, type: type)
            
            offerGroup.enter()
            
            guard let peerConnection = peerConnections[participant.id] else {
                offerGroup.leave()
                continue
            }
            
            createOfferForParticipant(peerConnection: peerConnection, userId: participant.id) { result in
                switch result {
                case .success(let offerData):
                    arrOffer.append(offerData)
                case .failure(let error):
                    offerErrors.append(error)
                }
                offerGroup.leave()
            }
        }
        
        // 3. When all offers are created, send them together
        offerGroup.notify(queue: .main) {
            if !offerErrors.isEmpty {
                debugPrint("Error creating some offers: \(offerErrors)")
                // Handle partial failures if needed
            }
            
            if !arrOffer.isEmpty {
                self.delegate?.daWebRTC(self, didSendOffer: channelName, arrOffer: arrOffer, groupId: groupId, type: type, isInviting: isInviting)
            } else {
                debugPrint("No offers were created successfully")
                // Handle complete failure case
            }
        }
    }

    func createOfferForParticipant(peerConnection: RTCPeerConnection,
                                         userId: String,
                                         completion: @escaping (Result<[String: String], Error>) -> Void) {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": callType == .video ? "true" : "false"
            ],
            optionalConstraints: nil
        )
        
        peerConnection.offer(for: constraints) { sdp, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let sdp = sdp else {
                completion(.failure(NSError(domain: "WebRTC", code: -1, userInfo: [NSLocalizedDescriptionKey: "No SDP generated"])))
                return
            }
            
            peerConnection.setLocalDescription(sdp) { error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                let offerData = [
                    "type":"offer",
                    "sdp": sdp.sdp,
                    "userId": userId
                ]
                
                completion(.success(offerData))
            }
        }
    }
    
    //MARK: - Handle offer
    public func handleOffer(from userId: String, sdp: String, type: CallType, callInitiateType: CallInitiateType, isInviting: Bool, isRejoin: Bool) {
        if !isInviting {
            if type == .audio {
                isVideoMuted = false
                isVideoEnabled = false
            } else if type == .video {
                isVideoMuted = false
                isVideoEnabled = true
            }
        }
        self.callInitiateType = callInitiateType
        self.callType = type
        guard let peerConnection = createPeerConnection(for: userId, type: type) else { return }
        let remoteDescription = RTCSessionDescription(type: .offer, sdp: sdp)
        peerConnection.setRemoteDescription(remoteDescription) { error in
            if let error = error {
                debugPrint("Error setting local description: \(error.localizedDescription)")
                return
            }
            self.createAnswer(for: userId)
            self.delegate?.daWebRTC(self, pendingHandleOffer: userId, isInviting: isInviting, sdp: sdp, isRejoin: false, groupId: self.isGroupId)
        }
        if isRejoin {
            self.delegate?.daWebRTC(self, pendingHandleOffer: userId, isInviting: isInviting, sdp: sdp, isRejoin: isRejoin, groupId: self.isGroupId)
        }
    }
    
    //MARK: - Create Answer
    func createAnswer(for userId: String) {
        guard let peerConnection = peerConnections[userId] else { return }
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": callType == .video ? "true" : "false"
            ],
            optionalConstraints: nil
        )
        peerConnection.answer(for: constraints) { [weak self] answer, error in
            if let error = error {
                debugPrint("Error setting local description: \(error.localizedDescription)")
                return
            }
            
            guard let answer = answer else { return }
            
            peerConnection.setLocalDescription(answer) { error in
                if let error = error {
                    debugPrint("Error setting local description: \(error.localizedDescription)")
                    return
                }
                self?.delegate?.daWebRTC(self!, didCreateAnswer: self?.channelName ?? "", sdp: answer.sdp, recieverId: [userId].joined(separator: ","))
                self?.addIceCandidate(from: userId)
            }
        }
    }
    
    func addIceCandidate(from userId: String) {
        if userId == streamId {
            return
        }
        guard let peerConnection = peerConnections[userId] else { return }
        if let pendingCandidate = self.arrIcCandidate.first(where: { $0.userId == userId }) {
            pendingCandidate.candidate.forEach { candidate in
                peerConnection.add(candidate) { error in
                    debugPrint("addIceCandidate \(userId)  \(error?.localizedDescription ?? "")")
                }
            }
            sendICECandidate(userId: userId)
        }
    }

    func sendICECandidate(userId: String) {
        let pending = arrIcCandidate.filter( { $0.userId == userId } )
        pending.forEach { pendingCandidate in
            pendingCandidate.candidate.forEach { candidate in
                let candidate = ["sdp": candidate.sdp, "sdpMid": candidate.sdpMid ?? "", "sdpMLineIndex": candidate.sdpMLineIndex] as [String : Any]
                self.delegate?.daWebRTC(self, didGenerateCandidate: self.channelName ?? "", recieverId: [pendingCandidate.userId].joined(separator: ","), candidate: candidate)
            }
        }
        arrIcCandidate.removeAll(where: { $0.userId == userId })
    }
    
    public func createNewConnections(userId: String, isAudioToVideo : Bool = false, isNeedToCreateNew: Bool = false, isVideoCallRequestAccepted: Bool = false) {
        if isAudioToVideo {
            peerConnections.removeAll()
            sdpConnection.removeAll()
        }
        self.remoteDescriptionSet.remove(userId)
        if !isNeedToCreateNew {
            if peerConnections.contains(where: { $0.key == userId }) { return }
        }
        
        guard let peerConnection = createPeerConnection(for: userId, type: callType, isNeedToCreateNew: isNeedToCreateNew) else { return }
        // Create an SDP offer for this participant
        peerConnection.offer(for: RTCMediaConstraints(mandatoryConstraints: [
            "OfferToReceiveAudio": "true",
            "OfferToReceiveVideo": callType == .video ? "true" : "false"
        ], optionalConstraints: nil)) { [weak self] sdp, error in
            guard let sdp = sdp, error == nil else {
                return
            }
            self?.sdpConnection[userId] = sdp
            peerConnection.setLocalDescription(sdp, completionHandler: { error in
                if let error = error {
                    debugPrint("Error setting local description: \(error.localizedDescription)")
                }
            })
            
            self?.delegate?.daWebRTC(self!, didCreateOffer: self?.channelName ?? "", sdp: sdp.sdp, recieverId: [userId].joined(separator: ","), isAudioToVideo: isAudioToVideo || isNeedToCreateNew ? "true" : "false", videoCallRequestAccepted: isVideoCallRequestAccepted ? "true" : "false")
        }
    }
    
    public func handleAnswer(from userId: String, sdp: String) {
        guard let peerConnection = peerConnections[userId] else { return }
        let remoteDescription = RTCSessionDescription(type: .answer, sdp: sdp)
        peerConnection.setRemoteDescription(remoteDescription) { error in
            if let error = error {
                debugPrint("WEBRTC: Error setting remote answer for \(userId): \(error.localizedDescription)")
                return
            }

            self.remoteDescriptionSet.insert(userId)
            self.flushPendingCandidates(for: userId)
        }
    }
    
    public func handleNewICECandidate(from userId: String, candidateData: RTCIceCandidate) {
        guard let peerConnection = peerConnections[userId] else {
            pendingCandidates[userId, default: []].append(candidateData)
            return
        }
        
        if !remoteDescriptionSet.contains(userId) {
            pendingCandidates[userId, default: []].append(candidateData)
            return
        }
        
        applyIceCandidate(candidateData, to: peerConnection, for: userId)
    }

    // Should be called after remoteDescription is set
    func flushPendingCandidates(for userId: String) {
        guard let peerConnection = peerConnections[userId] else { return }
        guard remoteDescriptionSet.contains(userId) else {
            return
        }
        let candidates = pendingCandidates[userId] ?? []
        for candidate in candidates {
            applyIceCandidate(candidate, to: peerConnection, for: userId)
        }
        pendingCandidates[userId] = []
    }

    func applyIceCandidate(_ candidate: RTCIceCandidate, to peerConnection: RTCPeerConnection, for userId: String) {
        peerConnection.add(candidate) { error in
            if let error = error {
                debugPrint("Failed to add ICE candidate for \(userId): \(error.localizedDescription)")
                self.pendingCandidates[userId, default: []].append(candidate)
            } else {
                debugPrint("[ICE] Successfully added ICE candidate for \(userId)")
            }
        }
    }
    
    //MARK: - Share ICE-Candidate
    
    func shareICECandidate(candidate: RTCIceCandidate, to userId: String) {
        guard let channelName = self.channelName else {
            debugPrint("Channel name not set when trying to share ICE candidate")
            return
        }
        debugPrint("Channel name : \(channelName)")
        let candidateObj = ["sdp": candidate.sdp, "sdpMid": candidate.sdpMid ?? "", "sdpMLineIndex": candidate.sdpMLineIndex] as [String : Any]
        
        self.delegate?.daWebRTC(self, didGenerateCandidate: self.channelName ?? "", recieverId: [userId].joined(separator: ","), candidate: candidateObj)
        
        if let index = arrIcCandidate.firstIndex(where: { $0.userId ==  userId}) {
            arrIcCandidate[index].candidate.append(candidate)
        } else {
            arrIcCandidate.append(ICECandidateShare(userId: userId, candidate: [candidate]))
        }
    }
    
    public func handleRejoin(for userId: String) {
        handleParticipantLeave(userId: userId)
        arrIcCandidate.removeAll(where: { $0.userId == userId })
        createNewConnections(userId: userId)
    }
    
    public func sendOfferFromSDP(sdp: RTCSessionDescription, userId: String) {
        delegate?.daWebRTC(self, sendOfferFromSDP: self.channelName ?? "", sdp: sdp.sdp, recieverId: [userId].joined(separator: ","))
    }
    
    public func handleIncomingOffer(_ offer: RTCSessionDescription, from userId: String) {
        if callType == .audio && self.localAudioTrack == nil {
            self.handlePendingHandleOffer.append(userId)
        } else if callType == .video && self.localVideoTrack == nil {
            self.handlePendingHandleOffer.append(userId)
        } else {
            if let peerConnection = peerConnections[userId] {
                setRemoteDescriptionForhandleIncomingOffer(offer, peerConnection: peerConnection, userId: userId)
            } else {
                guard let peerConnection = createPeerConnection(for: userId, type: callType) else { return }
                setRemoteDescriptionForhandleIncomingOffer(offer, peerConnection: peerConnection, userId: userId)
            }
        }
    }
    
    func setRemoteDescriptionForhandleIncomingOffer(_ offer: RTCSessionDescription, peerConnection: RTCPeerConnection, userId: String) {
        peerConnection.setRemoteDescription(offer) { error in
            if let error = error {
                debugPrint("WEBRCT DELEGATE : Error setting local description: \(error.localizedDescription)")
                return
            }
            self.remoteDescriptionSet.insert(userId)
            self.flushPendingCandidates(for: userId)
            self.createAnswer(for: userId)
        }
    }
    
    public func restartICECandidates() {
        self.peerConnections.keys.forEach { userId in
            self.handleParticipantLeave(userId: userId)
            self.remoteDescriptionSet.remove(userId)
            self.createNewConnections(userId: userId, isNeedToCreateNew: true)
        }
    }
    
    public func handleNetworkDisconnection(userId: String, isSelfUser: Bool = false) {
        // Already scheduled
        if disconnectTimers[userId] != nil {
            return
        }
        
        let timer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            if !isSelfUser {
                delegate?.daWebRTC(self, didDisconnectedUser: self.channelName ?? "", userId: userId, duration: secondsElapsed)
                handleParticipantLeave(userId: userId, isLeave: true)
            } else {
                hangOut()
            }
            self.disconnectTimers.removeValue(forKey: userId)
        }
        
        disconnectTimers[userId] = timer
    }

    public func cancelDisconnectTimer(userId: String) {
        disconnectTimers[userId]?.invalidate()
        disconnectTimers.removeValue(forKey: userId)
    }
    
    //MARK: - Setup remote video view
    private func setupRemoteVideoView(_ remoteVideoTrack: RTCVideoTrack) {
        self.setRemoteVideoView?(remoteVideoTrack)
    }
    
    public func handleParticipantLeave(userId: String, isLeave: Bool = false) {
        
        if isLeave {
            if userId != streamId {
                delegate?.daWebRTC(self, handleParticipantIsLeave: channelName ?? "", userId: userId, isLeave: isLeave)
            }
        }
        
        // 1. Close the peer connection for the user
        if let peerConnection = peerConnections[userId] {
            peerConnection.close()
            peerConnections.removeValue(forKey: userId)
        }
        
        // 2. Remove their video feed from the UI
        if let remoteVideoView = remoteVideoViews[userId] {
            DispatchQueue.main.async {
                remoteVideoView.removeFromSuperview()
            }
            remoteVideoViews.removeValue(forKey: userId)
        }
        
        if let tracks = remoteVideoTracks[userId] {
            tracks.isEnabled = false
        }
        remoteVideoTracks.removeValue(forKey: userId)
        cancelDisconnectTimer(userId: userId)
    }
    
    // Method to end the call
    public func hangOut() {
        var arrPeerConnectionId = [String]()
        
        self.peerConnections.keys.forEach { userId in
            if userId != streamId {
                arrPeerConnectionId.append(userId)
            }
        }
        
        delegate?.daWebRTC(self, callCut: self.channelName ?? "", recieverId: arrPeerConnectionId.joined(separator: ","))
        // Clean up all peer connections and UI elements
        for peerConnection in peerConnections.values {
            peerConnection.close()
        }
        peerConnections.removeAll()
        
        for remoteVideoView in remoteVideoViews.values {
            DispatchQueue.main.async {
                remoteVideoView.removeFromSuperview()
            }
        }
        remoteVideoViews.removeAll()
        
        capturer?.stopCapture()
        capturer = nil
                
        arrIcCandidate.removeAll()
        remoteVideoTracks.removeAll()
        remoteDescriptionSet.removeAll()
        pendingCandidates.removeAll()
        localVideoTrack = nil
        localAudioTrack = nil
        isHangOut = true
        // Update UI to show end of call message, etc.
    }
    
    // MARK: - Mute/Unmute Audio
    
    public func enableAudio() {
        isAudioMuted = false
        localAudioTrack?.isEnabled = true
        sendAudioMuteStatus(isMuted: false)
    }

    public func disableAudio() {
        isAudioMuted = true
        localAudioTrack?.isEnabled = false
        sendAudioMuteStatus(isMuted: true)
    }

    func sendAudioMuteStatus(isMuted: Bool) {
        var arrPeerConnectionId = [String]()
        self.peerConnections.keys.forEach { userId in
            if userId != streamId {
                arrPeerConnectionId.append(userId)
            }
        }
        delegate?.daWebRTC(self, sendAudioMuteStatus: self.channelName ?? "", recieverId: arrPeerConnectionId.joined(separator: ","), audioMuted: isMuted ? "true" : "false")
    }
    
    // MARK: - Video enable/disable
    
    public func enableVideo() {
        localVideoTrack?.isEnabled = true
        isVideoMuted = false
        var arrPeerConnectionId = [String]()
        self.peerConnections.keys.forEach { userId in
            if userId != streamId {
                arrPeerConnectionId.append(userId)
            }
        }
        delegate?.daWebRTC(self, sendVideoMuteStatus: self.channelName ?? "", recieverId: arrPeerConnectionId.joined(separator: ","), videoMuted: "false")
    }
    
    public func disableVideo() {
        localVideoTrack?.isEnabled = false
        isVideoMuted = true
        var arrPeerConnectionId = [String]()
        self.peerConnections.keys.forEach { userId in
            if userId != streamId {
                arrPeerConnectionId.append(userId)
            }
        }
        delegate?.daWebRTC(self, sendVideoMuteStatus: self.channelName ?? "", recieverId: arrPeerConnectionId.joined(separator: ","), videoMuted: "true")
    }
    
    // Turn speaker on
    public func enableSpeaker() {
        isSpekerOn = true
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            debugPrint("Error enabling speaker: \(error.localizedDescription)")
        }
    }
    
    // Turn speaker off (use earpiece)
    public func disableSpeaker() {
        isSpekerOn = false
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
            try audioSession.overrideOutputAudioPort(.none) // Route audio to earpiece
            try audioSession.setActive(true)
        } catch {
            debugPrint("Error disabling speaker: \(error.localizedDescription)")
        }
    }
    
    // Toggle speaker state
    public func toggleSpeaker(isOn: Bool) {
        if isOn {
            enableSpeaker()
        } else {
            disableSpeaker()
        }
    }
    
    // MARK: - Switch Camera
    
    public func switchCamera() {
        guard let capturer = self.capturer else { return }
        
        let currentPosition = capturer.captureSession.inputs
            .compactMap { ($0 as? AVCaptureDeviceInput)?.device.position }
            .first ?? .front
        
        let newPosition: AVCaptureDevice.Position = (currentPosition == .front) ? .back : .front
        
        guard let newCamera = RTCCameraVideoCapturer.captureDevices().first(where: { $0.position == newPosition }) else {
            return
        }
        
        guard let format = newCamera.formats.last, // Use the highest resolution format
              let fps = format.videoSupportedFrameRateRanges.first?.maxFrameRate else {
            return
        }
        
        capturer.startCapture(with: newCamera, format: format, fps: Int(fps)) { error in
            if let error = error {
                debugPrint("Error switching camera: \(error.localizedDescription)")
            } else {
                debugPrint("Camera switched successfully to \(newPosition == .front ? "front" : "back")")
            }
        }
    }
    
    public func switchLocalToRemoteVideoView(localView: RTCMTLVideoView, remoteView: RTCMTLVideoView, userId: String) {
        guard let remoteTracks = remoteVideoTracks[userId] else {
            return
        }
        
        let remoteVideoTrack = remoteTracks // Assuming one remote track per user
        
        localVideoTrack?.remove(localView)
        remoteVideoTrack.add(localView)
        
        // Show local video in smaller remote view
        remoteVideoTrack.remove(remoteView)
        localVideoTrack?.add(remoteView)
    }
    
}

//MARK: - RTCPeerConnectionDelegate delegete method

extension DAWebRTC: RTCPeerConnectionDelegate {
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        
        guard let userId = self.peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
        var isConnectedSuccess = false
        if let videoTrack = stream.videoTracks.first {
            self.remoteVideoTracks[stream.streamId] = videoTrack
            self.setupRemoteVideoView(videoTrack)
            isConnectedSuccess = true
        } else {
            if self.callType == CallType.video {
                self.restartICECandidates()
            }
        }
        if stream.audioTracks.first != nil {
            isConnectedSuccess = true
        } else {
            if self.callType == CallType.audio {
                self.restartICECandidates()
            }
        }
        if isConnectedSuccess {
            self.sendICECandidate(userId: userId)
            if userId != streamId {
                self.stopPlayingRingingSound()
                self.stopSelfTimer()
                self.startTimer()
                delegate?.daWebRTC(self, updateUserCallStatus: channelName ?? "", userId: userId, joinedStatus: true, isActive: true)
            }
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    
    public func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        guard let userId = self.peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
        switch newState {
        case .disconnected:
            self.handleNetworkDisconnection(userId: userId)
            break
        case .failed:
            break
        case .closed:
            break
        case .connected:
            self.cancelDisconnectTimer(userId: userId)
            break
        default:
            break
        }
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        guard let userId = self.peerConnections.first(where: { $0.value == peerConnection })?.key else { return }
        self.shareICECandidate(candidate: candidate, to: userId)
    }
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    
    public func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

extension DAWebRTC {
    public func stopPlayingRingingSound() {
        ringingTimer?.invalidate()
        ringingTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }
    
    public func stopSelfTimer() {
        if selfTimer != nil {
            self.selfTimer?.invalidate()
            self.selfTimer = nil
        }
    }
    
    public func startTimer() {
        if (timer != nil) { return }
        timer = Timer.scheduledTimer(timeInterval:  1.0, target: self, selector: #selector(updateTimer), userInfo: nil, repeats: true)
    }
    
    @objc func updateTimer() {
        // Increment the elapsed time
        secondsElapsed += 1
        // Update the timer label
        updateTimerLabel()
    }
    
    public func updateTimerLabel() {
        if giveTimerUpdateToUI {
            let hours = secondsElapsed / 3600
            let minutes = (secondsElapsed / 60) % 60
            let seconds = secondsElapsed % 60
            if hours > 0 {
                self.updateCallTimer(String(format: "%0.2d:%0.2d:%0.2d", hours, minutes, seconds))
            } else {
                self.updateCallTimer(String(format: "%02d:%02d", minutes, seconds))
            }
        }
    }
    
    ///Ringing setups
    public func startPlayingRingingSoundRepeatedly() {
        stopPlayingRingingSound()
        playRingingSound() // Play immediately
        ringingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.playRingingSound()
        }
    }
    
    public func playRingingSound() {
        guard let soundURL = Bundle.main.url(forResource: "ringing", withExtension: "aac") else {
            print("Failed to find ringing.wav in the bundle")
            return
        }
        do {
            // Initialize AVAudioPlayer with the sound URL
            self.audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            self.audioPlayer?.numberOfLoops = -1 // Loop indefinitely
            self.audioPlayer?.prepareToPlay()
            self.audioPlayer?.play()
        } catch {
            print("Error initializing AVAudioPlayer: \(error)")
        }
    }
    
    // Stop the timer when it's no longer needed, e.g., when the call ends
    public func stopTimer(fromOffline: Bool = false) {
        delegate?.daWebRTC(self, callEnded: true)
        if self.timer != nil {
            self.timer?.invalidate()
            self.timer = nil
        }
        self.stopPlayingRingingSound()
        self.isAudioMuted = false
        if !self.isHangOut {
            self.hangOut()
        }
    }
    
    public func startSelfTimer() {
        stopSelfTimer()
        selfTimer = Timer.scheduledTimer(timeInterval: 90, target: self, selector: #selector(self.handleCallEndTimer(_:)), userInfo: nil, repeats: false)
    }
    
    @objc func handleCallEndTimer(_ timer: Timer) {
        secondsElapsed = 0
        selfEndTimerObserver(true)
    }

}
