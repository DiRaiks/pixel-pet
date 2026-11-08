import AppKit
import Observation
import PetCore
import PetSprites
import SwiftUI

/// What the update card shows, from a check through the restart.
@MainActor
@Observable
final class UpdateModel {
    enum Phase: Equatable {
        case checking
        case available
        case downloading(received: UInt64, expected: UInt64)
        /// Unpacking and installing, 0...1 when known.
        case preparing(Double?)
        case ready
        case upToDate
        case failed(String)
        /// The new version, after the restart.
        case updated
    }

    var phase = Phase.checking {
        didSet { if phase != oldValue { onPhaseChange?() } }
    }
    /// The card changes height between phases: re-fit it.
    @ObservationIgnored var onPhaseChange: (() -> Void)?
    var current = ""
    var version = ""
    var size: UInt64 = 0
    var look = Look.standard
    /// Sparkle's "download and install automatically", shown as a checkbox on the offer.
    var installsAutomatically = false
    @ObservationIgnored var onInstallAutomatically: ((Bool) -> Void)?

    /// The card's buttons; each phase uses its own.
    @ObservationIgnored var onUpdate: (() -> Void)?
    @ObservationIgnored var onLater: (() -> Void)?
    @ObservationIgnored var onSkip: (() -> Void)?
    @ObservationIgnored var onCancel: (() -> Void)?
    @ObservationIgnored var onRestart: (() -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
}

typealias UpdatePanel = CardPanel<UpdateView>

/// The update card: a lavender band with the pet and its box, the version, and below it a link to what's new on
/// GitHub and the choices, a pixel progress bar while it downloads.
struct UpdateView: View {
    let model: UpdateModel

