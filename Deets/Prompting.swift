//
//  Prompting.swift
//  Deets
//
//  Created by Idelfonso Gutierrez on 6/14/25.
//

import Foundation
import FoundationModels
import Playgrounds

@available(iOS 26.0, *)
#Playground {
    let session = LanguageModelSession()
    let response = try await session.respond(to: "Whats a good name for a trip to Japan?")
    response.content
}
