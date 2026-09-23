/// Which strategy resolves an IPv4-wildcard WebDAV host to a concrete IP.
///
/// [discovery] is the install default: SSDP/mDNS first, then a subnet-aware
/// bounded-concurrency scan. [legacyScan] keeps the original serial isolate
/// scan for rollback and for users who relied on its exact behavior.
enum WebDavScanMode {
  discovery,
  legacyScan,
}
