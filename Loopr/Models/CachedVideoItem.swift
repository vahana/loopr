//
//  CachedVideoItem.swift
//  Loopr
//
//  Created by vahan on 2025-05-08.
//


import SwiftUI
import AVKit

// Model for cached video item display
struct CachedVideoItem: Identifiable {
    let id = UUID()
    let filename: String
    let url: URL
    let size: String
    let date: Date
}
