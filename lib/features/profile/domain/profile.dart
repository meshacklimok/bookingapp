class Profile {
  const Profile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.avatarUrl,
    required this.isPlatformAdmin,
  });

  final String id;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;
  final bool isPlatformAdmin;

  factory Profile.fromMap(Map<String, dynamic> m) => Profile(
        id: m['id'] as String,
        fullName: m['full_name'] as String?,
        phone: m['phone'] as String?,
        avatarUrl: m['avatar_url'] as String?,
        isPlatformAdmin: m['is_platform_admin'] as bool? ?? false,
      );
}
