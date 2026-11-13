import CryptoKit
import Foundation
import Security

/// Hex helpers — LocalSend fingerprints are uppercase SHA-256 hex.
enum Hex {
  static func encode(_ data: Data) -> String {
    data.map { String(format: "%02X", $0) }.joined()
  }

  static func sha256(_ data: Data) -> String {
    encode(Data(SHA256.hash(data: data)))
  }
}

/// Minimal DER writer — just enough X.509 to mint a self-signed RSA certificate.
enum DER {
  static func length(_ count: Int) -> Data {
    if count < 0x80 {
      return Data([UInt8(count)])
    }
    var value = count
    var bytes: [UInt8] = []
    while value > 0 {
      bytes.insert(UInt8(value & 0xFF), at: 0)
      value >>= 8
    }
    return Data([0x80 | UInt8(bytes.count)] + bytes)
  }

  static func tlv(_ tag: UInt8, _ content: Data) -> Data {
    Data([tag]) + length(content.count) + content
  }

  static func sequence(_ items: [Data]) -> Data {
    tlv(0x30, items.reduce(Data(), +))
  }

  static func set(_ items: [Data]) -> Data {
    tlv(0x31, items.reduce(Data(), +))
  }

  static func integer(_ value: Data) -> Data {
    var bytes = value
    while bytes.count > 1, bytes.first == 0x00, (bytes[1] & 0x80) == 0 {
      bytes.removeFirst()
    }
    if let first = bytes.first, first & 0x80 != 0 {
      bytes.insert(0x00, at: 0)
    }
    return tlv(0x02, bytes)
  }

  static func integer(_ value: Int) -> Data {
    var big = value
    var bytes: [UInt8] = []
    repeat {
      bytes.insert(UInt8(big & 0xFF), at: 0)
      big >>= 8
    } while big > 0
    return integer(Data(bytes))
  }

  static func oid(_ bytes: [UInt8]) -> Data {
    tlv(0x06, Data(bytes))
  }

  static func utf8(_ string: String) -> Data {
    tlv(0x0C, Data(string.utf8))
  }

  static func null() -> Data {
    Data([0x05, 0x00])
  }

  static func bitString(_ data: Data) -> Data {
    tlv(0x03, Data([0x00]) + data)
  }

  static func utcTime(_ date: Date) -> Data {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "yyMMddHHmmss'Z'"
    return tlv(0x17, Data(formatter.string(from: date).utf8))
  }

  static func explicit(_ number: UInt8, _ content: Data) -> Data {
    tlv(0xA0 | number, content)
  }
}

/// The LocalSend device identity: an RSA-2048 key, a self-signed certificate with
/// `CN=LocalSend User`, and the SHA-256 fingerprint of the certificate in DER form.
///
/// LocalSend identifies devices purely by that fingerprint, so it replaces the random
/// UUID the Flutter client would otherwise generate.
final class LocalIdentity {
  /// OIDs used by the certificate.
  private enum OID {
    static let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    static let sha256WithRSA: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
    static let commonName: [UInt8] = [0x55, 0x04, 0x03]
  }

  private static let keyTag = Data("org.localsend.native.identity.key".utf8)
  private static let certTag = Data("org.localsend.native.identity.cert".utf8)

  let certificate: SecCertificate?
  let identity: SecIdentity?
  let fingerprint: String

  private init(certificate: SecCertificate?, identity: SecIdentity?, fingerprint: String) {
    self.certificate = certificate
    self.identity = identity
    self.fingerprint = fingerprint
  }

  /// Loads the stored identity, generating a fresh one on first launch.
  ///
  /// Falls back to a random fingerprint when the keychain refuses to hold an RSA key
  /// (the app then runs unencrypted, and the settings screen says so).
  static func load() -> LocalIdentity {
    if let existing = loadFromKeychain() {
      return existing
    }
    if let created = generate() {
      return created
    }
    let fallback = UserDefaults.standard.string(forKey: "fingerprint") ?? {
      let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
      UserDefaults.standard.set(value, forKey: "fingerprint")
      return value
    }()
    return LocalIdentity(certificate: nil, identity: nil, fingerprint: fallback)
  }

