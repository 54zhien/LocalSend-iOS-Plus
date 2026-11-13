import Darwin
import Foundation

/// Sends LocalSend's UDP announcement so peers list this device immediately.
///
/// Upstream broadcasts the same JSON to `224.0.0.167:53317`. iOS only allows that with the
/// `com.apple.developer.networking.multicast` entitlement, but a *unicast* datagram needs no
/// entitlement — it only needs the local-network permission. Peers accept both, so announcing
/// host-by-host gives the same effect without Apple's approval: the receiver matches the JSON
/// and adds us to its device list.
final class Announcer {
  private let queue = DispatchQueue(label: "org.localsend.native.announcer")
  private var socketFD: Int32 = -1

  deinit {
    if socketFD >= 0 { close(socketFD) }
  }

  /// Fire-and-forget: every host gets one datagram, errors are ignored (a sleeping phone in the
  /// subnet is normal, not a failure worth surfacing).
  func announce(_ payload: Data, hosts: [String], port: UInt16) {
    queue.async { [self] in
      if socketFD < 0 {
        socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { return }
        var on: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))
      }

      payload.withUnsafeBytes { raw in
        guard let base = raw.baseAddress else { return }
        for host in hosts {
          var address = sockaddr_in()
          address.sin_family = sa_family_t(AF_INET)
          address.sin_port = port.bigEndian
          guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { continue }
          withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
              _ = sendto(
                socketFD,
                base,
                raw.count,
                0,
                sockaddrPointer,
                socklen_t(MemoryLayout<sockaddr_in>.size)
              )
            }
          }
        }
      }
    }
  }
}
