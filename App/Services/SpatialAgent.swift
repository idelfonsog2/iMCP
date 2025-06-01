actor SpatialAgent {
    private let mapsService = MapsService.shared
    private var routeCache: [String: RouteResult] = [:]
    
    func detectRoutingConflicts(_ activities: [TripActivity], transportMode: String) async throws -> [TravelConflict] {
        var conflicts: [TravelConflict] = []
        
        for i in 0..<(activities.count - 1) {
            let current = activities[i]
            let next = activities[i + 1]
            
            let routeKey = "\(current.id)-\(next.id)-\(transportMode)"
            
            let travelTime: TimeInterval
            if let cached = routeCache[routeKey] {
                travelTime = cached.duration
            } else {
                // Use existing MapsService to get travel time
                let result = try await mapsService.call(tool: "maps_eta", with: [
                    "originLatitude": .double(current.coordinate.latitude),
                    "originLongitude": .double(current.coordinate.longitude),
                    "destinationLatitude": .double(next.coordinate.latitude),
                    "destinationLongitude": .double(next.coordinate.longitude),
                    "transportType": .string(transportMode)
                ])
                
                if let routeData = result?.objectValue,
                   let duration = routeData["expectedTravelTime"]?.doubleValue {
                    travelTime = duration
                    routeCache[routeKey] = RouteResult(duration: duration, distance: 0)
                } else {
                    continue
                }
            }
            
            let availableTime = next.startTime.timeIntervalSince(current.endTime)
            let bufferTime: TimeInterval = 900 // 15 minutes buffer
            
            if travelTime + bufferTime > availableTime {
                conflicts.append(TravelConflict(
                    type: .impossibleTransition,
                    severity: .high,
                    description: "Not enough time to travel from \(current.name) to \(next.name)",
                    affectedActivityIds: [current.id, next.id],
                    recommendations: [
                        "Allow \(Int((travelTime + bufferTime) / 60)) minutes between activities",
                        "Consider rescheduling one of the activities",
                        "Use faster transportation if available"
                    ],
                    estimatedImpact: travelTime + bufferTime - availableTime
                ))
            }
        }
        
        return conflicts
    }
    
    func optimizeRoute(_ activities: [TripActivity], startLocation: CLLocationCoordinate2D?, transportMode: String) async throws -> RouteOptimization {
        // Implement traveling salesman problem solution for activity ordering
        let orderedActivities = try await solveRoutingProblem(activities, startLocation: startLocation, transportMode: transportMode)
        
        return RouteOptimization(
            optimizedOrder: orderedActivities.map { $0.id },
            timeSavings: 0, // Calculate actual savings
            totalDistance: 0, // Calculate total distance
            recommendations: generateRoutingRecommendations(orderedActivities),
            routeSegments: []
        )
    }
    
    private func solveRoutingProblem(_ activities: [TripActivity], startLocation: CLLocationCoordinate2D?, transportMode: String) async throws -> [TripActivity] {
        // Simple nearest neighbor algorithm for now
        // In production, use more sophisticated algorithms
        var remaining = activities
        var ordered: [TripActivity] = []
        var currentLocation = startLocation ?? activities.first?.coordinate
        
        while !remaining.isEmpty {
            let nearest = remaining.min { a, b in
                guard let current = currentLocation else { return true }
                let distA = distance(from: current, to: a.coordinate)
                let distB = distance(from: current, to: b.coordinate)
                return distA < distB
            }
            
            if let next = nearest {
                ordered.append(next)
                remaining.removeAll { $0.id == next.id }
                currentLocation = next.coordinate
            }
        }
        
        return ordered
    }
    
    private func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }
    
    private func generateRoutingRecommendations(_ activities: [TripActivity]) -> [String] {
        var recommendations: [String] = []
        
        if activities.count > 5 {
            recommendations.append("Consider grouping activities by neighborhood to reduce travel time")
        }
        
        return recommendations
    }
}