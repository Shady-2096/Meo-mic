import Foundation
import Testing

@testable import MeoMicCore

// Real `pkgutil --check-signature` output for a Developer ID signed,
// notarized package, trimmed to the lines the check reads.
private let existentialAudioSignature = """
Package "BlackHole2ch-0.7.1.pkg":
   Status: signed by a developer certificate issued by Apple for distribution
   Notarization: trusted by the Apple notary service
   Signed with a trusted timestamp on: 2026-07-04 22:10:31 +0000
   Certificate Chain:
    1. Developer ID Installer: Existential Audio Inc. (Q5C99V536K)
       Expires: 2027-02-01 00:00:00 +0000
    2. Developer ID Certification Authority
    3. Apple Root CA
"""

@Test func acceptsPackageSignedByExistentialAudio() {
    #expect(BlackHoleInstaller.signatureIsAcceptable(existentialAudioSignature))
}

@Test func rejectsUnsignedPackage() {
    let output = """
    Package "BlackHole2ch-0.7.1.pkg":
       Status: no signature
    """
    #expect(!BlackHoleInstaller.signatureIsAcceptable(output))
}

@Test func rejectsPackageSignedByUntrustedCertificate() {
    let output = """
    Package "BlackHole2ch-0.7.1.pkg":
       Status: signed by untrusted certificate
       Certificate Chain:
        1. Developer ID Installer: Existential Audio Inc. (Q5C99V536K)
    """
    #expect(!BlackHoleInstaller.signatureIsAcceptable(output))
}

@Test func rejectsValidlySignedPackageFromAnotherPublisher() {
    // A correctly signed, notarized package is still refused when it is not
    // the vendor we expect: this is the check that stops a hijacked download
    // from reaching Installer.
    let output = """
    Package "Something.pkg":
       Status: signed by a developer certificate issued by Apple for distribution
       Certificate Chain:
        1. Developer ID Installer: Someone Else Ltd. (AB12CD34EF)
        2. Developer ID Certification Authority
        3. Apple Root CA
    """
    #expect(!BlackHoleInstaller.signatureIsAcceptable(output))
}

@Test func readsGatekeeperVerdict() {
    let accepted = """
    /tmp/BlackHole2ch-0.7.1.pkg: accepted
    source=Notarized Developer ID
    origin=Developer ID Installer: Existential Audio Inc. (Q5C99V536K)
    """
    let rejected = "/tmp/BlackHole2ch-0.7.1.pkg: rejected\nsource=no usable signature"

    #expect(BlackHoleInstaller.gatekeeperAccepted(accepted))
    #expect(!BlackHoleInstaller.gatekeeperAccepted(rejected))
    #expect(!BlackHoleInstaller.gatekeeperAccepted(""))
}

@Test func buildsOfficialDownloadURLs() {
    #expect(
        BlackHoleInstaller.packageURL(version: "0.7.1").absoluteString
            == "https://existential.audio/downloads/BlackHole2ch-0.7.1.pkg"
    )
    // Every candidate must come from the vendor's own host.
    for version in BlackHoleInstaller.versions {
        #expect(BlackHoleInstaller.packageURL(version: version).host == "existential.audio")
        #expect(BlackHoleInstaller.packageURL(version: version).scheme == "https")
    }
}
