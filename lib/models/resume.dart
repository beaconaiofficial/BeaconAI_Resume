import 'package:hive_ce/hive.dart';
import '../constants/app_constants.dart';
import 'app_enums.dart';

part 'resume.g.dart';

/// Resume — top-level Hive model for both master and tailored resumes.
/// Rule §2: User data is NEVER deleted. isArchived = true is the only
///          "removal" — soft-reset master resumes go to archive, never deleted.
/// Rule §12: File bytes are never stored permanently. Only extracted text
///           and metadata live in SourceDocument — not here.
@HiveType(typeId: AppConstants.resumeTypeId)
class Resume extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  DateTime createdAt;

  @HiveField(3)
  DateTime updatedAt;

  /// True for the user's master resume. False for tailored resumes.
  @HiveField(4)
  bool isMaster;

  /// One of the 12 template IDs defined in AppConstants.
  @HiveField(5)
  String templateId;

  /// Horizon template accent color (one of 6 hex color strings).
  /// Only used when templateId == AppConstants.templateHorizon.
  @HiveField(6)
  String? templateAccentColor;

  /// Raw job description text linked to this tailored resume.
  /// null for master resumes.
  @HiveField(7)
  String? linkedJobDescription;

  /// Number of source documents uploaded against this resume.
  /// Tracked against tier upload limits (Free=4, Basic=10, Pro=unlimited).
  @HiveField(8)
  int uploadCount;

  /// True for master resumes that have been soft-reset after 30 days.
  /// Archived resumes are moved to archive in My Documents — NEVER deleted.
  @HiveField(9)
  bool isArchived;

  /// Company name extracted from job posting.
  /// Used for search and filter in My Documents. Tailored resumes only.
  @HiveField(10)
  String? companyName;

  /// Role title extracted from job posting.
  /// Used for search and filter in My Documents. Tailored resumes only.
  @HiveField(11)
  String? roleTitle;

  Resume({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.isMaster,
    this.templateId = AppConstants.defaultTemplateId,
    this.templateAccentColor,
    this.linkedJobDescription,
    this.uploadCount = 0,
    this.isArchived = false,
    this.companyName,
    this.roleTitle,
  });

  // ── Computed Properties ─────────────────────────────────────────────────────

  /// True if this resume has reached the upload limit for the given tier.
  bool isUploadLimitReached(TierEnum tier) {
    if (tier.isPro) return false;
    return uploadCount >= tier.uploadLimit;
  }

  /// Display label shown in My Documents and Dashboard.
  String get displayTitle {
    if (isMaster) return title;
    if (companyName != null && roleTitle != null) {
      return '$roleTitle — $companyName';
    }
    if (companyName != null) return '$title — $companyName';
    return title;
  }

  /// True if this is a tailored resume (has a linked job description).
  bool get isTailored => !isMaster && linkedJobDescription != null;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  /// Marks this master resume as archived (soft-reset).
  /// Rule §2: Sets isArchived = true. Never deletes.
  void archive() {
    isArchived = true;
    updatedAt = DateTime.now();
    save();
  }

  /// Updates the updatedAt timestamp and saves.
  void touch() {
    updatedAt = DateTime.now();
    save();
  }

  // ── Backup Serialization ────────────────────────────────────────────────────

  Map<String, dynamic> toBackupJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isMaster': isMaster,
        'templateId': templateId,
        'templateAccentColor': templateAccentColor,
        'linkedJobDescription': linkedJobDescription,
        'uploadCount': uploadCount,
        'isArchived': isArchived,
        'companyName': companyName,
        'roleTitle': roleTitle,
      };

  factory Resume.fromBackupJson(Map<String, dynamic> json) => Resume(
        id: json['id'] as String,
        title: json['title'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isMaster: json['isMaster'] as bool,
        templateId:
            json['templateId'] as String? ?? AppConstants.defaultTemplateId,
        templateAccentColor: json['templateAccentColor'] as String?,
        linkedJobDescription: json['linkedJobDescription'] as String?,
        uploadCount: json['uploadCount'] as int? ?? 0,
        isArchived: json['isArchived'] as bool? ?? false,
        companyName: json['companyName'] as String?,
        roleTitle: json['roleTitle'] as String?,
      );
}
