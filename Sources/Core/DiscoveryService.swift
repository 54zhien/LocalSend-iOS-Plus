import Foundation
import Observation

/// Finds LocalSend peers by probing `GET /api/localsend/v2/info` across the local /24.
///
/// The protocol's fast path is a UDP multicast announce on 224.0.0.167, but iOS only grants
/// multicast to apps holding the `com.apple.developer.networking.multicast` entitlement.
/// Probing the HTTP API needs nothing beyond the local network prompt, finds every peer that
/// announces by multicast, and also finds peers that do not multicast at all.
@MainActor
@Observable
final class DiscoveryService {
  private(set) var devices: [Device] = []
  private(set) var isScanning = false
  private(set) var lastScan: Date?

  private var loop: Task<Void, Never>?
  private var ownFingerprint = ""
  private var interval: Double = 12
  private var known: [String: Device] = [:]

  func start(ownFingerprint: String, interval: Double) {
    self.ownFingerprint = ownFingerprint
    self.interval = max(4, interval)
    guard loop == nil else { return }
    loop = Task { [weak self] in
      while !Task.isCancelled {
        await self?.scan()
        let seconds = self?.interval ?? 12
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      }
    }
  }

  func stop() {
    loop?.cancel()
    loop = nil
  }

  func restart(interval: Double) {
    self.interval = max(4, interval)
  }

  /// Records a peer that called our `/register` endpoint, so it shows up without waiting for a scan.
  func register(peer: DeviceInfoDTO, host: String) {
    guard !host.isEmpty, peer.fingerprint != ownFingerprint else { return }
    let device = Device(
      id: peer.fingerprint,
      alias: peer.alias,
      deviceType: DeviceType(wire: peer.deviceType),
      host: host,
      port: peer.port ?? 53317,
      lastSeen: Date()
    )
    known[device.id] = device
    publish()
  }

  func scan() async {
    guard !isScanning else { return }
    isScanning = true
    defer { isScanning = false }

    let hosts = NetworkInfo.candidateHosts()
    var found: [String: Device] = [:]

    for start in stride(from: 0, to: hosts.count, by: 32) {
      let end = min(start + 32, hosts.count)
      let batch = Array(hosts[start..<end])
      await withTaskGroup(of: Device?.self) { group in
        for host in batch {
          group.addTask { await DeviceProbe.info(host: host) }
        }
        for await device in group {
          guard let device, device.id != ownFingerprint else { continue }
          found[device.id] = device
        }
      }
      // Publish per batch so the list fills in while the scan is still running.
      known.merge(found) { _, new in new }
      publish()
    }

    lastScan = Date()
    publish()
  }

  private func publish() {
    devices = known.values.sorted { lhs, rhs in
      lhs.alias.localizedCaseInsensitiveCompare(rhs.alias) == .orderedAscending
    }
  }
}

/// One-shot HTTP probe, free of actor isolation so the batches really run in parallel.
enum DeviceProbe {
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 0.8
    configuration.timeoutIntervalForResource = 1.5
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.urlCache = nil
    return URLSession(configuration: configuration)
  }()

  static func info(host: String) async -> Device? {
    guard let url = URL(string: "http://\(host):53317/api/localsend/v2/info") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    guard let (data, response) = try? await session.data(for: request),
      let http = response as? HTTPURLResponse,
      http.statusCode == 200,
      let dto = try? JSONDecoder().decode(DeviceInfoDTO.self, from: data),
      !dto.fingerprint.isEmpty
    else {
      return nil
    }
    return Device(
      id: dto.fingerprint,
      alias: dto.alias,
      deviceType: DeviceType(wire: dto.deviceType),
      host: host,
      port: dto.port ?? 53317,
      lastSeen: Date()
    )
  }
}
