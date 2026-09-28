import SwiftUI
import SwiftData

struct ListeningStatsView: View {
    @Query(sort: \ListeningRecord.timestamp, order: .reverse)
    private var allRecords: [ListeningRecord]

    @EnvironmentObject var styleManager: StyleManager
    @EnvironmentObject var collectionVM: CollectionViewModel

    @State private var selectedPeriod: StatsPeriod = .allTime

    private var filteredRecords: [ListeningRecord] {
        guard selectedPeriod != .allTime else { return allRecords }
        let cutoff = selectedPeriod.cutoffDate
        return allRecords.filter { $0.timestamp >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                styleManager.theme.backgroundColor
                    .ignoresSafeArea()

                if allRecords.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            periodPicker
                            overviewCards
                            topAlbumsSection
                            topTracksSection
                            recentPlaysSection
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle(L("stats.title"))
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 48))
                .foregroundColor(styleManager.theme.textSecondary.opacity(0.3))

            Text(L("stats.no_history"))
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(styleManager.theme.textSecondary)

            Text(L("stats.no_history_hint"))
                .font(.system(size: 13))
                .foregroundColor(styleManager.theme.textSecondary.opacity(0.6))
        }
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        HStack(spacing: 8) {
            ForEach(StatsPeriod.allCases) { period in
                let isSelected = selectedPeriod == period
                Text(period.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? styleManager.theme.accentColor : styleManager.theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(
                            isSelected
                                ? styleManager.theme.accentColor.opacity(0.12)
                                : styleManager.theme.surfaceColor
                        )
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPeriod = period
                        }
                    }
            }
        }
    }

    // MARK: - Overview Cards

    private var overviewCards: some View {
        let records = filteredRecords
        let totalTime = records.reduce(0) { $0 + $1.listenDuration }
        let uniqueAlbums = Set(records.map(\.albumId)).count
        let totalPlays = records.count

        return HStack(spacing: 12) {
            statCard(icon: "clock", label: L("stats.listened"), value: totalTime.formattedListeningTime)
            statCard(icon: "play.circle", label: L("stats.plays"), value: "\(totalPlays)")
            statCard(icon: "vinyl_record", label: L("stats.albums"), value: "\(uniqueAlbums)", isAssetImage: true)
        }
    }

    private func statCard(icon: String, label: String, value: String, isAssetImage: Bool = false) -> some View {
        VStack(spacing: 8) {
            if isAssetImage {
                VinylRecordIcon(size: 18)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(styleManager.theme.accentColor)
            }

            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(styleManager.theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 11))
                .foregroundColor(styleManager.theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(styleManager.theme.surfaceColor)
        )
    }

    // MARK: - Top Albums

    private var topAlbumsSection: some View {
        let records = filteredRecords
        let grouped = Dictionary(grouping: records, by: \.albumId)
        let sorted = grouped.sorted { $0.value.count > $1.value.count }
        let top5 = sorted.prefix(5)

        return VStack(alignment: .leading, spacing: 8) {
            Text(L("stats.top_albums"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(styleManager.theme.textPrimary)

            if top5.isEmpty {
                Text(L("stats.no_data"))
                    .font(.system(size: 13))
                    .foregroundColor(styleManager.theme.textSecondary)
            } else {
                ForEach(Array(top5.enumerated()), id: \.element.key) { index, entry in
                    let sample = entry.value.first!
                    let totalDuration = entry.value.reduce(0) { $0 + $1.listenDuration }

                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(styleManager.theme.accentColor)
                            .frame(width: 24)

                        CachedAsyncImage(url: sample.artworkURL.flatMap { URL(string: $0) }) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(styleManager.theme.surfaceColor)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .foregroundColor(styleManager.theme.textSecondary.opacity(0.3))
                                )
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.albumTitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(styleManager.theme.textPrimary)
                                .lineLimit(1)
                            Text(sample.artist)
                                .font(.system(size: 11))
                                .foregroundColor(styleManager.theme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(L("stats.plays_count", entry.value.count))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(styleManager.theme.textPrimary)
                            Text(totalDuration.formattedListeningTime)
                                .font(.system(size: 10))
                                .foregroundColor(styleManager.theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(styleManager.theme.surfaceColor)
        )
    }

    // MARK: - Top Tracks

    private var topTracksSection: some View {
        let records = filteredRecords.filter { $0.trackId != nil }
        let grouped = Dictionary(grouping: records) { $0.trackId! }
        let sorted = grouped.sorted { $0.value.count > $1.value.count }
        let top5 = sorted.prefix(5)

        return VStack(alignment: .leading, spacing: 8) {
            Text(L("stats.top_tracks"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(styleManager.theme.textPrimary)

            if top5.isEmpty {
                Text(L("stats.no_data"))
                    .font(.system(size: 13))
                    .foregroundColor(styleManager.theme.textSecondary)
            } else {
                ForEach(Array(top5.enumerated()), id: \.element.key) { index, entry in
                    let sample = entry.value.first!

                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(styleManager.theme.secondaryAccent)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(sample.trackTitle ?? L("vinyl.unknown"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(styleManager.theme.textPrimary)
                                .lineLimit(1)
                            Text("\(sample.artist) — \(sample.albumTitle)")
                                .font(.system(size: 11))
                                .foregroundColor(styleManager.theme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(L("stats.plays_count", entry.value.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(styleManager.theme.textPrimary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(styleManager.theme.surfaceColor)
        )
    }

    // MARK: - Recent Plays

    private var recentPlaysSection: some View {
        let recent = Array(filteredRecords.prefix(10))

        return VStack(alignment: .leading, spacing: 8) {
            Text(L("stats.recent"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(styleManager.theme.textPrimary)

            if recent.isEmpty {
                Text(L("stats.no_recent"))
                    .font(.system(size: 13))
                    .foregroundColor(styleManager.theme.textSecondary)
            } else {
                ForEach(recent) { record in
                    HStack(spacing: 12) {
                        CachedAsyncImage(url: record.artworkURL.flatMap { URL(string: $0) }) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(styleManager.theme.surfaceColor)
                                .overlay(
                                    Image(systemName: "music.note")
                                        .font(.system(size: 10))
                                        .foregroundColor(styleManager.theme.textSecondary.opacity(0.3))
                                )
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.trackTitle ?? record.albumTitle)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(styleManager.theme.textPrimary)
                                .lineLimit(1)
                            Text(record.artist)
                                .font(.system(size: 11))
                                .foregroundColor(styleManager.theme.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(record.timestamp.relativeFormatted)
                            .font(.system(size: 10))
                            .foregroundColor(styleManager.theme.textSecondary.opacity(0.7))
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(styleManager.theme.surfaceColor)
        )
    }
}

// MARK: - Stats Period

enum StatsPeriod: String, CaseIterable, Identifiable {
    case week = "week"
    case month = "month"
    case year = "year"
    case allTime = "all"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .week: return L("stats.period_week")
        case .month: return L("stats.period_month")
        case .year: return L("stats.period_year")
        case .allTime: return L("stats.period_all")
        }
    }

    var cutoffDate: Date {
        let cal = Calendar.current
        switch self {
        case .week: return cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        case .month: return cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        case .year: return cal.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        case .allTime: return .distantPast
        }
    }
}

// MARK: - Helpers

extension TimeInterval {
    var formattedListeningTime: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
}

extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
