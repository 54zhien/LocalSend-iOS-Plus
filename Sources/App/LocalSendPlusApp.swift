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
  @Environment(\.scenePhase) private var scenePhase

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
    .tint(model.settings.accentColor)
    .preferredColorScheme(model.settings.preferredColorScheme)
    .environment(\.locale, model.settings.selectedLocale)
    .background(AmbientBackground())
    .overlay {
      if model.addFavoriteRequested {
        AddFavoritePanel(
          onCancel: {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
              model.addFavoriteRequested = false
            }
          },
          onSave: { alias, host in
            model.addFavorite(alias: alias, host: host)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
              model.addFavoriteRequested = false
            }
          }
        )
        .transition(.opacity)
        .zIndex(1)
      }
    }
    .task {
      model.start()
      model.consumeShareInbox()
    }
    .onOpenURL { _ in
      model.consumeShareInbox()
    }
    .sheet(item: Binding(
      get: { model.isWebReceiving ? nil : model.incoming },
      set: { model.incoming = $0 }
    )) { request in
      IncomingApprovalSheet(
        request: request,
        onAccept: { selected in model.accept(request, acceptedIds: selected) },
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
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        // iOS tore the listening socket down while suspended; recreate it before the user
        // wonders why the phone stopped accepting transfers.
        model.resumeAfterForeground()
        model.endBackgroundGrace()
      case .background:
        model.beginBackgroundGrace()
      default:
        break
      }
    }
  }
}
