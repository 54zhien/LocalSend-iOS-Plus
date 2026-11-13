import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// Renders a pairing QR code from a `https://host:port` address.
///
/// LocalSend peers accept a plain address in their manual-add dialog, so the code carries
/// the URL itself instead of an opaque payload.
struct QRCodeView: View {
  let url: URL
  var size: CGFloat = 220

  var body: some View {
    if let image = Self.makeImage(from: url.absoluteString, size: size) {
      Image(uiImage: image)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
        .frame(width: size, height: size)
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous))
    } else {
      RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
        .fill(.white.opacity(0.12))
        .frame(width: size, height: size)
        .overlay(Image(systemName: "qrcode").font(.system(size: 48)).foregroundStyle(.secondary))
    }
  }

  static func makeImage(from string: String, size: CGFloat) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(string.utf8)
    filter.correctionLevel = "M"

    guard let output = filter.outputImage else { return nil }
    let scale = size / output.extent.width
    let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let context = CIContext()
    guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
    return UIImage(cgImage: cgImage)
  }
}

/// Camera sheet that hands a scanned string back to the caller.
struct QRScannerView: UIViewControllerRepresentable {
  let onCode: (String) -> Void
  let onCancel: () -> Void

  func makeUIViewController(context: Context) -> ScannerViewController {
    let controller = ScannerViewController()
    controller.onCode = onCode
    controller.onCancel = onCancel
    return controller
  }

  func updateUIViewController(_ controller: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
  var onCode: ((String) -> Void)?
  var onCancel: (() -> Void)?

  private let session = AVCaptureSession()
  private let sessionQueue = DispatchQueue(label: "com.imzhien.localsendplus.scanner")
  private var previewLayer: AVCaptureVideoPreviewLayer?
  private var hasReported = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureCamera()
    addOverlay()
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    sessionQueue.async { [session] in
      if !session.isRunning { session.startRunning() }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer?.frame = view.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [session] in
      if session.isRunning { session.stopRunning() }
    }
  }

  private func configureCamera() {
    guard let device = AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: device),
      session.canAddInput(input)
    else {
      return
    }
    session.addInput(input)

    let output = AVCaptureMetadataOutput()
    guard session.canAddOutput(output) else { return }
    session.addOutput(output)
    output.setMetadataObjectsDelegate(self, queue: .main)
    output.metadataObjectTypes = [.qr]

    let layer = AVCaptureVideoPreviewLayer(session: session)
    layer.videoGravity = .resizeAspectFill
    layer.frame = view.bounds
    view.layer.addSublayer(layer)
    previewLayer = layer
  }

  private func addOverlay() {
    let frame = UIView()
    frame.translatesAutoresizingMaskIntoConstraints = false
    frame.layer.borderColor = UIColor.white.withAlphaComponent(0.8).cgColor
    frame.layer.borderWidth = 2
    frame.layer.cornerRadius = AppRadius.control
    frame.layer.cornerCurve = .continuous
    view.addSubview(frame)

    let hint = UILabel()
    hint.translatesAutoresizingMaskIntoConstraints = false
    hint.text = String(localized: "Point the camera at the other device's pairing code")
    hint.textColor = .white
    hint.font = .preferredFont(forTextStyle: .footnote)
    hint.numberOfLines = 0
    hint.textAlignment = .center
    view.addSubview(hint)

    let close = UIButton(type: .system)
    close.translatesAutoresizingMaskIntoConstraints = false
    close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    close.tintColor = .white
    close.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    view.addSubview(close)

    NSLayoutConstraint.activate([
      frame.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      frame.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      frame.widthAnchor.constraint(equalToConstant: 240),
      frame.heightAnchor.constraint(equalToConstant: 240),

      hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
      hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
      hint.topAnchor.constraint(equalTo: frame.bottomAnchor, constant: 24),

      close.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      close.widthAnchor.constraint(equalToConstant: 32),
      close.heightAnchor.constraint(equalToConstant: 32),
    ])
  }

  @objc private func cancelTapped() {
    onCancel?()
  }

  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard !hasReported,
      let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
      let value = object.stringValue,
      !value.isEmpty
    else {
      return
    }
    hasReported = true
    UINotificationFeedbackGenerator().notificationOccurred(.success)
    onCode?(value)
  }
}
