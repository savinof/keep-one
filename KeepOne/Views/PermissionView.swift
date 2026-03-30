import SwiftUI

struct PermissionView: View {
    let title: String
    let message: String
    let buttonTitle: String
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: action) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(buttonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .disabled(isLoading)

            Spacer()
        }
        .navigationTitle("KeepOne")
    }
}
