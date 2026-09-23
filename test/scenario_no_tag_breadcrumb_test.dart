import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iris/features/paginated_browser/data_source/paginated_browser_data_source.dart';
import 'package:iris/features/paginated_browser/paginated_browser_page.dart'
    show crumbColor, crumbLabel;
import 'package:iris/l10n/app_localizations.dart';

/// Scenario play queue no-tag breadcrumb: the data source emits the
/// canonical [kNoTagCrumb] payload (never display text) and the generic
/// renderer localizes it via `tag_no_tag`, keeping the subdued grey.
void main() {
  test('no-tag crumb localizes via tag_no_tag (en)', () async {
    final t = await lookupAppLocalizations(const Locale('en'));
    expect(crumbLabel(kNoTagCrumb, t), t.tag_no_tag);
    expect(t.tag_no_tag, 'No tag');
  });

  test('no-tag crumb localizes via tag_no_tag (zh)', () async {
    final t = await lookupAppLocalizations(const Locale('zh'));
    expect(crumbLabel(kNoTagCrumb, t), t.tag_no_tag);
  });

  test('a real tag literally named like no-tag keeps its own rendering', () async {
    final t = await lookupAppLocalizations(const Locale('en'));
    // A genuine tag name travels under the tag sentinel, never the muted one,
    // so it can never be confused with the no-tag marker.
    expect(crumbLabel('\u0000tag:${t.tag_no_tag}', t), t.tag_no_tag);
    expect(crumbLabel('\u0000tag:无tag', t), '无tag');
  });

  test('no-tag crumb keeps the subdued grey, tag crumb the primary', () {
    const scheme = ColorScheme.light();
    expect(crumbColor(kNoTagCrumb, scheme), isNotNull);
    expect(
      crumbColor(kNoTagCrumb, scheme),
      scheme.onSurfaceVariant.withValues(alpha: 0.7),
    );
    expect(
      crumbColor('\u0000tag:some-tag', scheme),
      scheme.primary,
    );
  });
}
