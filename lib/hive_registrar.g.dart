import 'package:hive_ce/hive.dart';
import 'package:beaconai_resume/models/app_enums.dart';
import 'package:beaconai_resume/models/resume.dart';
import 'package:beaconai_resume/models/resume_sections.dart';
import 'package:beaconai_resume/models/supporting_models.dart';
import 'package:beaconai_resume/models/user_settings.dart';

extension HiveRegistrar on HiveInterface {
  void registerAdapters() {
    registerAdapter(TierEnumAdapter());
    registerAdapter(FileTypeEnumAdapter());
    registerAdapter(DocumentRoleEnumAdapter());
    registerAdapter(ExtractionStatusEnumAdapter());
    registerAdapter(SectionTypeEnumAdapter());
    registerAdapter(SkillCategoryEnumAdapter());
    registerAdapter(QuestionCategoryEnumAdapter());
    registerAdapter(AddOnTypeEnumAdapter());
    registerAdapter(ExportFormatEnumAdapter());
    registerAdapter(AppThemeEnumAdapter());
    registerAdapter(ResumeAdapter());
    registerAdapter(ResumeSectionAdapter());
    registerAdapter(ContactInfoAdapter());
    registerAdapter(SkillEntryAdapter());
    registerAdapter(ExperienceEntryAdapter());
    registerAdapter(EducationEntryAdapter());
    registerAdapter(CertificationEntryAdapter());
    registerAdapter(SourceDocumentAdapter());
    registerAdapter(CoverLetterAdapter());
    registerAdapter(InterviewStudyGuideAdapter());
    registerAdapter(InterviewQuestionAdapter());
    registerAdapter(AddOnPurchaseAdapter());
    registerAdapter(UserSettingsAdapter());
  }
}
