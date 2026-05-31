import SwiftUI

struct WatchContentView: View {
    @StateObject private var viewModel = WatchAlarmViewModel()

    var body: some View {
        VStack(spacing: 12) {
            Text("딩띵스")
                .font(.headline)

            Text(viewModel.remainingText)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()

            Text(viewModel.statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 8) {
                Button {
                    viewModel.decreaseInterval()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(viewModel.isRunning)

                Text("\(viewModel.intervalMinutes)분")
                    .font(.caption)
                    .frame(minWidth: 42)

                Button {
                    viewModel.increaseInterval()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(viewModel.isRunning)
            }

            Button {
                viewModel.toggleTimer()
            } label: {
                Label(viewModel.isRunning ? "중지" : "시작",
                      systemImage: viewModel.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(viewModel.isRunning ? .red : .mint)
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    WatchContentView()
}
