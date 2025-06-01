actor ParsingAgent {
    func parseInput(_ input: String, context: [String: Value]?) async throws -> ParsedActivity? {
        let lowercaseInput = input.lowercased()
        
        // Extract time information
        let timeResult = extractTime(from: input)
        
        // Extract location information
        let locationResult = extractLocation(from: input)
        
        // Determine activity type
        let category = determineCategory(from: input)
        
        // Extract activity name
        let name = extractActivityName(from: input, category: category)
        
        guard let startTime = timeResult.startTime else {
            return nil
        }
        
        let endTime = timeResult.endTime ?? startTime.addingTimeInterval(3600) // Default 1 hour
        
        return ParsedActivity(
            name: name,
            category: category,
            startTime: startTime,
            endTime: endTime,
            coordinate: locationResult.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
            locationName: locationResult.name ?? "TBD",
            estimatedDuration: endTime.timeIntervalSince(startTime),
            confidence: calculateConfidence(input: input, hasTime: timeResult.startTime != nil, hasLocation: locationResult.coordinate != nil),
            suggestions: generateSuggestions(for: input)
        )
    }
    
    private func extractTime(from input: String) -> (startTime: Date?, endTime: Date?) {
        // Parse various time formats: "8pm", "at 8", "8:30", "from 2 to 4", etc.
        let timePatterns = [
            #"(\d{1,2}):?(\d{2})?\s*(am|pm)"#,
            #"at\s+(\d{1,2}):?(\d{2})?"#,
            #"(\d{1,2})\s*(am|pm)"#
        ]
        
        for pattern in timePatterns {
            if let range = input.range(of: pattern, options: .regularExpression) {
                // Parse the matched time string
                // This is simplified - production would use more sophisticated parsing
                let timeString = String(input[range])
                if let date = parseTimeString(timeString) {
                    return (date, nil)
                }
            }
        }
        
        return (nil, nil)
    }
    
    private func extractLocation(from input: String) -> (coordinate: CLLocationCoordinate2D?, name: String?) {
        // Extract location names, addresses, or landmark references
        let locationKeywords = ["at", "in", "near", "by"]
        
        for keyword in locationKeywords {
            if let range = input.range(of: keyword + " ", options: .caseInsensitive) {
                let afterKeyword = String(input[range.upperBound...])
                let locationName = String(afterKeyword.prefix(while: { !$0.isWhitespace && !$0.isPunctuation }))
                return (nil, locationName)
            }
        }
        
        return (nil, nil)
    }
    
    private func determineCategory(from input: String) -> String {
        let categoryKeywords: [String: String] = [
            "dinner": "restaurant",
            "lunch": "restaurant", 
            "breakfast": "restaurant",
            "eat": "restaurant",
            "museum": "museum",
            "hotel": "accommodation",
            "flight": "transportation",
            "meeting": "business",
            "coffee": "cafe"
        ]
        
        for (keyword, category) in categoryKeywords {
            if input.localizedCaseInsensitiveContains(keyword) {
                return category
            }
        }
        
        return "activity"
    }
    
    private func extractActivityName(from input: String, category: String) -> String {
        // Extract the main activity name, removing time and location info
        var cleanedInput = input
        
        // Remove time patterns
        let timePatterns = [#"\d{1,2}:?\d{0,2}\s*(am|pm)"#, #"at\s+\d{1,2}"#]
        for pattern in timePatterns {
            cleanedInput = cleanedInput.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        
        // Remove location patterns
        let locationWords = ["at", "in", "near", "by"]
        for word in locationWords {
            if let range = cleanedInput.range(of: " " + word + " ", options: .caseInsensitive) {
                cleanedInput = String(cleanedInput[..<range.lowerBound])
            }
        }
        
        return cleanedInput.trimmingCharacters(in: .whitespacesAndPunctuation).capitalized
    }
    
    private func parseTimeString(_ timeString: String) -> Date? {
        // Simplified time parsing - production would be more robust
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        
        if let time = formatter.date(from: timeString) {
            // Combine with today's date
            let calendar = Calendar.current
            let now = Date()
            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
            return calendar.date(bySettingHour: timeComponents.hour ?? 0, minute: timeComponents.minute ?? 0, second: 0, of: now)
        }
        
        return nil
    }
    
    private func calculateConfidence(input: String, hasTime: Bool, hasLocation: Bool) -> Double {
        var confidence = 0.3 // Base confidence
        
        if hasTime { confidence += 0.4 }
        if hasLocation { confidence += 0.3 }
        
        return min(1.0, confidence)
    }
    
    private func generateSuggestions(for input: String) -> [String] {
        // Generate helpful suggestions for ambiguous input
        var suggestions: [String] = []
        
        if !input.contains(":") && !input.contains("am") && !input.contains("pm") {
            suggestions.append("Try adding a specific time, like 'at 7pm'")
        }
        
        if !input.contains("at") && !input.contains("in") {
            suggestions.append("Add a location like 'at the restaurant' or 'in downtown'")
        }
        
        return suggestions
    }
}