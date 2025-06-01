actor TemporalAgent {
    private let calendarService = CalendarService.shared
    
    func detectSchedulingConflicts(_ activities: [TripActivity]) async throws -> [TravelConflict] {
        var conflicts: [TravelConflict] = []
        
        // Check for overlapping activities
        for i in 0..<activities.count {
            for j in (i+1)..<activities.count {
                let activity1 = activities[i]
                let activity2 = activities[j]
                
                if activitiesOverlap(activity1, activity2) {
                    conflicts.append(TravelConflict(
                        type: .scheduleOverlap,
                        severity: .high,
                        description: "\(activity1.name) overlaps with \(activity2.name)",
                        affectedActivityIds: [activity1.id, activity2.id],
                        recommendations: [
                            "Adjust timing of one activity",
                            "Consider shorter duration for one activity"
                        ],
                        estimatedImpact: overlapDuration(activity1, activity2)
                    ))
                }
            }
        }
        
        // Check against existing calendar events
        if await calendarService.isActivated {
            let conflicts = try await checkCalendarConflicts(activities)
            conflicts.append(contentsOf: conflicts)
        }
        
        return conflicts
    }
    
    private func activitiesOverlap(_ a1: TripActivity, _ a2: TripActivity) -> Bool {
        return a1.startTime < a2.endTime && a2.startTime < a1.endTime
    }
    
    private func overlapDuration(_ a1: TripActivity, _ a2: TripActivity) -> TimeInterval {
        let overlapStart = max(a1.startTime, a2.startTime)
        let overlapEnd = min(a1.endTime, a2.endTime)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
    
    private func checkCalendarConflicts(_ activities: [TripActivity]) async throws -> [TravelConflict] {
        // Check against user's calendar for conflicts
        // Implementation would use CalendarService to fetch events
        return []
    }
}