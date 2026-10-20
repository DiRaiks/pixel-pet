import AppKit
import Observation
import PetCore
import SwiftUI

/// What the recap card shows: last week (the finished one) or this week so far.
@MainActor
@Observable
final class RecapModel {
    var lastWeek = true
    var stats = AgentStats()
    var now = Date()

    var week: AgentStats.Week {
        let current = AgentStats.Week.containing(now)
        return lastWeek ? current.previous : current
    }

    var summary: WeekSummary { stats.summary(of: week) }
}

struct RecapView: View {
    let model: RecapModel

    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.36, green: 0.48, blue: 0.84)

    var body: some View {
        let s = model.summary
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Weekly recap", "Итоги недели")).font(.headline)
                    Text(Self.range(model.week)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: Binding(get: { model.lastWeek }, set: { model.lastWeek = $0 })) {
                    Text(L("Last week", "Прошлая")).tag(true)
                    Text(L("This week", "Эта")).tag(false)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if s.total <= 0 && s.turns == 0 {
                Text(model.stats.isEmpty
                     ? L("Nothing counted yet: the recap starts from the day it was turned on",
                         "Пока ничего не посчитано: итоги копятся с того дня, как их включили")
                     : L("No agent work this week", "На этой неделе агенты не работали"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                totals(s)
                DayBars(summary: s)
                Divider()
                projects(s)
                Divider()
                facts(s)
            }
        }
        .padding(16)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }

    private func totals(_ s: WeekSummary) -> some View {
        HStack(alignment: .top, spacing: 20) {
            big(Format.duration(s.total), L("agents worked", "агенты работали"))
            big("\(s.turns)", L(s.turns == 1 ? "turn" : "turns", Format.ru(s.turns, "ход", "хода", "ходов")))
            big(s.steps.formatted(), L(s.steps == 1 ? "step" : "steps", Format.ru(s.steps, "шаг", "шага", "шагов")))
            Spacer(minLength: 0)
        }
    }

    private func big(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private func projects(_ s: WeekSummary) -> some View {
        let top = max(1, s.projects.first?.seconds ?? 1)
        let rows = s.projects.map { ($0.name, $0.seconds) }
            + (s.others.map { [(L("\($0.count) more", "ещё \($0.count)"), $0.seconds)] } ?? [])
        return VStack(spacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(row.0).font(.callout).lineLimit(1).frame(width: 100, alignment: .leading)
                    ProgressView(value: min(1, row.1 / top)).tint(.secondary)
                    Text(Format.duration(row.1)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
            }
        }
    }

    private func facts(_ s: WeekSummary) -> some View {
        VStack(spacing: 4) {
            if let longest = s.longest {
                fact(L("Longest turn", "Самый долгий ход"),
                     "\(Format.duration(longest.seconds)) · \(longest.project), \(Self.weekday(longest.weekday))")
            }
            if s.waits > 0 {
                fact(L("Waited for you", "Ждали вас"),
                     L("\(Format.duration(s.waited)) · \(s.waits) times",
                       "\(Format.duration(s.waited)) · \(s.waits) \(Format.ru(s.waits, "раз", "раза", "раз"))"))
            }
            if s.answeredInPet > 0 {
                fact(L("Answered in the cube", "Ответили в кубике"),
                     L(s.answeredInPet == 1 ? "1 permission" : "\(s.answeredInPet) permissions",
                       "\(s.answeredInPet) \(Format.ru(s.answeredInPet, "разрешение", "разрешения", "разрешений"))"))
            }
            if let peak = s.limitPeak {
                let hits = s.limitHits == 0 ? ""
                    : L(" · ran out \(s.limitHits)×", " · упёрлись \(s.limitHits) \(Format.ru(s.limitHits, "раз", "раза", "раз"))")
                fact(L("5-hour limit", "Лимит 5 ч"), L("up to \(Int(peak.rounded()))%", "до \(Int(peak.rounded()))%") + hits)
            }
            if let change = s.change, model.lastWeek {
                let percent = Int((change * 100).rounded())
                fact(L("Week over week", "Неделя к неделе"),
                     L("\(percent >= 0 ? "+" : "")\(percent)% agent time", "\(percent >= 0 ? "+" : "")\(percent)% времени агентов"))
            }
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    static func weekday(_ i: Int) -> String {
        let en = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], ru = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
        return L(en[i], ru[i])
    }

    static func range(_ week: AgentStats.Week) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Loc.shared.language == .ru ? "ru_RU" : "en_US")
        f.setLocalizedDateFormatFromTemplate("dMMMM")
        guard let first = week.days.first, let last = week.days.last else { return "" }
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }
}

/// Agent time per day, Monday first: Claude Code below, Codex stacked on top.
private struct DayBars: View {
    let summary: WeekSummary

    var body: some View {
        let peak = max(1, summary.perDay.map { $0.claude + $0.codex }.max() ?? 1)
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let day = summary.perDay[i]
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(RecapView.codex).frame(height: 70 * day.codex / peak)
                        Rectangle().fill(RecapView.claude).frame(height: 70 * day.claude / peak)
                    }
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2))
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 70)
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(RecapView.weekday(i)).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: 12) {
                legend(RecapView.claude, "Claude Code")
                if summary.perDay.contains(where: { $0.codex > 0 }) { legend(RecapView.codex, "Codex") }
                Spacer()
            }
            .padding(.top, 2)
        }
    }

    private func legend(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }
}

typealias RecapPanel = CardPanel<RecapView>

extension CardPanel where Content == RecapView {
    convenience init(model: RecapModel) {
        self.init(content: RecapView(model: model))
        onShow = { model.now = Date() }
    }
}
