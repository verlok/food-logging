import SwiftUI

/// First-launch setup: body data, goal and starting weight.
struct OnboardingView: View {
    @Environment(AppStore.self) private var store
    @State private var step = 0
    @State private var startWeight: Double?

    var body: some View {
        @Bindable var profile = store.profile
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $step) {
                    welcome.tag(0)
                    profileForm($profile).tag(1)
                    goalForm($profile).tag(2)
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .always))
                #endif
                Button {
                    if step < 2 {
                        withAnimation { step += 1 }
                    } else {
                        store.completeOnboarding(startWeightKg: startWeight)
                    }
                } label: {
                    Text(step < 2 ? "Continue" : "Start tracking")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
            .navigationTitle("Welcome")
        }
    }

    private var welcome: some View {
        VStack(spacing: 20) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            Text("onboarding.welcome.title")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text("onboarding.welcome.body")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }

    private func profileForm(_ profile: Bindable<UserProfile>) -> some View {
        Form {
            Section("About you") {
                Picker("Sex", selection: profile.sex) {
                    ForEach(BiologicalSex.allCases) { Text($0.localizedName).tag($0) }
                }
                .pickerStyle(.segmented)
                DatePicker("Birth date", selection: profile.birthDate, in: ...Date(), displayedComponents: .date)
                HStack {
                    Text("Height")
                    Spacer()
                    TextField("cm", value: profile.heightCm, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                    Text(verbatim: "cm").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Current weight")
                    Spacer()
                    TextField("70", value: $startWeight, format: .number.precision(.fractionLength(0...1)))
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                    Text(verbatim: "kg").foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Activity", selection: profile.activity) {
                    ForEach(ActivityLevel.allCases) { Text($0.localizedName).tag($0) }
                }
                Text(profile.wrappedValue.activity.localizedDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Activity")
            } footer: {
                Text("onboarding.activity.footer")
            }
        }
    }

    private func goalForm(_ profile: Bindable<UserProfile>) -> some View {
        Form {
            Section("Goal") {
                Picker("Goal", selection: profile.goal) {
                    ForEach(GoalType.allCases) { Label($0.localizedName, systemImage: $0.systemImage).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if profile.wrappedValue.goal != .maintain {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Weekly rate")
                            Spacer()
                            Text("\(Format.grams(profile.wrappedValue.weeklyRateKg, decimals: 2)) kg")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: profile.weeklyRateKg, in: 0.1...1.0, step: 0.05)
                    }
                }
            }
            Section("Macronutrient split") {
                Picker("Strategy", selection: profile.strategy) {
                    ForEach(MacroStrategy.allCases.filter { $0 != .custom }) { Text($0.localizedName).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Text("onboarding.goal.footer")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
