import Darwin
import Foundation
import UIKit

enum NetworkInfo {
  /// IPv4 addresses of active, non-loopback interfaces (iOS keeps `en0` first).
  static func ipv4Addresses() -> [String] {
    var addresses: [String] = []
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
    defer { freeifaddrs(ifaddr) }

    for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let flags = Int32(pointer.pointee.ifa_flags)
      guard let sockaddr = pointer.pointee.ifa_addr, sockaddr.pointee.sa_family == UInt8(AF_INET) else { continue }
      guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
      var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let result = getnameinfo(
        sockaddr,
        socklen_t(sockaddr.pointee.sa_len),
        &host,
        socklen_t(host.count),
        nil,
        0,
        NI_NUMERICHOST
      )
      if result == 0 {
        let ip = String(cString: host)
        if !ip.isEmpty {
          addresses.append(ip)
        }
      }
    }
    return addresses
  }

  /// Every host of the local /24 that is not this device.
  ///
  /// iOS only grants UDP multicast with a special entitlement, so discovery probes the HTTP
  /// API directly instead: 254 requests, no permission prompt beyond local network access.
  static func candidateHosts(limit: Int = 254) -> [String] {
    var hosts: [String] = []
    var seen = Set<String>()
    let own = Set(ipv4Addresses())
    for address in own {
      let parts = address.split(separator: ".")
      guard parts.count == 4 else { continue }
      let prefix = "\(parts[0]).\(parts[1]).\(parts[2])"
      for last in 1...limit {
        let host = "\(prefix).\(last)"
        if own.contains(host) || seen.contains(host) {
          continue
        }
        seen.insert(host)
        hosts.append(host)
      }
    }
    return hosts
  }
}

struct DeviceIdentity {
  var alias: String
  var fingerprint: String
  var deviceModel: String = UIDevice.current.model
  var version = "2.2"
  var port = 53317
  /// `https` when encryption is enabled — the server then speaks TLS.
  var protocolName = "https"

  var addresses: [String] { NetworkInfo.ipv4Addresses() }
  var primaryAddress: String { addresses.first ?? "0.0.0.0" }

  func infoDTO(downloadEnabled: Bool) -> DeviceInfoDTO {
    DeviceInfoDTO(
      alias: alias,
      version: version,
      deviceModel: deviceModel,
      deviceType: DeviceType.mobile.rawValue,
      fingerprint: fingerprint,
      port: port,
      protocolName: protocolName,
      download: downloadEnabled
    )
  }

  func announce(downloadEnabled: Bool) -> MulticastAnnounce {
    MulticastAnnounce(
      alias: alias,
      version: version,
      deviceModel: deviceModel,
      deviceType: DeviceType.mobile.rawValue,
      fingerprint: fingerprint,
      port: port,
      protocolName: protocolName,
      download: downloadEnabled,
      announcement: true
    )
  }
}
