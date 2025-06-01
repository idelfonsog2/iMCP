//
//  Item.swift
//  Deets
//
//  Created by Idelfonso Gutierrez on 6/1/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
