import SwiftUI

struct CarPlayWidgetSettingsView: View {
    @StateObject var viewModel: CarPlaySettingsViewModel

    var body: some View {
        Form {
            Section("Texto") {
                VStack(alignment: .leading) {
                    Text("Tamaño: \(Int(viewModel.fontSize))")
                    Slider(value: $viewModel.fontSize, in: 14...34, step: 1)
                }
                Toggle("Alineado al centro", isOn: $viewModel.centeredText)
                Toggle("Solo línea actual", isOn: $viewModel.showOnlyCurrentLine)
            }
        }
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [.purple.opacity(0.3), .blue.opacity(0.25)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .navigationTitle("Widget CarPlay")
    }
}

struct CarPlayWidgetSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        CarPlayWidgetSettingsView(viewModel: CarPlaySettingsViewModel())
    }
}
