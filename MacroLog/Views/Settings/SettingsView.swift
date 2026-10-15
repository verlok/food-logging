import SwiftUI

/// Profile, goal, macro strategy, expenditure and integrations.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var apiKey = AppSecrets.claudeAPIKey ?? ""
    @State private var model = AIFoodService.shared.model
    @State private var showingResetConfirmation = false

    var body: some View {
        @Bindable var profile = store.profile
        NavigationStack {
            Form {
                Section("Expenditure") {
                    LabeledContent("Estimated expenditure", value: "\(Format.kcal(store.expenditure.kilocaloriesPerDay)) kcal")
                    Text(expenditureExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Toggle("Override manually", isOn: Binding(
                        get: { profile.manualExpenditure != nil },
                        set: { enabled in
                            profile.manualExpenditure = enabled ? store.expenditure.kilocaloriesPerDay.rounded() : nil
                            store.profileDidChange()
                        }
                    ))
                    if profile.manualExpenditure != nil {
                        HStack {
                            Text("Daily expenditure")
                            Spacer()
                            TextField("kcal", value: Binding(
                                get: { profile.manualExpenditure ?? 0 },
                                set: { profile.manualExpenditure = $0; store.profileDidChange() }
                            ), format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                            Text(verbatim: "kcal").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Goal") {
                    Picker("Goal", selection: $profile.goal) {
                        ForEach(GoalType.allCases) { Label($0.localizedName, systemImage: $0.systemImage).tag($0) }
                    }
                    if profile.goal != .maintain {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Weekly rate")
                                Spacer()
                                Text("\(Format.grams(profile.weeklyRateKg, decimals: 2)) kg")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $profile.weeklyRateKg, in: 0.1...1.0, step: 0.05)
                        }
                    }
                    targetsSummary
                }

                Section("Macronutrient split") {
                    Picker("Strategy", selection: $profile.strategy) {
                        ForEach(MacroStrategy.allCases) { Text($0.localizedName).tag($0) }
                    }
                    if profile.strategy == .custom {
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Protein per kg")
                                Spacer()
                                Text("\(Format.grams(profile.customProteinGramsPerKg, decimals: 1)) g/kg")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            Slider(value: $profile.customProteinGramsPerKg, in: 0.8...3.0, step: 0.1)
                        }
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Fat share")
                                Spacer()
                                Text(Format.percent(profile.customFatFraction))
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            Slider(value: $profile.customFatFraction, in: 0.15...0.6, step: 0.01)
                        }
                    } else {
                        Text("strategy.summary \(Format.grams(profile.proteinGramsPerKg, decimals: 1)) \(Format.percent(profile.fatFraction))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Profile") {
                    Picker("Sex", selection: $profile.sex) {
                        ForEach(BiologicalSex.allCases) { Text($0.localizedName).tag($0) }
                    }
                    DatePicker("Birth date", selection: $profile.birthDate, in: ...Date(), displayedComponents: .date)
                    HStack {
                        Text("Height")
                        Spacer()
                        TextField("cm", value: $profile.heightCm, format: .number)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                        Text(verbatim: "cm").foregroundStyle(.secondary)
                    }
                    Picker("Activity", selection: $profile.activity) {
                        ForEach(ActivityLevel.allCases) { Text($0.localizedName).tag($0) }
                    }
                    Text(profile.activity.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    SecureField("Claude API key", text: $apiKey)
                        .textContentType(.password)
                        .onSubmit { AppSecrets.claudeAPIKey = apiKey }
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                    Button("Save key") { AppSecrets.claudeAPIKey = apiKey }
                        .disabled(apiKey == (AppSecrets.claudeAPIKey ?? ""))
                    TextField("Model", text: $model)
                        .onSubmit { UserDefaults.standard.set(model, forKey: AIFoodService.modelDefaultsKey) }
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif
                } header: {
                    Text("AI dish creation")
                } footer: {
                    Text("settings.ai.footer")
                }

                Section("Language") {
                    Text("settings.language.hint")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    #if os(iOS)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        Link("Open system settings", destination: url)
                    }
                    #endif
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    LabeledContent("Foods in database", value: store.foods.count.formatted())
                }
            }
            .navigationTitle("Settings")
            .onChange(of: profile.goal) { _, _ in store.profileDidChange() }
            .onChange(of: profile.weeklyRateKg) { _, _ in store.profileDidChange() }
            .onChange(of: profile.strategy) { _, _ in store.profileDidChange() }
            .onChange(of: profile.customProteinGramsPerKg) { _, _ in store.profileDidChange() }
            .onChange(of: profile.customFatFraction) { _, _ in store.profileDidChange() }
            .onChange(of: profile.sex) { _, _ in store.profileDidChange() }
            .onChange(of: profile.birthDate) { _, _ in store.profileDidChange() }
            .onChange(of: profile.heightCm) { _, _ in store.profileDidChange() }
            .onChange(of: profile.activity) { _, _ in store.profileDidChange() }
        }
    }

    private var targetsSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily targets").font(.subheadline.weight(.semibold))
            NutrientSummaryGrid(nutrients: NutrientProfile(
                calories: store.targets.calories,
                protein: store.targets.protein,
                carbs: store.targets.carbs,
                fat: store.targets.fat
            ))
        }
        .padding(.vertical, 4)
    }

    private var expenditureExplanation: String {
        switch store.expenditure.method {
        case .formula:
            return String(localized: "expenditure.method.formula")
        case .adaptive(let dataWeight, let loggedDays):
            return String(localized: "expenditure.method.adaptive \(loggedDays) \(Format.percent(dataWeight))")
        case .manual:
            return String(localized: "expenditure.method.manual")
        }
    }
}