    static let lavender = Color(red: 0x8A / 255, green: 0x80 / 255, blue: 0xE6 / 255)
    static let bandLight = Color(red: 0x8C / 255, green: 0x86 / 255, blue: 0xC4 / 255)
    static let bandDeep = Color(red: 0x5E / 255, green: 0x59 / 255, blue: 0x94 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(16)
        }
        .frame(width: 384)
        .tint(Self.lavender)
        // The card never takes focus, and AppKit would draw its buttons as in a background window.
        .environment(\.controlActiveState, .key)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private var banner: some View {
        HStack(spacing: 12) {
            sprite.frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let versions {
                    Text(versions).font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            Spacer(minLength: 8)
            if closable {
                Button { model.onClose?() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless).foregroundStyle(.white.opacity(0.85))
                    .accessibilityLabel(L("Close", "Закрыть"))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(LinearGradient(colors: [Self.bandLight, Self.bandDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
    }

    /// The pet as it looks right now: with the box, or out of it with a check mark once updated.
    private var sprite: some View {
        let state: PetState = model.phase == .updated ? .updateDone : (isWorking ? .updateUnpack : .updateWait)
        let index = model.phase == .updated ? state.frameCount - 1 : 6
        let frame = SpriteFactory.frame(for: state, index: index, agentCubes: false, look: model.look)
        return Group {
            if let image = frame.makeImage() {
                Image(decorative: image, scale: 1).interpolation(.none).resizable()
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Asking GitHub for the latest version…", "Спрашиваем у GitHub последнюю версию…"))
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(L("Cancel", "Отменить")) { model.onCancel?() }.fixedSize()
            }
        case .available:
            caption(sizeLine)
            whatsNew
            Toggle(isOn: Binding(get: { model.installsAutomatically }, set: { model.onInstallAutomatically?($0) })) {
                Text(L("Update automatically from now on", "Дальше обновлять автоматически")).font(.callout)
            }
            .toggleStyle(.checkbox)
            HStack(spacing: 8) {
                Button(L("Skip this version", "Пропустить версию")) { model.onSkip?() }
                    .buttonStyle(.link).font(.callout).fixedSize()
                Spacer(minLength: 8)
                Button(L("Later", "Позже")) { model.onLater?() }.fixedSize()
                Button(L("Update", "Обновить")) { model.onUpdate?() }.buttonStyle(.borderedProminent).fixedSize()
            }
        case .downloading(let received, let expected):
            PixelBar(value: expected > 0 ? Double(received) / Double(expected) : nil)
            HStack {
                Text(expected > 0
                     ? L("\(Self.megabytes(received)) of \(Self.megabytes(expected))",
                         "\(Self.megabytes(received)) из \(Self.megabytes(expected))")
                     : L("Downloading…", "Загружается…"))
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
                Button(L("Cancel", "Отменить")) { model.onCancel?() }.fixedSize()
            }
        case .preparing(let progress):
            PixelBar(value: progress)
            caption(L("Checking the signature and unpacking…", "Проверяем подпись и распаковываем…"))
        case .ready:
            Text(L("Pixel Pet quits and opens again right away. Settings and the weekly recap stay.",
                   "Pixel Pet закроется и сразу откроется снова. Настройки и итоги недели сохранятся."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button(L("On quit", "При выходе")) { model.onLater?() }.fixedSize()
                Button(L("Restart", "Перезапустить")) { model.onRestart?() }.buttonStyle(.borderedProminent).fixedSize()
            }
        case .upToDate:
            HStack {
                caption(L("You have the latest version.", "У вас последняя версия."))
                Spacer()
                Button(L("OK", "Хорошо")) { model.onClose?() }.buttonStyle(.borderedProminent).fixedSize()
            }
        case .failed(let message):
            Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("OK", "Хорошо")) { model.onClose?() }.buttonStyle(.borderedProminent).fixedSize()
            }
        case .updated:
            whatsNew
            HStack {
                Spacer()
                Button(L("Done", "Готово")) { model.onClose?() }.buttonStyle(.borderedProminent).fixedSize()
            }
        }
    }

    /// What changed lives on the release page GitHub makes for each version.
    @ViewBuilder private var whatsNew: some View {
        if let page = AppVersion.releasePage(model.version) {
            Link(destination: page) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Self.lavender)
                Text(L("What's new in \(model.version), on GitHub", "Что нового в \(model.version) — на GitHub")).font(.callout)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private var isWorking: Bool {
        switch model.phase {
        case .downloading, .preparing, .ready: true
        default: false
        }
    }

    /// Mid-download and mid-install it has to be cancelled, not closed.
    private var closable: Bool {
        switch model.phase {
        case .downloading, .preparing, .checking: false
        default: true
        }
    }

    private var title: String {
        switch model.phase {
        case .checking: L("Checking for updates", "Проверка обновлений")
        case .available: L("Pixel Pet \(model.version) is out", "Вышел Pixel Pet \(model.version)")
        case .downloading: L("Downloading the update", "Загружается обновление")
        case .preparing: L("Getting the update ready", "Готовим обновление")
        case .ready: L("Ready to install", "Обновление готово")
        case .upToDate: L("Up to date", "Обновлений нет")
        case .failed: L("Couldn't update", "Не удалось обновить")
        case .updated: L("Updated to \(model.version)", "Обновлено до \(model.version)")
        }
    }

    private var versions: String? {
        switch model.phase {
        case .checking, .upToDate, .failed: model.current.isEmpty ? nil : "v\(model.current)"
        case .updated: "v\(model.version)"
        default: model.current.isEmpty ? "v\(model.version)" : "v\(model.current) → v\(model.version)"
        }
    }

    private var sizeLine: String {
        let signed = L("signed and notarized", "подписано и проверено Apple")
        return model.size > 0 ? "\(Self.megabytes(model.size)) · \(signed)" : signed
    }

    static func megabytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// A progress bar of square blocks, like the pet's pixels; nil lights a block that walks along.
struct PixelBar: View {
    let value: Double?
    static let blocks = 26

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.12)) { context in
            let walk = Int(context.date.timeIntervalSinceReferenceDate / 0.12) % Self.blocks
            HStack(spacing: 2) {
                ForEach(0..<Self.blocks, id: \.self) { k in
                    Rectangle().fill(lit(k, walk: walk) ? UpdateView.lavender : Color.primary.opacity(0.1))
                        .frame(width: 11, height: 11)
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(L("Progress", "Прогресс"))
        .accessibilityValue(value.map { "\(Int($0 * 100))%" } ?? "")
    }

    private func lit(_ k: Int, walk: Int) -> Bool {
        guard let value else { return abs(k - walk) < 2 }
        return k < Int((Double(Self.blocks) * min(1, max(0, value))).rounded())
    }
}
