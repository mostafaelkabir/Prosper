import SwiftUI

struct BlockView: View {
    @State private var showCreateBlock = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "lock.open")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("No active blocks")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("Block distracting apps and websites\nfor a set time with no way to undo.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Spacer()

                Button {
                    showCreateBlock = true
                } label: {
                    Label("New Block", systemImage: "lock.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationTitle("Block")
            .sheet(isPresented: $showCreateBlock) {
                CreateBlockView()
            }
        }
    }
}
