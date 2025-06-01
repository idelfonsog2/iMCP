actor ContextAgent {
    private let weatherService = WeatherService.shared
    private let mapsService = MapsService.shared
    
    func suggestActivities(location: CLLocationCoordinate2D, radius: Double, timeSlot: DateInterval, preferences: [String]) async throws -> [ActivitySuggestion] {
        // Use existing MapsService to find nearby places
        let nearbyPlaces = try await mapsService.call(tool: "maps_explore", with: [
            "category": .string("restaurant"), // This would be dynamic based on timeSlot
            "latitude": .double(location.latitude),
            "longitude": .double(location.longitude),
            "radius": .double(radius)
        ])
        
        // Convert to suggestions with context
        var suggestions: [ActivitySuggestion] = []
        
        // Add weather context
        if await weatherService.isActivated {
            let weather = try await weatherService.call(tool: "weather_current", with: [
                "latitude": .double(location.latitude),
                "longitude": .double(location.longitude)
            ])
            
            // Use weather data to filter suggestions
        }
        
        return suggestions
    }
}