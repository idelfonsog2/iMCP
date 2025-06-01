//
//  DeetsApp.swift
//  Deets
//
//  Created by Idelfonso Gutierrez on 6/1/25.
//

import SwiftUI
import SwiftData
import ComposableArchitecture
import MapKit
import CoreLocation

@main
struct DeetsApp: App {    
    var body: some Scene {
        WindowGroup {
            AppView(
                store: Store(initialState: AppFeature.State()) {
                    AppFeature()
                }
            )
        }
    }
}

// MARK: - App Feature (Root)

@Reducer
struct AppFeature: Reducer {
    @ObservableState
    struct State: Equatable {
        var currentTrip: TripFeature.State?
        var tripsList: TripsListFeature.State = TripsListFeature.State()
        var importFlow: ImportFeature.State = ImportFeature.State()
        var selectedTab: Tab = .timeline
        
        enum Tab: CaseIterable {
            case map, timeline, list, importDoc
            
            var title: String {
                switch self {
                case .map: return "Map"
                case .timeline: return "Timeline"
                case .list: return "Plans"
                case .importDoc: return "Import"
                }
            }
            
            var icon: String {
                switch self {
                case .map: return "map.fill"
                case .timeline: return "calendar"
                case .list: return "list.bullet"
                case .importDoc: return "square.and.arrow.down"
                }
            }
        }
    }
    
    enum Action {
        case tabSelected(State.Tab)
        case trip(TripFeature.Action)
        case tripsList(TripsListFeature.Action)
        case importFlow(ImportFeature.Action)
        case loadSampleTrip
        case selectTrip(TravelTrip)
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                state.selectedTab = tab
                return .none
                
            case .loadSampleTrip:
                let sampleTrip = TravelTrip.sampleParis
                state.currentTrip = TripFeature.State(trip: sampleTrip)
                return .none
                
            case let .selectTrip(trip):
                state.currentTrip = TripFeature.State(trip: trip)
                return .none
                
            case .trip, .tripsList, .importFlow:
                return .none
            }
        }
        .ifLet(\.currentTrip, action: \.trip) {
            TripFeature()
        }
        .ifLet(\.tripsList, action: \.tripsList) {
            TripsListFeature()
        }
        .ifLet(\.importFlow, action: \.importFlow) {
            ImportFeature()
        }
    }
}

// MARK: - App View

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    
    var body: some View {
        TabView(selection: $store.selectedTab.sending(\.tabSelected)) {
            ForEach(AppFeature.State.Tab.allCases, id: \.self) { tab in
                tabContent(for: tab)
                    .tabItem {
                        Image(systemName: tab.icon)
                        Text(tab.title)
                    }
                    .tag(tab)
            }
        }
        .onAppear {
            store.send(.loadSampleTrip)
        }
    }
    
    @ViewBuilder
    private func tabContent(for tab: AppFeature.State.Tab) -> some View {
        switch tab {
        case .map:
            if let tripStore = store.scope(state: \.currentTrip, action: \.trip) {
                UnifiedTripView(store: tripStore, mode: .mapFocused)
            } else {
                EmptyTripView()
            }
            
        case .timeline:
            if let tripStore = store.scope(state: \.currentTrip, action: \.trip) {
                UnifiedTripView(store: tripStore, mode: .timelineFocused)
            } else {
                EmptyTripView()
            }
            
        case .list:
            TripsListView(
                store: store.scope(state: \.tripsList, action: \.tripsList)
            )
            
        case .importDoc:
            ImportView(
                store: store.scope(state: \.importFlow, action: \.importFlow)
            )
        }
    }
}

// MARK: - Trip Feature (Main Planning Interface)

@Reducer
struct TripFeature {
    @Dependency(\.travelPlanningClient) var travelPlanningClient
    
    @ObservableState
    struct State: Equatable {
        var trip: TravelTrip
        var selectedActivity: TravelActivity?
        var quickInput: String = ""
        var isProcessingInput: Bool = false
        var mapRegion: MKCoordinateRegion
        var conflicts: [TravelConflict] = []
        var viewMode: ViewMode = .unified
        
        enum ViewMode {
            case unified, mapFocused, timelineFocused, listFocused
        }
        
        init(trip: TravelTrip) {
            self.trip = trip
            self.mapRegion = Self.calculateMapRegion(for: trip.activities)
        }
        
