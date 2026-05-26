/// A councillor enriched from Democracy Club's Candidates API (CC BY 4.0).
///
/// Everything here is best-effort: any field may be absent, and the whole
/// profile is null when no DC person could be matched.
class CouncillorProfile {
  final int personId;

  /// DC's name for the matched person (may include middle names).
  final String name;

  /// Portrait URL (full size) and a smaller thumbnail, when DC holds a photo.
  final String? imageUrl;
  final String? thumbnailUrl;

  final String? email;

  /// External links (Twitter, Facebook, homepage, …) derived from DC
  /// identifiers, each with a display [SocialLink.label] and a launchable URL.
  final List<SocialLink> links;

  /// Earliest year the person was recorded as elected, across all candidacies.
  final int? firstElectedYear;

  const CouncillorProfile({
    required this.personId,
    required this.name,
    this.imageUrl,
    this.thumbnailUrl,
    this.email,
    this.links = const [],
    this.firstElectedYear,
  });

  bool get isEmpty =>
      imageUrl == null &&
      thumbnailUrl == null &&
      email == null &&
      links.isEmpty &&
      firstElectedYear == null;

  /// Builds a profile from a Democracy Club `next/people/{id}` JSON object.
  factory CouncillorProfile.fromPersonJson(Map<String, dynamic> json) {
    final identifiers = (json['identifiers'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>();

    String? email = json['email'] as String?;
    final links = <SocialLink>[];
    for (final id in identifiers) {
      final type = (id['value_type'] as String?)?.toLowerCase() ?? '';
      final value = (id['value'] as String?)?.trim() ?? '';
      if (value.isEmpty) continue;
      if (type == 'email') {
        email ??= value;
      } else {
        final link = _linkFor(type, value);
        if (link != null) links.add(link);
      }
    }

    return CouncillorProfile(
      personId: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] as String?) ?? '',
      imageUrl: _nonEmpty(json['image'] as String?),
      thumbnailUrl: _nonEmpty(json['thumbnail'] as String?),
      email: _nonEmpty(email),
      links: links,
      firstElectedYear: _firstElectedYear(json['candidacies']),
    );
  }

  Map<String, dynamic> toJson() => {
        'personId': personId,
        'name': name,
        'imageUrl': imageUrl,
        'thumbnailUrl': thumbnailUrl,
        'email': email,
        'links': [for (final l in links) l.toJson()],
        'firstElectedYear': firstElectedYear,
      };

  factory CouncillorProfile.fromJson(Map<String, dynamic> json) =>
      CouncillorProfile(
        personId: (json['personId'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        imageUrl: json['imageUrl'] as String?,
        thumbnailUrl: json['thumbnailUrl'] as String?,
        email: json['email'] as String?,
        links: (json['links'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SocialLink.fromJson)
            .toList(),
        firstElectedYear: (json['firstElectedYear'] as num?)?.toInt(),
      );
}

/// A labelled external link. URLs are normalised so usernames become full URLs.
class SocialLink {
  final String label;
  final String url;

  const SocialLink({required this.label, required this.url});

  Map<String, dynamic> toJson() => {'label': label, 'url': url};

  factory SocialLink.fromJson(Map<String, dynamic> json) => SocialLink(
        label: (json['label'] as String?) ?? '',
        url: (json['url'] as String?) ?? '',
      );
}

String? _nonEmpty(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();

/// Maps a DC identifier `value_type` + value to a labelled link, handling both
/// bare usernames (twitter/facebook) and full URLs.
SocialLink? _linkFor(String type, String value) {
  bool isUrl(String v) => v.startsWith('http://') || v.startsWith('https://');

  if (type.contains('twitter')) {
    final handle = value.replaceFirst('@', '');
    return SocialLink(
      label: 'Twitter/X',
      url: isUrl(value) ? value : 'https://twitter.com/$handle',
    );
  }
  if (type.contains('facebook')) {
    return SocialLink(label: 'Facebook', url: value);
  }
  if (type.contains('instagram')) {
    return SocialLink(
      label: 'Instagram',
      url: isUrl(value) ? value : 'https://instagram.com/$value',
    );
  }
  if (type.contains('linkedin')) {
    return SocialLink(label: 'LinkedIn', url: value);
  }
  if (type.contains('youtube')) {
    return SocialLink(label: 'YouTube', url: value);
  }
  if (type.contains('wikipedia')) {
    return SocialLink(label: 'Wikipedia', url: value);
  }
  // Catches homepage_url, party_ppc_page_url and similar URL identifiers.
  if (isUrl(value) &&
      (type.contains('homepage') ||
          type.contains('website') ||
          type.contains('url') ||
          type.contains('page'))) {
    return SocialLink(label: 'Website', url: value);
  }
  return null;
}

/// Minimum election year across candidacies flagged `elected`, parsed from the
/// trailing `YYYY-MM-DD` in each ballot id (e.g. `local.foo.ward.2021-05-06`).
int? _firstElectedYear(dynamic candidacies) {
  if (candidacies is! List) return null;
  int? earliest;
  for (final c in candidacies) {
    if (c is! Map<String, dynamic>) continue;
    if (c['elected'] != true) continue;
    final ballot = c['ballot'];
    final id = ballot is Map<String, dynamic>
        ? ballot['ballot_paper_id'] as String?
        : null;
    final match = id == null
        ? null
        : RegExp(r'(\d{4})-\d{2}-\d{2}$').firstMatch(id);
    final year = match == null ? null : int.tryParse(match.group(1)!);
    if (year != null && (earliest == null || year < earliest)) {
      earliest = year;
    }
  }
  return earliest;
}
