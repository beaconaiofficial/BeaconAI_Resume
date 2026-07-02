import 'package:hive_ce/hive.dart';
import '../constants/app_constants.dart';
import 'app_enums.dart';

part 'supporting_models.g.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SourceDocument
// ─────────────────────────────────────────────────────────────────────────────

/// Represents an uploaded source document (PDF, DOCX, TXT, or image).
/// Rule §12: Actual file bytes are NEVER stored permanently.
///           Only rawExtractedText (Claude's output) and metadata are stored.
///           This keeps local storage lean.
@HiveType(typeId: AppConstants.sourceDocumentTypeId)
class SourceDocument extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String resumeId;

  @HiveField(2)
  String fileName;

  @HiveField(3)
  FileTypeEnum fileType;

  /// Role determines how this document is used in the app flow.
  /// documentRole == jobPosting drives the tailored resume creation flow.
  @HiveField(4)
  DocumentRoleEnum documentRole;

  @HiveField(5)
  DateTime uploadedAt;

  @HiveField(6)
  ExtractionStatusEnum extractionStatus;

  /// Claude's parsed output — stored locally.
  /// File bytes are discarded after extraction.
  @HiveField(7)
  String rawExtractedText;

  /// Which resume fields were populated from this document.
  @HiveField(8)
  List<String> appliedFields;

  SourceDocument({
    required this.id,
    required this.resumeId,
    required this.fileName,
    required this.fileType,
    required this.documentRole,
    required this.uploadedAt,
    this.extractionStatus = ExtractionStatusEnum.pending,
    this.rawExtractedText = '',
    List<String>? appliedFields,
  }) : appliedFields = appliedFields ?? [];

  Map<String, dynamic> toBackupJson() => {
        'id': id,
        'resumeId': resumeId,
        'fileName': fileName,
        'fileType': fileType.name,
        'documentRole': documentRole.name,
        'uploadedAt': uploadedAt.toIso8601String(),
        'extractionStatus': extractionStatus.name,
        'rawExtractedText': rawExtractedText,
        'appliedFields': appliedFields,
      };

  factory SourceDocument.fromBackupJson(Map<String, dynamic> json) =>
      SourceDocument(
        id: json['id'] as String,
        resumeId: json['resumeId'] as String,
        fileName: json['fileName'] as String,
        fileType:
            FileTypeEnum.values.firstWhere((e) => e.name == json['fileType']),
        documentRole: DocumentRoleEnum.values
            .firstWhere((e) => e.name == json['documentRole']),
        uploadedAt: DateTime.parse(json['uploadedAt'] as String),
        extractionStatus: ExtractionStatusEnum.values.firstWhere(
            (e) => e.name == json['extractionStatus'],
            orElse: () => ExtractionStatusEnum.complete),
        rawExtractedText: json['rawExtractedText'] as String? ?? '',
        appliedFields: (json['appliedFields'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// FieldMappingSuggestion  (ephemeral — NEVER persisted to Hive)
// ─────────────────────────────────────────────────────────────────────────────

/// Ephemeral model used during the field mapping confirmation screen.
/// Claude's suggested field mappings are shown to the user all at once.
/// Rule §3: User always reviews and confirms — no auto-apply.
/// This class is intentionally NOT a HiveObject.
class FieldMappingSuggestion {
  /// Dot-notation field path, e.g. 'experience[0].title', 'contact.email'
  final String field;

  /// Claude's suggested value for this field.
  final String suggestedValue;

  /// Confidence score (0.0–1.0) used to order suggestions in the UI.
  final double confidence;

  /// Whether the user has accepted this suggestion.
  bool accepted;

  FieldMappingSuggestion({
    required this.field,
    required this.suggestedValue,
    required this.confidence,
    this.accepted = true, // default to accepted so 'Apply All' works
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// PendingEntryDecision  (ephemeral — NEVER persisted to Hive)
// ─────────────────────────────────────────────────────────────────────────────

/// The shapes of ambiguity the extraction/tailoring model can flag: "is this
/// a job or training?", "is this cert real or clutter?", or "is this a
/// degree or non-degree training?".
enum PendingDecisionKind {
  employmentVsTraining,
  credentialVsCompliance,
  degreeVsNonDegreeTraining,
}

/// The bucket the user routes an uncertain entry into. `education` is
/// distinct from `employment` — they route to different list fields, so
/// resolution code must not have to also inspect [PendingDecisionKind] just
/// to know which list an accepted decision belongs in.
enum EntryDecision { employment, education, certification, exclude }

/// Surfaced on the document-upload / wizard Path A confirmation screen when
/// the extraction model could not confidently classify an entry as
/// employment vs. training, or as a real credential vs. compliance clutter.
/// Never silently guessed — the user resolves it explicitly.
/// This class is intentionally NOT a HiveObject.
class PendingEntryDecision {
  PendingEntryDecision({
    required this.id,
    required this.rawTitle,
    required this.rawCompany,
    required this.rawBullets,
    required this.uncertaintyReason,
    required this.kind,
    required this.rawEntry,
    this.resolution,
  });

  /// Stable id for keying the card in the UI and for removal once resolved.
  final String id;

  final String rawTitle;
  final String rawCompany;
  final List<String> rawBullets;

  /// Plain-language reason the model gave for its uncertainty.
  final String uncertaintyReason;

  final PendingDecisionKind kind;

  /// The original extracted map (experience- or certification-shaped)
  /// so the resolved entry can be routed without re-extracting anything.
  final Map<String, dynamic> rawEntry;

  /// Null until the user resolves the card. Skipping a card without an
  /// explicit choice must resolve to [EntryDecision.exclude] — never a
  /// silent default to inclusion.
  EntryDecision? resolution;
}

// ─────────────────────────────────────────────────────────────────────────────
// CoverLetter
// ─────────────────────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.coverLetterTypeId)
class CoverLetter extends HiveObject {
  @HiveField(0)
  String id;

  /// Links this cover letter to a specific resume.
  @HiveField(1)
  String resumeId;

  /// The job description this cover letter was generated for.
  @HiveField(2)
  String jobDescription;

  /// The full cover letter body (editable after AI generation).
  @HiveField(3)
  String content;

  @HiveField(4)
  DateTime createdAt;

  @HiveField(5)
  DateTime updatedAt;

  CoverLetter({
    required this.id,
    required this.resumeId,
    required this.jobDescription,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  void touch() {
    updatedAt = DateTime.now();
    save();
  }

  Map<String, dynamic> toBackupJson() => {
        'id': id,
        'resumeId': resumeId,
        'jobDescription': jobDescription,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CoverLetter.fromBackupJson(Map<String, dynamic> json) => CoverLetter(
        id: json['id'] as String,
        resumeId: json['resumeId'] as String,
        jobDescription: json['jobDescription'] as String,
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// InterviewStudyGuide
// ─────────────────────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.interviewStudyGuideTypeId)
class InterviewStudyGuide extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  String resumeId;

  /// Auto-detected from the parsed job posting.
  @HiveField(2)
  String companyName;

  @HiveField(3)
  String roleTitle;

  @HiveField(4)
  DateTime generatedAt;

  @HiveField(5)
  List<InterviewQuestion> questions;

  /// Null until the user exports the guide as a PDF.
  @HiveField(6)
  DateTime? exportedAt;

  InterviewStudyGuide({
    required this.id,
    required this.resumeId,
    required this.companyName,
    required this.roleTitle,
    required this.generatedAt,
    List<InterviewQuestion>? questions,
    this.exportedAt,
  }) : questions = questions ?? [];

  Map<String, dynamic> toBackupJson() => {
        'id': id,
        'resumeId': resumeId,
        'companyName': companyName,
        'roleTitle': roleTitle,
        'generatedAt': generatedAt.toIso8601String(),
        'questions': questions.map((q) => q.toJson()).toList(),
        'exportedAt': exportedAt?.toIso8601String(),
      };

  factory InterviewStudyGuide.fromBackupJson(Map<String, dynamic> json) =>
      InterviewStudyGuide(
        id: json['id'] as String,
        resumeId: json['resumeId'] as String,
        companyName: json['companyName'] as String,
        roleTitle: json['roleTitle'] as String,
        generatedAt: DateTime.parse(json['generatedAt'] as String),
        questions: (json['questions'] as List<dynamic>?)
                ?.map((q) =>
                    InterviewQuestion.fromJson(q as Map<String, dynamic>))
                .toList() ??
            [],
        exportedAt: json['exportedAt'] != null
            ? DateTime.parse(json['exportedAt'] as String)
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// InterviewQuestion
// ─────────────────────────────────────────────────────────────────────────────

@HiveType(typeId: AppConstants.interviewQuestionTypeId)
class InterviewQuestion extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  QuestionCategoryEnum category;

  @HiveField(2)
  String questionText;

  /// Personalized talking points drawn from the user's resume (Pro tier).
  @HiveField(3)
  String answerGuide;

  /// UI-only expand/collapse state — not persisted between sessions.
  /// Initialized to false on load.
  bool isExpanded;

  InterviewQuestion({
    required this.id,
    required this.category,
    required this.questionText,
    required this.answerGuide,
    this.isExpanded = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.name,
        'questionText': questionText,
        'answerGuide': answerGuide,
        // isExpanded intentionally excluded — UI state only
      };

  factory InterviewQuestion.fromJson(Map<String, dynamic> json) =>
      InterviewQuestion(
        id: json['id'] as String,
        category: QuestionCategoryEnum.values
            .firstWhere((e) => e.name == json['category']),
        questionText: json['questionText'] as String,
        answerGuide: json['answerGuide'] as String,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// AddOnPurchase
// ─────────────────────────────────────────────────────────────────────────────

/// Tracks $0.99 consumable IAP purchases.
/// RevenueCat handles restore across reinstalls automatically.
@HiveType(typeId: AppConstants.addOnPurchaseTypeId)
class AddOnPurchase extends HiveObject {
  @HiveField(0)
  String id;

  @HiveField(1)
  DateTime purchasedAt;

  @HiveField(2)
  AddOnTypeEnum type;

  /// Linked once the tailored resume is created with this add-on.
  @HiveField(3)
  String? resumeId;

  /// False until the user creates the resume + cover letter with this purchase.
  /// Once used = true, the add-on is consumed.
  @HiveField(4)
  bool used;

  AddOnPurchase({
    required this.id,
    required this.purchasedAt,
    required this.type,
    this.resumeId,
    this.used = false,
  });

  Map<String, dynamic> toBackupJson() => {
        'id': id,
        'purchasedAt': purchasedAt.toIso8601String(),
        'type': type.name,
        'resumeId': resumeId,
        'used': used,
      };

  factory AddOnPurchase.fromBackupJson(Map<String, dynamic> json) =>
      AddOnPurchase(
        id: json['id'] as String,
        purchasedAt: DateTime.parse(json['purchasedAt'] as String),
        type: AddOnTypeEnum.values.firstWhere((e) => e.name == json['type']),
        resumeId: json['resumeId'] as String?,
        used: json['used'] as bool? ?? false,
      );
}
