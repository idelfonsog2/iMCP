//
//  DeetsApp.swift
//  Deets
//
//  Created by Idelfonso Gutierrez on 6/1/25.
//

import SwiftUI
import SwiftData
import ComposableArchitecture

@main
struct DeetsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                        ._printChanges()
                }
            )
        }
        .modelContainer(sharedModelContainer)
    }
}
