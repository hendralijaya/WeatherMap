//
//  ContentView.swift
//  WeatherMap
//
//  Created by hendra on 09/07/24.
//

import SwiftUI
import WeatherKit
import CoreLocation
import MapKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var location: CLLocation?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            self.location = location
            manager.stopUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to find user's location: \(error.localizedDescription)")
    }
}

struct ContentView: View {
    @State private var cameraPosition: MapCameraPosition = .region(.userRegion)
    @State private var searchText = ""
    @State private var results = [MKMapItem]()
    @State private var mapSelection: MKMapItem?
    @State private var showDetails = false
    @State private var getDirections = false
    @State private var routeDisplaying = false
    @State private var route: MKRoute?
    @State private var routeDestination: MKMapItem?
    
    var body: some View {
        Map(position: $cameraPosition, selection: $mapSelection) {
//            Marker("My Location", systemImage: "paperplane", coordinate: .userLocation)
//                .tint(.blue)
//            UserAnnotation()
            Annotation("My Location", coordinate: .userLocation) {
                ZStack {
                    Circle()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.blue.opacity(0.25))
                    Circle()
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.white)
                    Circle()
                        .frame(width: 12, height: 12)
                        .foregroundStyle(.blue)
                }
            }
            ForEach(results, id: \.self) { item in
                if routeDisplaying {
                    if item == routeDestination {
                        let placemark = item.placemark
                        Marker(placemark.name ?? "", coordinate: placemark.coordinate)
                    }
                } else {
                    let placemark = item.placemark
                    Marker(placemark.name ?? "", coordinate: placemark.coordinate)
                }
            }
            
            if let route {
                MapPolyline(route.polyline)
                    .stroke(.blue, lineWidth: 6)
            }
        }
        .overlay(alignment: .top) {
            TextField("Search for a location...", text: $searchText)
                .font(.subheadline)
                .padding(12)
                .background(.white)
                .padding()
                .shadow(radius: 10)
        }
        .onAppear {
            fetchPrecipitationData()
        }
        .onSubmit(of: /*@START_MENU_TOKEN@*/.text/*@END_MENU_TOKEN@*/) {
            Task { await searchPlaces() }
        }
        .onChange(of: getDirections, { oldValue, newValue in
            if newValue {
                fetchRoute()
            }
        })
        .onChange(of: mapSelection, { oldValue, newValue in
            showDetails = newValue != nil
        })
        .sheet(isPresented: $showDetails) {
            LocationDetailsView(mapSelection: $mapSelection, show: $showDetails, getDirections: $getDirections)
                .presentationDetents([.height(340)])
                .presentationBackgroundInteraction(.enabled(upThrough: .height(340)))
                .presentationCornerRadius(12)
        }
        .mapControls {
            MapCompass()
            MapPitchToggle()
            MapUserLocationButton()
        }
    }
}

extension ContentView {
    func searchPlaces() async {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = .userRegion
        
        let results = try? await MKLocalSearch(request: request).start()
        self.results = results?.mapItems ?? []
    }
    
    struct LocationPrecipitationData {
        let coordinate: CLLocationCoordinate2D
        let hourlyData: [Date: Double]
    }
    
    func getHourlyPrecipitation(for locations: [CLLocation]) async throws -> [LocationPrecipitationData] {
        let weatherService = WeatherService()
        var locationData: [LocationPrecipitationData] = []
        
        for location in locations {
            let weather = try await weatherService.weather(for: location)
            let hourlyForecasts = weather.hourlyForecast
            
            var hourlyPrecipitation: [Date: Double] = [:]
            
            for forecast in hourlyForecasts.prefix(12) { // Limit to 12 hours
                let date = forecast.date
                print("date \(date)")
                let precipitation = forecast.precipitationChance
                hourlyPrecipitation[date] = precipitation
            }
            
            let data = LocationPrecipitationData(coordinate: location.coordinate, hourlyData: hourlyPrecipitation)
            locationData.append(data)
        }
        
        return locationData
    }
    
    func fetchPrecipitationData() {
        let centerLocation = CLLocation(latitude: -6, longitude: 106) // San Francisco, CA
        let radius: Double = 100000 // 100 km
        let numberOfPoints: Int = 10 // Number of points to query within the radius
        
        let locations = generateLocations(within: radius, center: centerLocation, numberOfPoints: numberOfPoints)
        
        Task {
            do {
                let precipitationData = try await getHourlyPrecipitation(for: locations)
                print(precipitationData)
            } catch {
                print("Failed to fetch weather data: \(error)")
            }
        }
    }
    
    func fetchRoute() {
        if let mapSelection {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: .init(coordinate: .userLocation))
            request.destination = mapSelection
            
            Task {
                let result = try? await MKDirections(request: request).calculate()
                route = result?.routes.first
                routeDestination = mapSelection
                
                withAnimation(.snappy) {
                    routeDisplaying = true
                    showDetails = false
                    
                    if let rect = route?.polyline.boundingMapRect, routeDisplaying {
                        cameraPosition = .rect(rect)
                    }
                }
            }
        }
    }
    
    func generateLocations(within radius: Double, center: CLLocation, numberOfPoints: Int) -> [CLLocation] {
        var locations: [CLLocation] = []
        let earthRadius = 6371000.0 // Earth radius in meters
        
        for _ in 0..<numberOfPoints {
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = Double.random(in: 0...radius)
            
            let dx = distance * cos(angle)
            let dy = distance * sin(angle)
            
            let deltaLat = dy / earthRadius
            let deltaLon = dx / (earthRadius * cos(center.coordinate.latitude * .pi / 180))
            
            let newLat = center.coordinate.latitude + (deltaLat * 180 / .pi)
            let newLon = center.coordinate.longitude + (deltaLon * 180 / .pi)
            
            let newLocation = CLLocation(latitude: newLat, longitude: newLon)
            locations.append(newLocation)
        }
        
        return locations
    }
}

extension CLLocationCoordinate2D {
    static var userLocation: CLLocationCoordinate2D {
        return .init(latitude: 25.7602, longitude: -80.1959)
    }
}

extension MKCoordinateRegion {
    static var userRegion: MKCoordinateRegion {
        return .init(center: .userLocation, latitudinalMeters: 10000, longitudinalMeters: 10000)
    }
}

#Preview {
    ContentView()
}
