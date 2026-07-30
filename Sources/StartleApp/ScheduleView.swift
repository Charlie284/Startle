import StartleCore
import SwiftUI

struct ScheduleView: View {
  @Environment(AppState.self) private var state
  private let intervals: [(String, TimeInterval)] = [
    ("5 min", 300), ("15 min", 900), ("30 min", 1800), ("1 hr", 3600), ("2 hr", 7200),
    ("4 hr", 14400),
  ]

  var body: some View {
    @Bindable var store = state.settings
    Page(
      title: "Schedule",
      subtitle: "Choose when Startle may surprise you. Every change replaces the pending timer."
    ) {
      GroupBox("Timing mode") {
        VStack(alignment: .leading, spacing: 14) {
          Picker("Mode", selection: $store.values.schedule.mode) {
            ForEach(ScheduleMode.allCases, id: \.self) { Text($0.title).tag($0) }
          }.pickerStyle(.segmented)
          switch store.values.schedule.mode {
          case .randomInterval:
            IntervalPicker(
              title: "Minimum interval", selection: $store.values.schedule.minimumInterval,
              choices: intervals)
            IntervalPicker(
              title: "Maximum interval", selection: $store.values.schedule.maximumInterval,
              choices: intervals)
            if store.values.schedule.minimumInterval > store.values.schedule.maximumInterval {
              Label(
                "Startle will automatically use the two values in ascending order.",
                systemImage: "arrow.up.arrow.down"
              ).font(.caption).foregroundStyle(.secondary)
            }
          case .fixedInterval:
            IntervalPicker(
              title: "Fixed interval", selection: $store.values.schedule.fixedInterval,
              choices: intervals)
          case .randomChance:
            IntervalPicker(
              title: "Check every", selection: $store.values.schedule.chanceCheckInterval,
              choices: Array(intervals.prefix(4)))
            HStack {
              Text("Chance at each check")
              Slider(value: $store.values.schedule.chancePercent, in: 1...100, step: 1)
              Text("\(Int(store.values.schedule.chancePercent))%").monospacedDigit().frame(
                width: 42)
            }
          }
        }.padding(8)
      }
      GroupBox("Active window") {
        VStack(alignment: .leading, spacing: 14) {
          HStack(spacing: 8) {
            ForEach(Array(Calendar.current.shortWeekdaySymbols.enumerated()), id: \.offset) {
              index, symbol in
              let day = index + 1
              Toggle(
                symbol,
                isOn: Binding(
                  get: { store.values.schedule.activeDays.contains(day) },
                  set: { enabled in
                    if enabled {
                      store.values.schedule.activeDays.insert(day)
                    } else {
                      store.values.schedule.activeDays.remove(day)
                    }
                  })
              )
              .toggleStyle(.button)
              .disabled(
                store.values.schedule.activeDays.count == 1
                  && store.values.schedule.activeDays.contains(day))
            }
          }
          HStack {
            DatePicker(
              "From", selection: minutesBinding($store.values.schedule.activeStartMinutes),
              displayedComponents: .hourAndMinute)
            DatePicker(
              "Until", selection: minutesBinding($store.values.schedule.activeEndMinutes),
              displayedComponents: .hourAndMinute)
          }
        }.padding(8)
      }
      GroupBox("Limits") {
        VStack(alignment: .leading, spacing: 14) {
          IntervalPicker(
            title: "Cooldown after a scare", selection: $store.values.schedule.cooldown,
            choices: [("None", 0)] + intervals)
          Stepper(
            "Maximum scares per day: \(store.values.schedule.maximumScaresPerDay)",
            value: $store.values.schedule.maximumScaresPerDay, in: 1...50)
          Toggle(
            "Wait after I return from keyboard or mouse inactivity",
            isOn: $store.values.schedule.avoidAfterIdle)
          if store.values.schedule.avoidAfterIdle {
            IntervalPicker(
              title: "Return grace period", selection: $store.values.schedule.idleGracePeriod,
              choices: [("1 min", 60), ("5 min", 300), ("10 min", 600), ("15 min", 900)])
          }
        }.padding(8)
      }
    }
  }

  private func minutesBinding(_ value: Binding<Int>) -> Binding<Date> {
    Binding(
      get: {
        Calendar.current.date(
          bySettingHour: value.wrappedValue / 60, minute: value.wrappedValue % 60, second: 0,
          of: Date()) ?? Date()
      },
      set: { date in
        value.wrappedValue =
          Calendar.current.component(.hour, from: date) * 60
          + Calendar.current.component(.minute, from: date)
      })
  }
}

private struct IntervalPicker: View {
  let title: String
  @Binding var selection: TimeInterval
  let choices: [(String, TimeInterval)]
  var body: some View {
    Picker(title, selection: $selection) { ForEach(choices, id: \.1) { Text($0.0).tag($0.1) } }
      .frame(maxWidth: 360)
  }
}
