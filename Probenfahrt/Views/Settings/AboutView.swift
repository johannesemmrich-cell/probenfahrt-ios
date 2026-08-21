import SwiftUI

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "cross.vial.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading) {
                        Text("Probenfahrt")
                            .font(.title3.bold())
                        Text("Fahrtenplanung fürs Laborteam")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            Section("Technologie") {
                Label("Gebaut mit SwiftUI & SwiftData", systemImage: "swift")
                Label("Lokale Datenhaltung, aktuell kein Server-Backend", systemImage: "internaldrive")
            }
        }
        .navigationTitle("Über")
        .listStyle(.insetGrouped)
    }
}

struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                Label("Kein Konto, kein Tracking", systemImage: "person.slash")
                Label("Alle Daten bleiben lokal auf dem Gerät", systemImage: "iphone")
                Label("Kein Zugriff auf Kontakte, Standort oder Kamera", systemImage: "hand.raised")
                Label("Name & Kürzel sind nur innerhalb deiner Team-Gruppe sichtbar", systemImage: "person.2")
            } header: {
                Text("Deine Privatsphäre")
            } footer: {
                Text("Probenfahrt ist aktuell ein reiner Mock-Daten-Prototyp ohne Mehrbenutzer-Synchronisierung — es verlassen keine Daten dieses Gerät.")
            }
        }
        .navigationTitle("Datenschutz")
        .listStyle(.insetGrouped)
    }
}
