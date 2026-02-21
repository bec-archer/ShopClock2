import SwiftUI
import MapKit

struct SettingsView: View {
    @EnvironmentObject var clockManager: ClockManager
    @EnvironmentObject var locationManager: LocationManager

    @AppStorage("workplaceLatitude") private var workplaceLatitude: Double = 0.0
    @AppStorage("workplaceLongitude") private var workplaceLongitude: Double = 0.0
    @AppStorage("geofenceRadius") private var geofenceRadius: Double = 100.0
    @AppStorage("gracePeriodMinutes") private var gracePeriodMinutes: Int = 15
    @AppStorage("recipientPhoneNumber") private var recipientPhoneNumber: String = ""
    @AppStorage("workplaceLocationSet") private var workplaceLocationSet: Bool = false

    @State private var showLocationPicker = false

    private var workplaceCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: workplaceLatitude, longitude: workplaceLongitude)
    }

    var body: some View {
        Form {
            // MARK: - Workplace Location
            Section {
                if workplaceLocationSet {
                    Map {
                        Marker("Workplace", coordinate: workplaceCoordinate)
                            .tint(.blue)

                        MapCircle(center: workplaceCoordinate, radius: geofenceRadius)
                            .foregroundStyle(.blue.opacity(0.15))
                            .stroke(.blue, lineWidth: 2)
                    }
                    .mapStyle(.standard)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .allowsHitTesting(false)
                }

                Button {
                    showLocationPicker = true
                } label: {
                    Label(
                        workplaceLocationSet ? "Change Workplace Location" : "Set Workplace Location",
                        systemImage: "mappin.and.ellipse"
                    )
                }

                Button {
                    useCurrentLocation()
                } label: {
                    Label("Use Current Location", systemImage: "location.fill")
                }
            } header: {
                Text("Workplace Location")
            } footer: {
                if workplaceLocationSet {
                    Text("Geofence is active around your workplace.")
                } else {
                    Text("Set the workplace location to enable automatic clock in/out.")
                }
            }

            // MARK: - Geofence Settings
            Section("Geofence") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Radius")
                        Spacer()
                        Text("\(Int(geofenceRadius))m")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $geofenceRadius, in: 50...300, step: 10) {
                        Text("Radius")
                    }
                    .onChange(of: geofenceRadius) {
                        restartMonitoringIfNeeded()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Grace Period")
                        Spacer()
                        Text("\(gracePeriodMinutes) min")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: Binding(
                        get: { Double(gracePeriodMinutes) },
                        set: { gracePeriodMinutes = Int($0) }
                    ), in: 5...60, step: 1) {
                        Text("Grace Period")
                    }
                }
            }

            // MARK: - Payroll Recipient
            Section {
                HStack {
                    Image(systemName: "person.circle")
                        .foregroundStyle(.blue)
                    TextField("Phone number", text: $recipientPhoneNumber)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
            } header: {
                Text("Payroll Recipient")
            } footer: {
                Text("Used for the weekly summary text message.")
            }

            // MARK: - Permissions Status
            Section("Status") {
                HStack {
                    Text("Location Permission")
                    Spacer()
                    permissionBadge(for: locationManager.authorizationStatus)
                }

                HStack {
                    Text("Geofence Active")
                    Spacer()
                    Image(systemName: locationManager.isMonitoring ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(locationManager.isMonitoring ? .green : .red)
                }

                if !locationManager.isMonitoring && workplaceLocationSet {
                    Button("Restart Geofence Monitoring") {
                        restartMonitoringIfNeeded()
                    }
                }
            }

            // MARK: - About
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showLocationPicker) {
            LocationPickerView(
                initialCoordinate: workplaceLocationSet ? workplaceCoordinate : nil,
                radius: geofenceRadius
            ) { coordinate in
                workplaceLatitude = coordinate.latitude
                workplaceLongitude = coordinate.longitude
                workplaceLocationSet = true
                restartMonitoringIfNeeded()
            }
        }
    }

    // MARK: - Helpers

    private func useCurrentLocation() {
        locationManager.requestCurrentLocation()
        // We'll observe the location update via the published property
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if let location = locationManager.currentLocation {
                workplaceLatitude = location.coordinate.latitude
                workplaceLongitude = location.coordinate.longitude
                workplaceLocationSet = true
                restartMonitoringIfNeeded()
            }
        }
    }

    private func restartMonitoringIfNeeded() {
        guard workplaceLocationSet else { return }
        locationManager.startMonitoring(
            latitude: workplaceLatitude,
            longitude: workplaceLongitude,
            radius: geofenceRadius
        )
    }

    @ViewBuilder
    private func permissionBadge(for status: CLAuthorizationStatus) -> some View {
        switch status {
        case .authorizedAlways:
            Label("Always", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .authorizedWhenInUse:
            Label("When In Use", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .denied, .restricted:
            Label("Denied", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(.red)
        case .notDetermined:
            Label("Not Set", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        @unknown default:
            Text("Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Location Picker Sheet

struct LocationPickerView: View {
    let initialCoordinate: CLLocationCoordinate2D?
    let radius: Double
    let onSelect: (CLLocationCoordinate2D) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var cameraPosition: MapCameraPosition
    @State private var pinLocation: CLLocationCoordinate2D

    init(initialCoordinate: CLLocationCoordinate2D?, radius: Double, onSelect: @escaping (CLLocationCoordinate2D) -> Void) {
        self.initialCoordinate = initialCoordinate
        self.radius = radius
        self.onSelect = onSelect

        let center = initialCoordinate ?? CLLocationCoordinate2D(latitude: 37.33, longitude: -122.0)
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
        _pinLocation = State(initialValue: center)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        Annotation("Workplace", coordinate: pinLocation) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title)
                                .foregroundStyle(.red)
                        }

                        MapCircle(center: pinLocation, radius: radius)
                            .foregroundStyle(.blue.opacity(0.15))
                            .stroke(.blue, lineWidth: 2)
                    }
                    .mapStyle(.standard)
                    .ignoresSafeArea(edges: .bottom)
                    .onMapCameraChange(frequency: .continuous) { context in
                        pinLocation = context.region.center
                    }
                }

                // Crosshair overlay — pin drops at center
                VStack {
                    Spacer()
                    Text("Move the map to position the pin")
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                    Spacer()
                    Spacer()
                }
            }
            .navigationTitle("Set Workplace Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        onSelect(pinLocation)
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
