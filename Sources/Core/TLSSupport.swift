import Foundation
import Network
import Security

/// TLS plumbing shared by the server (incoming transfers) and the client (outgoing ones).
///
/// LocalSend peers authenticate each other with self-signed RSA certificates and pin the
/// SHA-256 fingerprint announced over HTTP/multicast. The server requests a client
/// certificate (optional, because browsers hitting the download page have none) and the
/// client pins the certificate it sees against the fingerprint it discovered.
enum TLS {
  /// Options for the receiving side.
  static func serverOptions(identity: LocalIdentity, requireClientCertificate: Bool) -> NWProtocolTLS.Options {
    let options = NWProtocolTLS.Options()
    if let secIdentity = identity.identity.flatMap(sec_identity_create) {
      sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
    }

    let protocolOptions = options.securityProtocolOptions
    sec_protocol_options_set_min_tls_protocol_version(protocolOptions, .TLSv12)
    sec_protocol_options_set_peer_authentication_required(protocolOptions, requireClientCertificate)
    sec_protocol_options_set_verify_block(protocolOptions, { _, _, complete in
      // A presented certificate is accepted: LocalSend trusts any structurally valid
      // self-signed certificate and identifies peers by fingerprint, not by a CA chain.
      complete(true)
    }, DispatchQueue.global(qos: .userInitiated))
    return options
  }

  /// Options for the sending side. `expectedFingerprint` pins the peer's certificate.
  static func clientOptions(identity: LocalIdentity, expectedFingerprint: String?) -> NWProtocolTLS.Options {
    let options = NWProtocolTLS.Options()
    if let secIdentity = identity.identity.flatMap(sec_identity_create) {
      sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
    }

    let protocolOptions = options.securityProtocolOptions
    sec_protocol_options_set_min_tls_protocol_version(protocolOptions, .TLSv12)

    let pin = expectedFingerprint?.uppercased()
    sec_protocol_options_set_verify_block(protocolOptions, { _, secTrust, complete in
      let trust = sec_trust_copy_ref(secTrust)
      guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
        let leaf = chain.first
      else {
        complete(false)
        return
      }

      let der = SecCertificateCopyData(leaf) as Data
      let fingerprint = Hex.sha256(der)

      if let pin, !pin.isEmpty, pin != fingerprint {
        // Fingerprint mismatch: someone is impersonating the device we discovered.
        complete(false)
        return
      }
      complete(true)
    }, DispatchQueue.global(qos: .userInitiated))

    return options
  }
}
