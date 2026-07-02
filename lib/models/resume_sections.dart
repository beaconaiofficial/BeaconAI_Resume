import 'package:hive_ce/hive.dart';
import '../constants/app_constants.dart';
import 'app_enums.dart';

part 'resume_sections.g.dart';

// Claude's extraction API may return GPA, year, and date fields as JSON
// numbers instead of strings (e.g. gpa: 3.9772 or graduationYear: 2024).
// This helper coerces both representations to String? so fromJson() never
// throws a type cast error on those fields.
String? _s(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is num) return v.toString();
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// ResumeSection  (polymorphic container)
// ─────────────────────────────────────────────────────────────────────────────

/// Polymorphic section container stored in Hive.
/// data field holds JSON-encoded section-specific content.
/// Rule §11: Sections are fixed-order. No drag-to-reorder.
///           Users reorder content within sections via cut/copy/paste.
@HiveType(typeId: AppConstants.resumeSectionTypeId)
class ResumeSection extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String resumeId;

  @HiveField(2)
  SectionTypeEnum type;

  /// JSON-encoded section content. Decoded into the appropriate typed model
  /// (ContactInfo, List<ExperienceEntry>, etc.) at the service layer.
  @HiveField(3)
  String data;

  /// True if any field in this section was prefilled by Claude and has not
  /// yet been edited by the user. Drives the AI indicator badge on section
  /// tabs in the wizard and section editors.
  /// Rule §4: prefilled fields are never locked — this flag clears on edit.
  @HiveField(4)
  bool hasUnreviewedAIContent;

  ResumeSection({
    required this.id,
    required this.resumeId,
    required this.type,
    required this.data,
    this.hasUnreviewedAIContent = false,
  });

  Map<String, dynamic> toBackupJson() => {
        'id': id,
        'resumeId': resumeId,
        'type': type.name,
        'data': data,
        'hasUnreviewedAIContent': hasUnreviewedAIContent,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// ContactInfo
// ─────────────────────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.contactInfoTypeId)
class ContactInfo extends HiveObject {
  @HiveField(0)
  String firstName;

  @HiveField(1)
  String lastName;

  /// Displayed beneath the name on the resume (e.g. 'Network Systems Engineer').
  @HiveField(2)
  String professionalTitle;

  /// Stored separately, displayed as 'City, State'.
  @HiveField(3)
  String city;

  @HiveField(4)
  String state;

  @HiveField(5)
  String phone;

  @HiveField(6)
  String email;

  @HiveField(7)
  String? linkedInUrl;

  @HiveField(8)
  String? websiteUrl;

  @HiveField(9)
  String? gitHubUrl;

  ContactInfo({
    this.firstName = '',
    this.lastName = '',
    this.professionalTitle = '',
    this.city = '',
    this.state = '',
    this.phone = '',
    this.email = '',
    this.linkedInUrl,
    this.websiteUrl,
    this.gitHubUrl,
  });

  String get fullName => '$firstName $lastName'.trim();
  String get cityState =>
      '$city, $state'.trim().replaceAll(RegExp(r'^,\s*|,\s*$'), '');

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'lastName': lastName,
        'professionalTitle': professionalTitle,
        'city': city,
        'state': state,
        'phone': phone,
        'email': email,
        'linkedInUrl': linkedInUrl,
        'websiteUrl': websiteUrl,
        'gitHubUrl': gitHubUrl,
      };

  factory ContactInfo.fromJson(Map<String, dynamic> json) => ContactInfo(
        firstName: json['firstName'] as String? ?? '',
        lastName: json['lastName'] as String? ?? '',
        professionalTitle: json['professionalTitle'] as String? ?? '',
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        email: json['email'] as String? ?? '',
        linkedInUrl: json['linkedInUrl'] as String?,
        websiteUrl: json['websiteUrl'] as String?,
        gitHubUrl: json['gitHubUrl'] as String?,
      );

  ContactInfo copyWith({
    String? firstName,
    String? lastName,
    String? professionalTitle,
    String? city,
    String? state,
    String? phone,
    String? email,
    String? linkedInUrl,
    String? websiteUrl,
    String? gitHubUrl,
  }) =>
      ContactInfo(
        firstName: firstName ?? this.firstName,
        lastName: lastName ?? this.lastName,
        professionalTitle: professionalTitle ?? this.professionalTitle,
        city: city ?? this.city,
        state: state ?? this.state,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        linkedInUrl: linkedInUrl ?? this.linkedInUrl,
        websiteUrl: websiteUrl ?? this.websiteUrl,
        gitHubUrl: gitHubUrl ?? this.gitHubUrl,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SkillEntry
// ─────────────────────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.skillEntryTypeId)
class SkillEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  /// Optional category for grouped PDF rendering.
  /// Underlying data is always a flat ordered list — category is a display layer.
  @HiveField(2)
  SkillCategoryEnum category;

  /// True if this skill was added by Claude extraction.
  /// Rule §4: cleared when user edits the field — never locked.
  @HiveField(3)
  bool isAIPrefilled;

  SkillEntry({
    required this.id,
    required this.name,
    this.category = SkillCategoryEnum.uncategorized,
    this.isAIPrefilled = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category.name,
        'isAIPrefilled': isAIPrefilled,
      };

  factory SkillEntry.fromJson(Map<String, dynamic> json) => SkillEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        category: SkillCategoryEnum.values.firstWhere(
          (e) => e.name == json['category'],
          orElse: () => SkillCategoryEnum.uncategorized,
        ),
        isAIPrefilled: json['isAIPrefilled'] as bool? ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ExperienceEntry
// ─────────────────────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.experienceEntryTypeId)
class ExperienceEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String title;

  @HiveField(2)
  String company;

  @HiveField(3)
  String location;

  @HiveField(4)
  String startDate;

  @HiveField(5)
  String? endDate;

  /// True if this is the user's current role.
  @HiveField(6)
  bool isCurrent;

  /// Achievement bullets. One achievement per item (STAR method).
  /// Rule §11: Users reorder via cut/copy/paste — no drag-to-reorder.
  @HiveField(7)
  List<String> bullets;

  /// True if this entry was created by Claude extraction.
  /// Rule §4: cleared when user edits any field in this entry.
  @HiveField(8)
  bool isAIPrefilled;

  ExperienceEntry({
    required this.id,
    this.title = '',
    this.company = '',
    this.location = '',
    this.startDate = '',
    this.endDate,
    this.isCurrent = false,
    List<String>? bullets,
    this.isAIPrefilled = false,
  }) : bullets = bullets ?? [];

  String get dateRange {
    final end = isCurrent ? 'Present' : (endDate ?? '');
    return '$startDate – $end'.trim();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'company': company,
        'location': location,
        'startDate': startDate,
        'endDate': endDate,
        'isCurrent': isCurrent,
        'bullets': bullets,
        'isAIPrefilled': isAIPrefilled,
      };

  factory ExperienceEntry.fromJson(Map<String, dynamic> json) =>
      ExperienceEntry(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        company: json['company'] as String? ?? '',
        location: json['location'] as String? ?? '',
        startDate: _s(json['startDate']) ?? '',
        endDate: _s(json['endDate']),
        isCurrent: json['isCurrent'] as bool? ?? false,
        bullets: (json['bullets'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        isAIPrefilled: json['isAIPrefilled'] as bool? ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EducationEntry
// ─────────────────────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.educationEntryTypeId)
class EducationEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String degree;

  @HiveField(2)
  String institution;

  @HiveField(3)
  String fieldOfStudy;

  @HiveField(4)
  String graduationYear;

  /// Optional — shown only if 3.5 or above per resume writing guidelines.
  @HiveField(5)
  String? gpa;

  /// True if this entry was created by Claude extraction.
  @HiveField(6)
  bool isAIPrefilled;

  /// Optional academic distinction (e.g. Summa Cum Laude, Magna Cum Laude).
  @HiveField(7)
  String? honors;

  EducationEntry({
    required this.id,
    this.degree = '',
    this.institution = '',
    this.fieldOfStudy = '',
    this.graduationYear = '',
    this.gpa,
    this.isAIPrefilled = false,
    this.honors,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'degree': degree,
        'institution': institution,
        'fieldOfStudy': fieldOfStudy,
        'graduationYear': graduationYear,
        'gpa': gpa,
        'isAIPrefilled': isAIPrefilled,
        'honors': honors,
      };

  factory EducationEntry.fromJson(Map<String, dynamic> json) => EducationEntry(
        id: json['id'] as String,
        degree: json['degree'] as String? ?? '',
        institution: json['institution'] as String? ?? '',
        fieldOfStudy: json['fieldOfStudy'] as String? ?? '',
        graduationYear: _s(json['graduationYear']) ?? '',
        gpa: _s(json['gpa']),
        isAIPrefilled: json['isAIPrefilled'] as bool? ?? false,
        honors: _s(json['honors']),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CertificationEntry
// ─────────────────────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.certificationEntryTypeId)
class CertificationEntry extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String issuer;

  @HiveField(3)
  String dateEarned;

  @HiveField(4)
  String? expiresDate;

  @HiveField(5)
  String? credentialId;

  /// True if this entry was created by Claude extraction.
  @HiveField(6)
  bool isAIPrefilled;

  /// True if this cert was flagged by the retroactive sanitization migration
  /// (ResumeMigrationService) as *possibly* generic compliance/administrative
  /// training rather than a real credential, using the same fallback keyword
  /// heuristic used elsewhere when no model classification is available.
  /// The migration never deletes a cert on this basis — it only sets this
  /// flag, which the resume editor surfaces as a pending-decision card so
  /// the user (not a background job) makes the final call.
  @HiveField(7, defaultValue: false)
  bool needsComplianceReview;

  /// Plain-language reason shown on the pending-decision card when
  /// [needsComplianceReview] is true.
  @HiveField(8, defaultValue: null)
  String? complianceReviewReason;

  CertificationEntry({
    required this.id,
    this.name = '',
    this.issuer = '',
    this.dateEarned = '',
    this.expiresDate,
    this.credentialId,
    this.isAIPrefilled = false,
    this.needsComplianceReview = false,
    this.complianceReviewReason,
  });

  bool get isExpired {
    if (expiresDate == null || expiresDate!.isEmpty) return false;
    try {
      // Basic year comparison — extend with full date parsing if needed
      final expYear = int.tryParse(expiresDate!.split('/').last.trim());
      if (expYear == null) return false;
      return expYear < DateTime.now().year;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'issuer': issuer,
        'dateEarned': dateEarned,
        'expiresDate': expiresDate,
        'credentialId': credentialId,
        'isAIPrefilled': isAIPrefilled,
        'needsComplianceReview': needsComplianceReview,
        'complianceReviewReason': complianceReviewReason,
      };

  factory CertificationEntry.fromJson(Map<String, dynamic> json) =>
      CertificationEntry(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        issuer: json['issuer'] as String? ?? '',
        dateEarned: _s(json['dateEarned']) ?? '',
        expiresDate: _s(json['expiresDate']),
        credentialId: json['credentialId'] as String?,
        isAIPrefilled: json['isAIPrefilled'] as bool? ?? false,
        needsComplianceReview: json['needsComplianceReview'] as bool? ?? false,
        complianceReviewReason: json['complianceReviewReason'] as String?,
      );
}