        static func calculateMapRegion(for activities: [TravelActivity]) -> MKCoordinateRegion {
            guard !activities.isEmpty else {
                return MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
            
            let coordinates = activities.map { $0.coordinate }
            let minLat = coordinates.map { $0.latitude }.min() ?? 0
            let maxLat = coordinates.map { $0.latitude }.max() ?? 0
            let minLon = coordinates.map { $0.longitude }.min() ?? 0
            let maxLon = coordinates.map { $0.longitude }.max() ?? 0
            
            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            
            let span = MKCoordinateSpan(
                latitudeDelta: max(maxLat - minLat, 0.01) * 1.3,
                longitudeDelta: max(maxLon - minLon, 0.01) * 1.3
            )
            
            return MKCoordinateRegion(center: center, span: span)
        }
    }
    
    enum Action {
        case activitySelected(TravelActivity?)
        case quickInputChanged(String)
        case addQuickActivity
        case quickActivityAdded(TravelActivity)
        case quickActivityFailed(String)
        case detectConflicts
        case conflictsDetected([TravelConflict])
        case optimizeRoute
        case routeOptimized([TravelActivity])
        case mapRegionChanged(MKCoordinateRegion)
        case viewModeChanged(State.ViewMode)
        case deleteActivity(TravelActivity)
        case updateActivity(TravelActivity)
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .activitySelected(activity):
                state.selectedActivity = activity
                return .none
                
            case let .quickInputChanged(input):
                state.quickInput = input
                return .none
                
            case .addQuickActivity:
                guard !state.quickInput.isEmpty else { return .none }
                state.isProcessingInput = true
                
                let input = state.quickInput
                state.quickInput = ""
                
                return .run { send in
                    do {
                        let activity = try await travelPlanningClient.parseInput(input)
                        await send(.quickActivityAdded(activity))
                    } catch {
                        await send(.quickActivityFailed(error.localizedDescription))
                    }
                }
                
            case let .quickActivityAdded(activity):
                state.isProcessingInput = false
                state.trip.activities.append(activity)
                state.mapRegion = State.calculateMapRegion(for: state.trip.activities)
                
                // Auto-detect conflicts after adding
                return .send(.detectConflicts)
                
            case let .quickActivityFailed(error):
                state.isProcessingInput = false
                // TODO: Show error alert
                return .none
                
            case .detectConflicts:
                return .run { [activities = state.trip.activities] send in
                    do {
                        let conflicts = try await travelPlanningClient.detectConflicts(activities)
                        await send(.conflictsDetected(conflicts))
                    } catch {
                        // Handle error
                    }
                }
                
            case let .conflictsDetected(conflicts):
                state.conflicts = conflicts
                return .none
                
            case .optimizeRoute:
                return .run { [activities = state.trip.activities] send in
                    do {
                        let optimizedActivities = try await travelPlanningClient.optimizeRoute(activities)
                        await send(.routeOptimized(optimizedActivities))
                    } catch {
                        // Handle error
                    }
                }
                
            case let .routeOptimized(activities):
                state.trip.activities = activities
                state.mapRegion = State.calculateMapRegion(for: activities)
                return .none
                
            case let .mapRegionChanged(region):
                state.mapRegion = region
                return .none
                
            case let .viewModeChanged(mode):
                state.viewMode = mode
                return .none
                
            case let .deleteActivity(activity):
                state.trip.activities.removeAll { $0.id == activity.id }
                if state.selectedActivity?.id == activity.id {
                    state.selectedActivity = nil
                }
                return .send(.detectConflicts)
                
            case let .updateActivity(activity):
                if let index = state.trip.activities.firstIndex(where: { $0.id == activity.id }) {
                    state.trip.activities[index] = activity
                }
                return .send(.detectConflicts)
            }
        }
    }
}

// MARK: - Unified Trip View

struct UnifiedTripView: View {
    @Bindable var store: StoreOf<TripFeature>
    let mode: TripFeature.State.ViewMode
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Quick Add Bar
                    QuickAddBarView(store: store)
                        .padding()
                        .background(Color(.systemBackground))
                    
                    Divider()
                    
