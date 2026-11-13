import SwiftUI

@main
struct LocalSendPlusApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
    }
  }
}

struct RootView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    @Bindable var model = model

    TabView {
      ReceiveView()
        .tabItem { Label("Receive", systemImage: "wifi") }

      SendView()
        .tabItem { Label("Send", systemImage: "paperplane.fill") }

      SettingsView(settings: model.settings)
        .tabItem { Label("Settings", systemImage: "gearshape.fill") }
    }
    .tint(.accentColor)
    .background(AmbientBackground())
    .task {
      model.start()
      model.consumeShareInbox()
    }
    .onOpenURL { _ in
      model.consumeShareInbox()
    }
    .sheet(item: $model.incoming) { request in
      IncomingApprovalSheet(
        request: request,
        onAccept: { model.accept(request) },
        onDecline: { model.decline(request) }
      )
    }
    .sheet(item: $model.pinRequest) { request in
      PinPromptSheet(alias: request.alias) { pin in
        model.submitPin(pin)
      }
    }
    .sheet(item: $model.outgoing) { _ in
      TransferProgressView()
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      ),
      presenting: model.errorMessage
    ) { _ in
      Button("OK", role: .cancel) {}
    } message: { message in
      Text(message)
    }
  }
}
