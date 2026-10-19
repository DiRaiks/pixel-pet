import AppKit
import PetCore
import PetSprites
import SwiftUI

/// First-launch welcome: what the pet does and the two things it needs from the user.
struct OnboardingView: View {
    @Bindable var model: SettingsModel
    var onSettings: () -> Void = {}
    var onDone: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                if let cube = Self.cube {
                    Image(nsImage: cube).interpolation(.none).resizable().frame(width: 64, height: 64)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Привет, я кубик").font(.title2.weight(.semibold))
                    Text("Живу на рабочем столе, слежу за агентами Claude Code и помогаю по мелочи.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Step(number: 1, title: "Подключить к Claude Code", done: model.hooksConnected,
                 detail: "Тогда я вижу, когда агенты работают, ждут вас или закончили, и показываю лимиты.") {
                if !model.hooksConnected { Button("Подключить…") { model.toggleHooks() } }
            }
            Step(number: 2, title: "Доступ к выделенному тексту", done: model.accessibility,
                 detail: "Нужен только для перевода по ⌃⌥T. Без него всё остальное работает.") {
                if !model.accessibility { Button("Разрешить…") { model.requestAccessibility() } }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Горячие клавиши").font(.headline)
                Shortcut(keys: "⌃⌥K", title: "спросить Claude")
                Shortcut(keys: "⌃⌥T", title: "перевести выделенный текст")
                Shortcut(keys: "⌃⌥P", title: "не беспокоить: спрятаться в нору")
            }
            Text("Клик по мне открывает лимиты и сессии. Меня можно таскать мышью, а если бросить к верхнему краю экрана, уйду в нору.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Настройки…", action: onSettings)
                Spacer()
                Button("Готово", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static let cube: NSImage? = {
        guard let image = SpriteFactory.frame(for: .idle, index: 0, agentCubes: false).makeImage(),
              let cropped = image.cropping(to: CGRect(x: 6, y: 9, width: 20, height: 20)) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: 20, height: 20))
    }()
}

private struct Step<Action: View>: View {
    let number: Int
    let title: String
    let done: Bool
    let detail: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color(red: 0.11, green: 0.62, blue: 0.46) : Color.secondary.opacity(0.2))
                if done {
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.weight(.semibold))
                }
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            action()
        }
    }
}

private struct Shortcut: View {
    let keys: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(keys).font(.callout.monospaced()).padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            Text(title).font(.callout)
        }
    }
}