                    // Main Content based on mode
                    switch mode {
                    case .unified:
                        unifiedContent(geometry: geometry)
                    case .mapFocused:
                        mapFocusedContent()
                    case .timelineFocused:
                        timelineFocusedContent()
                    case .listFocused:
                        listFocusedContent()
                    }
                }
            }
            .navigationTitle(store.trip.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Detect Conflicts") {
                            store.send(.detectConflicts)
                        }
                        Button("Optimize Route") {
                            store.send(.optimizeRoute)
                        }
                        Divider()
                        Button("Share Trip") {
                            // TODO: Implement sharing
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func unifiedContent(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Top Half: Map
            TripMapView(store: store)
                .frame(height: geometry.size.height * 0.5)
            
            Divider()
            
            // Bottom Half: Split Timeline + List
            HStack(spacing: 0) {
                TimelineView(store: store)
                    .frame(width: geometry.size.width * 0.6)
                
                Divider()
                
                ActivitiesListView(store: store)
                    .frame(width: geometry.size.width * 0.4)
            }
            .frame(height: geometry.size.height * 0.5)
        }
        
        // Conflicts Alert Overlay
        if !store.conflicts.isEmpty {
            conflictsOverlay(conflicts: store.conflicts)
        }
    }
    
    @ViewBuilder
    private func mapFocusedContent() -> some View {
        TripMapView(store: store)
            .overlay(alignment: .bottom) {
                if let selectedActivity = store.selectedActivity {
                    ActivityDetailCard(
                        activity: selectedActivity,
                        onDismiss: { store.send(.activitySelected(nil)) }
                    )
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
    }
    
    @ViewBuilder
    private func timelineFocusedContent() -> some View {
        TimelineView(store: store)
    }
    
    @ViewBuilder
    private func listFocusedContent() -> some View {
        ActivitiesListView(store: store)
    }
    
    @ViewBuilder
    private func conflictsOverlay(conflicts: [TravelConflict]) -> some View {
        VStack {
            Spacer()
            
            ConflictsAlertView(conflicts: conflicts) {
                // Dismiss conflicts - could clear the conflicts array
            }
            .padding()
        }
        .background(Color.black.opacity(0.3))
        .transition(.opacity)
    }
}

// MARK: - Quick Add Bar

struct QuickAddBarView: View {
    @Bindable var store: StoreOf<TripFeature>
    
    var body: some View {
        HStack {
            TextField("Add anything: 'dinner at 7pm' or 'Louvre Museum tomorrow'",
                     text: $store.quickInput.sending(\.quickInputChanged))
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    store.send(.addQuickActivity)
                }
            
            if store.isProcessingInput {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button(action: { store.send(.addQuickActivity) }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
                .disabled(store.quickInput.isEmpty)
            }
        }
    }
}

// MARK: - Trip Map View

struct TripMapView: View {
    @Bindable var store: StoreOf<TripFeature>
    
    var body: some View {
        Map(
            coordinateRegion: $store.mapRegion.sending(\.mapRegionChanged),
            annotationItems: store.trip.activities
        ) { activity in
            MapAnnotation(coordinate: activity.coordinate) {
                ActivityMapPin(
                    activity: activity,
                    isSelected: store.selectedActivity?.id == activity.id
                ) {
                    store.send(.activitySelected(activity))
                }
            }
        }
        .overlay(
            RouteOverlayView(activities: store.trip.activities)
        )
    }
}

// MARK: - Timeline View

struct TimelineView: View {
    let store: StoreOf<TripFeature>
    
    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let groupedActivities = Dictionary(grouping: store.trip.activities) { activity in
                        Calendar.current.startOfDay(for: activity.startTime)
                    }
                    
                    ForEach(groupedActivities.keys.sorted(), id: \.self) { date in
                        DaySection(
                            date: date,
                            activities: groupedActivities[date] ?? [],
                            selectedActivity: store.selectedActivity,
                            onActivityTap: { activity in
                                store.send(.activitySelected(activity))
                            }
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemGray6))
        }
    }
}

// MARK: - Activities List View

struct ActivitiesListView: View {
    let store: StoreOf<TripFeature>
    
    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.trip.activities) { activity in
                        ActivityListCard(
                            activity: activity,
                            isSelected: store.selectedActivity?.id == activity.id,
                            onTap: {
                                store.send(.activitySelected(activity))
                            },
                            onDelete: {
                                store.send(.deleteActivity(activity))
                            }
                        )
                    }
                }
                .padding()
            }
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Supporting Views

