/// Mirrors the `org_status` enum. Only platform admins can move an organization out of `pending`.
enum OrgStatus {
  pending,
  approved,
  suspended;

  static OrgStatus parse(String? value) => OrgStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => OrgStatus.pending,
      );

  String get label => switch (this) {
        OrgStatus.pending => 'Pending approval',
        OrgStatus.approved => 'Approved',
        OrgStatus.suspended => 'Suspended',
      };

  String get explanation => switch (this) {
        OrgStatus.pending =>
          'Our team is reviewing your organization. You can set things up now; customers will see your services once it is approved.',
        OrgStatus.approved => 'Your organization is live. Customers can find and book your services.',
        OrgStatus.suspended => 'Your organization is suspended and hidden from customers. Contact support to find out why.',
      };
}

class Organization {
  const Organization({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    this.description,
    this.category,
  });

  final String id;
  final String name;
  final String slug;
  final OrgStatus status;
  final String? description;
  final String? category;

  bool get isApproved => status == OrgStatus.approved;

  factory Organization.fromMap(Map<String, dynamic> m) => Organization(
        id: m['id'] as String,
        name: m['name'] as String,
        slug: m['slug'] as String,
        status: OrgStatus.parse(m['status'] as String?),
        description: m['description'] as String?,
        category: m['category'] as String?,
      );
}

/// Same list the discover filter uses.
const orgCategories = ['Beauty', 'Health', 'Education', 'Events', 'Sports', 'Other'];

/// "Wanjiru's Salon & Spa" -> "wanjirus-salon-spa". Falls back to "org" when nothing usable is left.
String slugify(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r"['’]"), '')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'org' : slug;
}
