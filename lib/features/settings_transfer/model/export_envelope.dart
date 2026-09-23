import 'dart:convert';

import 'package:iris/features/settings_transfer/engine/platform_key_policy.dart';
import 'package:iris/features/settings_transfer/model/transfer_section.dart';
import 'package:package_info_plus/package_info_plus.dart';

// Export envelope — versioned, per-section tolerant.
//
// sourcePlatform stamps the exporting device (android/ios/windows/linux/
// macos, or `unknown` for legacy files). Cross-platform imports keep common
// + target-platform keys and skip source-platform-only keys.

const int kTransferFormatVersion = 2;

class ExportEnvelope {
  const ExportEnvelope({
    required this.format,
    required this.appVersion,
    required this.exportedAt,
    required this.sections,
    this.enc,
    this.sourcePlatform = kTransferPlatformUnknown,
  });

  final int format;
  final String appVersion;
  final String exportedAt; // ISO8601
  final Map<String, dynamic> sections;
  final Map<String, dynamic>? enc; // present when encrypted
  final String sourcePlatform; // exporting device, see transferPlatformName

  Map<String, dynamic> toJson() => {
        'format': format,
        'appVersion': appVersion,
        'exportedAt': exportedAt,
        'sourcePlatform': sourcePlatform,
        'sections': sections,
        if (enc != null) 'enc': enc,
      };

  factory ExportEnvelope.fromJson(Map<String, dynamic> j) => ExportEnvelope(
        format: j['format'] as int,
        appVersion: j['appVersion'] as String? ?? 'unknown',
        exportedAt: j['exportedAt'] as String? ?? '',
        sections: (j['sections'] as Map).cast<String, dynamic>(),
        enc: (j['enc'] as Map?)?.cast<String, dynamic>(),
        sourcePlatform: j['sourcePlatform'] as String? ?? kTransferPlatformUnknown,
      );

  bool get isEncrypted => enc != null;

  // --- helpers ---

  static Future<ExportEnvelope> create(Map<String, dynamic> sections) async {
    String appVersion = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    return ExportEnvelope(
      format: kTransferFormatVersion,
      appVersion: appVersion,
      exportedAt: DateTime.now().toIso8601String(),
      sections: sections,
      sourcePlatform: currentTransferPlatformName,
    );
  }

  String encode({bool pretty = true}) {
    final json = toJson();
    return pretty ? const JsonEncoder.withIndent('  ').convert(json) : jsonEncode(json);
  }

  static ExportEnvelope decode(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    return ExportEnvelope.fromJson(j);
  }

  bool hasSection(TransferSection s) => sections.containsKey(s.key);

  Map<String, dynamic>? sectionPayload(TransferSection s) {
    final v = sections[s.key];
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return v.cast<String, dynamic>();
    return null;
  }
}
