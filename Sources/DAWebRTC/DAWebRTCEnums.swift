//
//  DAWebRTCEnums.swift
//  DAWebRTC
//
//  Created by Jekil Dabhoya on 29/04/25.
//


import Foundation

public enum CallType: String {
    case audio
    case video
}

public enum CallInitiateType: String {
    case incoming = "Incoming"
    case outgoing = "Outgoing"
    case missed = "Missed"
}