  // MARK: Keychain

  private static func loadFromKeychain() -> LocalIdentity? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassCertificate,
      kSecAttrApplicationTag as String: certTag,
      kSecReturnRef as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let value = item,
      CFGetTypeID(value) == SecCertificateGetTypeID()
    else {
      return nil
    }
    let certificate = value as! SecCertificate
    let der = SecCertificateCopyData(certificate) as Data

    return LocalIdentity(
      certificate: certificate,
      identity: LocalIdentity.keychainIdentity(for: keyTag),
      fingerprint: Hex.sha256(der)
    )
  }

  private static func generate() -> LocalIdentity? {
    guard let key = loadOrCreateKey() else { return nil }
    guard let publicData = SecKeyCopyExternalRepresentation(key, nil) else { return nil }
    let publicDER = publicData as Data

    let name = DER.sequence([
      DER.set([DER.sequence([DER.oid(OID.commonName), DER.utf8("LocalSend User")])])
    ])
    let algorithm = DER.sequence([DER.oid(OID.sha256WithRSA), DER.null()])
    let spki = DER.sequence([algorithm, DER.bitString(publicDER)])

    let now = Date()
    let notBefore = now.addingTimeInterval(-60 * 60 * 24)
    let notAfter = now.addingTimeInterval(60 * 60 * 24 * 365 * 20)
    let validity = DER.sequence([DER.utcTime(notBefore), DER.utcTime(notAfter)])

    var serialBytes = [UInt8](repeating: 0, count: 16)
    _ = SecRandomCopyBytes(kSecRandomDefault, serialBytes.count, &serialBytes)
    serialBytes[0] &= 0x7F

    let tbs = DER.sequence([
      DER.explicit(0, DER.integer(2)),
      DER.integer(Data(serialBytes)),
      algorithm,
      name,
      validity,
      name,
      spki,
    ])

    var error: Unmanaged<CFError>?
    guard let signatureData = SecKeyCreateSignature(
      key,
      .rsaSignatureMessagePKCS1v15SHA256,
      tbs as CFData,
      &error
    )
    else {
      return nil
    }
    let signature = signatureData as Data

    let certificateDER = DER.sequence([tbs, algorithm, DER.bitString(signature)])
    guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
      return nil
    }

    let certQuery: [String: Any] = [
      kSecClass as String: kSecClassCertificate,
      kSecAttrApplicationTag as String: keyTag,
      kSecValueRef as String: certificate,
    ]
    SecItemDelete(certQuery as CFDictionary)
    SecItemAdd(certQuery as CFDictionary, nil)

    let identity = LocalIdentity.keychainIdentity(for: keyTag)

    return LocalIdentity(
      certificate: certificate,
      identity: identity,
      fingerprint: Hex.sha256(certificateDER)
    )
  }

  private static func loadOrCreateKey() -> SecKey? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: keyTag,
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecReturnRef as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
      let value = item,
      CFGetTypeID(value) == SecKeyGetTypeID()
    {
      return value as! SecKey
    }

    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeySizeInBits as String: 2048,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: keyTag,
      ],
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      return nil
    }
    return key
  }

  /// iOS has no SecIdentityCreateWithCertificate; a keychain query pairs the certificate
  /// and its private key when both were stored under the same application tag.
  static func keychainIdentity(for tag: Data) -> SecIdentity? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassIdentity,
      kSecAttrApplicationTag as String: tag,
      kSecReturnRef as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let item else {
      return nil
    }
    guard CFGetTypeID(item) == SecIdentityGetTypeID() else { return nil }
    return (item as! SecIdentity)
  }
}

