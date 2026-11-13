import SwiftUI

@main
@MainActor
struct LocalSendNativeApp: App {
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
    let outgoingShown = Binding(
      get: { model.outgoing != nil },
      set: { shown in
        if !shown { model.dismissOutgoing() }
      }
    )

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
    .task { model.start() }
    .sheet(isPresented: outgoingShown) {
      if let transfer = model.outgoing {
        TransferProgressView(transfer: transfer)
      }
    }
  }
}