struct ActivityMapPin: View {
    let activity: TravelActivity
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(activity.category.color)
                    .frame(width: isSelected ? 28 : 20, height: isSelected ? 28 : 20)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: isSelected ? 3 : 2)
                    )
                
                Image(systemName: activity.category.iconName)
                    .foregroundColor(.white)
                    .font(.system(size: isSelected ? 12 : 9, weight: .bold))
            }
            .scaleEffect(isSelected ? 1.2 : 1.0)
            .animation(.spring(response: 0.3), value: isSelected)
        }
    }
}

struct DaySection: View {
    let date: Date
    let activities: [TravelActivity]
    let selectedActivity: TravelActivity?
    let onActivityTap: (TravelActivity) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(date.formatted(.dateTime.weekday(.wide).month().day()))
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.vertical, 8)
            
            ForEach(activities.sorted(by: { $0.startTime < $1.startTime })) { activity in
                TimelineActivityRow(
                    activity: activity,
                    isSelected: selectedActivity?.id == activity.id,
                    onTap: { onActivityTap(activity) }
                )
            }
        }
    }
}

struct TimelineActivityRow: View {
    let activity: TravelActivity
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack {
                    Text(activity.startTime.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Circle()
                        .fill(activity.category.color)
                        .frame(width: 8, height: 8)
                }
                .frame(width: 50)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(activity.locationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(activity.duration / 60))min")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(activity.category.color.opacity(0.2))
                        .foregroundColor(activity.category.color)
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActivityListCard: View {
    let activity: TravelActivity
    let isSelected: Bool
    let onTap: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: activity.category.iconName)
                        .foregroundColor(activity.category.color)
                        .frame(width: 20)
                    
                    Text(activity.name)
                        .font(.headline)
                        .fontWeight(.medium)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                HStack {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text(activity.startTime.formatted(.dateTime.hour().minute()))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                HStack {
                    Image(systemName: "location")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Text(activity.locationName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    Spacer()
                }
            }
            .padding(12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ActivityDetailCard: View {
    let activity: TravelActivity
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activity.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(activity.locationName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
            }
            
            HStack {
                Image(systemName: "clock")
                    .foregroundColor(.blue)
                
                Text("\(activity.startTime.formatted(.dateTime.hour().minute())) - \(activity.endTime.formatted(.dateTime.hour().minute()))")
                    .font(.subheadline)
                
                Spacer()
                
                Text("\(Int(activity.duration / 60))min")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
            }
            
            HStack {
                Image(systemName: activity.category.iconName)
                    .foregroundColor(activity.category.color)
                
                Text(activity.category.displayName)
                    .font(.subheadline)
                    .foregroundColor(activity.category.color)
            }
            
            HStack(spacing: 12) {
                Button("Directions") {
                    let coordinate = activity.coordinate
                    let placemark = MKPlacemark(coordinate: coordinate)
                    let mapItem = MKMapItem(placemark: placemark)
                    mapItem.name = activity.locationName
                    mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button("Share") {
                    // Share activity details
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 8)
    }
}

struct ConflictsAlertView: View {
    let conflicts: [TravelConflict]
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                
                Text("Schedule Conflicts Detected")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            ForEach(conflicts.prefix(3), id: \.description) { conflict in
                VStack(alignment: .leading, spacing: 4) {
                    Text(conflict.description)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let recommendation = conflict.recommendations.first {
                        Text(recommendation)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            
            if conflicts.count > 3 {
                Text("And \(conflicts.count - 3) more conflicts...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Button("Auto-Fix") {
                    // Auto-resolve conflicts
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                
                Button("Review All") {
                    // Show detailed conflicts view
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }
}

struct RouteOverlayView: View {
    let activities: [TravelActivity]
    
    var body: some View {
        // Custom route drawing implementation would go here
        EmptyView()
    }
}

// MARK: - Trips List Feature

@Reducer
struct TripsListFeature {
    @ObservableState
    struct State: Equatable {
        var trips: [TravelTrip] = []
        var isLoading: Bool = false
    }
    
    enum Action {
        case onAppear
        case tripsLoaded([TravelTrip])
        case deleteTripAtOffsets(IndexSet)
        case selectTrip(TravelTrip)
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                return .run { send in
                    // Load saved trips from UserDefaults or CloudKit
                    let trips = [TravelTrip.sampleParis] // Mock data
                    await send(.tripsLoaded(trips))
                }
                
            case let .tripsLoaded(trips):
                state.trips = trips
                state.isLoading = false
                return .none
                
            case let .deleteTripAtOffsets(offsets):
                state.trips.remove(atOffsets: offsets)
                return .none
                
            case .selectTrip:
                return .none
            }
        }
    }
}

// MARK: - Trips List View

struct TripsListView: View {
    let store: StoreOf<TripsListFeature>
    
    var body: some View {
        WithPerceptionTracking {
            NavigationView {
                List {
                    ForEach(store.trips) { trip in
                        TripRowView(trip: trip) {
                            store.send(.selectTrip(trip))
                        }
                    }
                    .onDelete { offsets in
                        store.send(.deleteTripAtOffsets(offsets))
                    }
                }
                .navigationTitle("Travel Plans")
                .onAppear {
                    store.send(.onAppear)
                }
            }
        }
    }
}

struct TripRowView: View {
    let trip: TravelTrip
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(trip.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("\(trip.activities.count) activities")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let firstActivity = trip.activities.first,
                   let lastActivity = trip.activities.last {
                    Text("\(firstActivity.startTime.formatted(.dateTime.month().day())) - \(lastActivity.endTime.formatted(.dateTime.month().day()))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Preview of activities
                HStack(spacing: 4) {
                    ForEach(trip.activities.prefix(3)) { activity in
                        Circle()
                            .fill(activity.category.color)
                            .frame(width: 8, height: 8)
                    }
                    
                    if trip.activities.count > 3 {
                        Text("+\(trip.activities.count - 3)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Import Feature

@Reducer
struct ImportFeature {
    @ObservableState
    struct State: Equatable {
        var importText: String = ""
        var isImporting: Bool = false
        var importResult: ImportResult?
        var showingFilePicker: Bool = false
        
        enum ImportResult: Equatable {
            case success(TravelTrip)
            case failure(String)
        }
    }
    
    enum Action {
        case importTextChanged(String)
        case importFromClipboard
        case importFromFile
        case filePickerPresented(Bool)
        case processImport(String)
        case importCompleted(State.ImportResult)
        case clearResult
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .importTextChanged(text):
                state.importText = text
                return .none
                
            case .importFromClipboard:
                if let clipboardString = UIPasteboard.general.string {
                    state.importText = clipboardString
                    return .send(.processImport(clipboardString))
                }
                return .none
                
            case .importFromFile:
                state.showingFilePicker = true
                return .none
                
            case let .filePickerPresented(isPresented):
                state.showingFilePicker = isPresented
                return .none
                
            case let .processImport(jsonString):
                state.isImporting = true
                return .run { send in
                    do {
                        let trip = try parseJSONTrip(jsonString)
                        await send(.importCompleted(.success(trip)))
                    } catch {
                        await send(.importCompleted(.failure(error.localizedDescription)))
                    }
                }
                
            case let .importCompleted(result):
                state.isImporting = false
                state.importResult = result
                return .none
                
            case .clearResult:
                state.importResult = nil
                return .none
            }
        }
    }
}

// MARK: - Import View

struct ImportView: View {
    @Bindable var store: StoreOf<ImportFeature>
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Import Trip from Claude Desktop")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                
                Text("Paste JSON from Claude Desktop or import from file")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                // Import buttons
                VStack(spacing: 12) {
                    Button("Paste from Clipboard") {
                        store.send(.importFromClipboard)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Import from File") {
                        store.send(.importFromFile)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                
                Divider()
                
                // Manual text input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or paste JSON manually:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    TextEditor(text: $store.importText.sending(\.importTextChanged))
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .frame(minHeight: 150)
                    
                    Button("Import Trip") {
                        store.send(.processImport(store.importText))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.importText.isEmpty || store.isImporting)
                    .frame(maxWidth: .infinity)
                }
                
                if store.isImporting {
                    ProgressView("Importing trip...")
                        .padding()
                }
                
                // Import result
                if let result = store.importResult {
                    importResultView(result: result)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
        }
        .fileImporter(
            isPresented: $store.showingFilePicker.sending(\.filePickerPresented),
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        let data = try Data(contentsOf: url)
                        let jsonString = String(data: data, encoding: .utf8) ?? ""
                        store.send(.processImport(jsonString))
                    } catch {
                        store.send(.importCompleted(.failure("Failed to read file: \(error.localizedDescription)")))
                    }
                }
            case .failure(let error):
                store.send(.importCompleted(.failure("Failed to import file: \(error.localizedDescription)")))
            }
        }
    }
    
    @ViewBuilder
    private func importResultView(result: ImportFeature.State.ImportResult) -> some View {
        VStack(spacing: 12) {
            switch result {
            case .success(let trip):
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.largeTitle)
                    
                    Text("Successfully imported!")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text("\"\(trip.name)\" with \(trip.activities.count) activities")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button("View Trip") {
                        // Navigate to trip view
                    }
                    .buttonStyle(.borderedProminent)
                }
                
            case .failure(let error):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.largeTitle)
                    
                    Text("Import Failed")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Button("Dismiss") {
                store.send(.clearResult)
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Empty Trip View

struct EmptyTripView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "map")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Trip Selected")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create a new trip or import one from Claude Desktop")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Load Sample Trip") {
                // Load sample for testing
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Data Models

struct TravelTrip: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var activities: [TravelActivity]
    let createdAt: Date = Date()
    
    static let sampleParis = TravelTrip(
        name: "Paris Weekend",
        activities: [
            TravelActivity(
                id: UUID().uuidString,
                name: "Louvre Museum",
                startTime: Calendar.current.date(byAdding: .hour, value: 10, to: Calendar.current.startOfDay(for: Date()))!,
                endTime: Calendar.current.date(byAdding: .hour, value: 13, to: Calendar.current.startOfDay(for: Date()))!,
                coordinate: CLLocationCoordinate2D(latitude: 48.8606, longitude: 2.3376),
                locationName: "Musée du Louvre",
                category: .museum,
                duration: 10800 // 3 hours
            ),
            TravelActivity(
                id: UUID().uuidString,
                name: "Lunch at Café de Flore",
                startTime: Calendar.current.date(byAdding: .hour, value: 14, to: Calendar.current.startOfDay(for: Date()))!,
                endTime: Calendar.current.date(byAdding: .hour, value: 15, to: Calendar.current.startOfDay(for: Date()))!,
                coordinate: CLLocationCoordinate2D(latitude: 48.8542, longitude: 2.3325),
                locationName: "Café de Flore",
                category: .restaurant,
                duration: 3600 // 1 hour
            ),
            TravelActivity(
                id: UUID().uuidString,
                name: "Eiffel Tower",
                startTime: Calendar.current.date(byAdding: .hour, value: 16, to: Calendar.current.startOfDay(for: Date()))!,
                endTime: Calendar.current.date(byAdding: .hour, value: 18, to: Calendar.current.startOfDay(for: Date()))!,
                coordinate: CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945),
                locationName: "Tour Eiffel",
                category: .landmark,
                duration: 7200 // 2 hours
            )
        ]
    )
}

struct TravelActivity: Identifiable, Equatable {
    let id: String
    let name: String
    let startTime: Date
    let endTime: Date
    let coordinate: CLLocationCoordinate2D
    let locationName: String
    let category: ActivityCategory
    let duration: TimeInterval
    
    static func == (lhs: TravelActivity, rhs: TravelActivity) -> Bool {
        lhs.id == rhs.id
    }
}

enum ActivityCategory: String, CaseIterable {
    case restaurant = "restaurant"
    case museum = "museum"
    case landmark = "landmark"
    case hotel = "hotel"
    case transportation = "transportation"
    case shopping = "shopping"
    case entertainment = "entertainment"
    case activity = "activity"
    
    var color: Color {
        switch self {
        case .restaurant: return .orange
        case .museum: return .purple
        case .landmark: return .blue
        case .hotel: return .green
        case .transportation: return .gray
        case .shopping: return .pink
        case .entertainment: return .red
        case .activity: return .cyan
        }
    }
    
    var iconName: String {
        switch self {
        case .restaurant: return "fork.knife"
        case .museum: return "building.columns"
        case .landmark: return "camera"
        case .hotel: return "bed.double"
        case .transportation: return "car"
        case .shopping: return "bag"
        case .entertainment: return "theatermasks"
        case .activity: return "figure.walk"
        }
    }
    
    var displayName: String {
        switch self {
        case .restaurant: return "Restaurant"
        case .museum: return "Museum"
        case .landmark: return "Landmark"
        case .hotel: return "Hotel"
        case .transportation: return "Transportation"
        case .shopping: return "Shopping"
        case .entertainment: return "Entertainment"
        case .activity: return "Activity"
        }
    }
}

struct TravelConflict: Equatable {
    let description: String
    let recommendations: [String]
    let severity: Severity
    
    enum Severity {
        case low, medium, high
    }
}

// MARK: - Dependencies

extension DependencyValues {
    var travelPlanningClient: TravelPlanningClient {
        get { self[TravelPlanningClientKey.self] }
        set { self[TravelPlanningClientKey.self] = newValue }
    }
}

private enum TravelPlanningClientKey: DependencyKey {
    static let liveValue = TravelPlanningClient.liveValue
    static let testValue = TravelPlanningClient.testValue
}

struct TravelPlanningClient {
    var parseInput: @Sendable (String) async throws -> TravelActivity
    var detectConflicts: @Sendable ([TravelActivity]) async throws -> [TravelConflict]
    var optimizeRoute: @Sendable ([TravelActivity]) async throws -> [TravelActivity]
}

extension TravelPlanningClient {
    static let liveValue = TravelPlanningClient(
        parseInput: { input in
            // In a real implementation, this would call your MCP service
            // For now, return a mock activity
            return TravelActivity(
                id: UUID().uuidString,
                name: "Parsed Activity",
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                coordinate: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522),
                locationName: "Paris",
                category: .activity,
                duration: 3600
            )
        },
        detectConflicts: { activities in
            // Mock conflict detection
            return []
        },
        optimizeRoute: { activities in
            // Mock route optimization - return activities as-is
            return activities
        }
    )
    
    static let testValue = TravelPlanningClient(
        parseInput: { _ in
            TravelActivity(
                id: "test",
                name: "Test Activity",
                startTime: Date(),
                endTime: Date().addingTimeInterval(3600),
                coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                locationName: "Test Location",
                category: .activity,
                duration: 3600
            )
        },
        detectConflicts: { _ in [] },
        optimizeRoute: { activities in activities }
    )
}

// MARK: - Helper Functions

func parseJSONTrip(_ jsonString: String) throws -> TravelTrip {
    guard let data = jsonString.data(using: .utf8) else {
        throw ImportError.invalidJSON
    }
    
    let decoder = JSONDecoder()
    let formatter = ISO8601DateFormatter()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let dateString = try container.decode(String.self)
        if let date = formatter.date(from: dateString) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date format")
    }
    
    let tripData = try decoder.decode(TripJSON.self, from: data)
    
    let activities = tripData.activities.map { activityData in
        TravelActivity(
            id: activityData.id ?? UUID().uuidString,
            name: activityData.name,
            startTime: activityData.startTime,
            endTime: activityData.endTime,
            coordinate: CLLocationCoordinate2D(
                latitude: activityData.location.latitude,
                longitude: activityData.location.longitude
            ),
            locationName: activityData.location.name,
            category: ActivityCategory(rawValue: activityData.category) ?? .activity,
            duration: activityData.endTime.timeIntervalSince(activityData.startTime)
        )
    }
    
    return TravelTrip(name: tripData.name, activities: activities)
}

// MARK: - JSON Decoding Models

struct TripJSON: Codable {
    let name: String
    let activities: [ActivityJSON]
}

struct ActivityJSON: Codable {
    let id: String?
    let name: String
    let startTime: Date
    let endTime: Date
    let location: LocationJSON
    let category: String
}

struct LocationJSON: Codable {
    let name: String
    let latitude: Double
    let longitude: Double
}

enum ImportError: Error, LocalizedError {
    case invalidJSON
    case missingRequiredFields
    case invalidDateFormat
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON format"
        case .missingRequiredFields:
            return "Missing required fields in JSON"
        case .invalidDateFormat:
            return "Invalid date format in JSON"
        }
    }
}
