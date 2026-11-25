# BeaconAI Resume — Ad Brief

## App name
**BeaconAI Resume** — the same on Google Play, the App Store (both checked 2026-11-24), the in-app name, and (from the next release) the Android launcher label and iOS home-screen name.

App icon: `icon.png` (1024×1024, from `ios/Runner/Assets.xcassets/AppIcon.appiconset/icon-ios-1024x1024.png`, the same artwork as the Android launcher icon). It shows a parchment scroll with a navy quill.

## One-line pitch
Tailor your resume to every job, in minutes.

## Who it's for
Job seekers applying online who need resumes that get past applicant tracking systems (ATS). That includes career changers and veterans (there's a Veteran / Military-to-Civilian template) and people sending lots of applications who want a version tuned to each posting.

## 3 strongest features
1. **Tailor to any job.** Paste a job posting and AI rewrites your resume for that role. It reorders bullets, brings the right keywords to the surface, and saves it as a separate tailored resume next to your master. *(Basic and Pro)*
2. **12 professional templates, all free.** The same content restyles with one tap. Every export is clean single-column text that ATS software can read, whatever the template looks like.
3. **Start from what you have.** Upload an old resume as a PDF, Word file, photo or plain text and AI fills in your experience. Or build from scratch with guided steps and tips such as STAR-method coaching on bullets.

Also: an ATS keyword scanner (match score plus missing keywords), AI cover letters, and interview prep.

## Free vs. paid (checked against the code)
Prices come from the app stores through RevenueCat and are not in the code, so no prices are quoted here.

| | Free | Basic | Pro |
|---|---|---|---|
| Resume builder + all 12 templates | ✓ | ✓ | ✓ |
| Upload existing documents (AI extraction) | 4 docs, max 8 pages each | 10 docs, max 50 pages each | Unlimited |
| PDF export | ✓ | ✓ | ✓ |
| Word (.docx) export | — | ✓ | ✓ |
| Plain text export | — | — | ✓ |
| Tailored resumes | — | 2 per month | Unlimited |
| ATS Keyword Scanner | — (opens paywall) | ✓ | ✓ |
| AI cover letters | — | — | ✓ |
| AI bullet suggestions | — | — | ✓ |
| Interview prep | Static tips guide | Role-specific | Personalized study guide + export |
| Ads | Interstitial ads (in the resume builder) | No ads | No ads |

**One-time add-on (any tier):** "Cover Letter + Tailored Resume" gives one AI cover letter and one tailored resume, saved permanently on the device.
Basic and Pro come as monthly or annual subscriptions.

**Claims to avoid:** "unlimited free AI", "free cover letters", "free ATS scan", or a guaranteed interview. The in-app ATS tip itself says the score is "a signal… not a guarantee of an interview."

## Brand colors (from `lib/theme/app_colors.dart`)
| Role | Hex |
|---|---|
| Primary accent (buttons, links) — navy | `#2C4A7C` |
| Primary text — deep navy-charcoal | `#1A1A2E` |
| Background — warm off-white | `#FAFAF8` |
| Surface / cards | `#FFFFFF` |
| Accent tint (selected states) | `#EEF2FF` |
| Success / ATS "good" green | `#16A34A` |
| AI indicator purple (used only for AI content) | `#7C3AED` |
| Secondary text gray | `#6B7280` |
| Dark mode background / accent | `#111118` / `#4F7AC7` |

## Fonts
- **Playfair Display**: headings and the BeaconAI wordmark (serif)
- **Inter**: body and UI text
- **JetBrains Mono**: small data labels (e.g., "ATS Score: 94 / 100", timestamps)

## Store links
- Google Play: https://play.google.com/store/apps/details?id=dev.getbeaconai.beaconai_resume
- App Store: https://apps.apple.com/app/id6782361658
- Website: https://getbeaconai.com · Privacy policy: https://getbeaconai.com/privacy

## Screenshots (1080×1920, 9:16 portrait)
| File | What it shows |
|---|---|
| `01_welcome.png` | First screen a new user sees: "BeaconAI Resume — Build an ATS-optimized resume that gets past the filters." |
| `02_tailor-to-any-job.png` | Onboarding: "Tailor it to any job in minutes," with an ATS Score 94/100 badge. |
| `03_12-free-templates.png` | Template picker: "All 12 templates are free — switch any time without losing your content." |
| `04_dashboard.png` | Home screen in use: master resume scoring 96, tailored resumes, ATS Scanner, Pro active. |
| `05_finished-resume.png` | The payoff: a finished resume in the bold navy Horizon template. |
| `06_tailored-resumes.png` | One resume per job: two tailored resumes plus a cover letter, each scoring 96. |
| `07_tailored-resume-preview.png` | Resume tailored for a Senior Platform Engineer role, in the Technical template. |
| `08_cover-letter.png` | AI cover letter written from the resume for a specific job. |
| `extras/upload-anything.png` | Onboarding: upload a PDF, Word file, image or plain text and AI pulls out your experience. |
| `extras/templates-with-your-resume.png` | Your own resume previewed in Academic, Veteran, Technical, Horizon, Sidebar and Pillar. |
| `extras/export-formats.png` | Export options: PDF, Word (.docx) and plain text. |

## Clips (MP4, H.264, 1080×1920, 30 fps)
| File | Length | What it shows |
|---|---|---|
| `clip01_onboarding-to-templates.mp4` | 12.9 s | Swipes through the 3 onboarding pages, then picks a template from the grid of 12. |
| `clip02_one-tap-restyle.mp4` | 12.4 s | From a finished resume, opens Templates, scrolls, picks Horizon, and the resume restyles instantly. |
| `clip03_tailored-resume-tour.mp4` | 12.9 s | Dashboard → opens a job-tailored resume → switches to Edit → opens Experience with STAR-method coaching. |
| `clip04_cover-letter.mp4` | 10.8 s | Opens a cover letter tailored to the job and scrolls through it. |

## How these were captured (for the record)
- Device: Android 15 emulator (Pixel-class, 420 dpi), display set to 1080×1920 so stills and clips match the 9:16 ad frame exactly. Demo-mode status bar shows 9:41, full battery and full wifi, with no notifications.
- Build: the app's own code, compiled as a profile (AOT) build for smooth animation. A debug build recorded at about 10–15 fps on the emulator.
- Clips were recorded with the emulator's host-side recorder at 30 fps. `adb shell screenrecord` on this emulator captured only about 12 fps during motion. They were cropped to 1080×1920 and the emulator skin's camera-dot overlay was removed. The clips are high-bitrate (about 30–60 MB each), so re-encode for upload if needed.
- **Sample data only.** The persona is the app's built-in fictional "Marcus Chen" sample (555 phone number, placeholder email). Companies (Cascadia Cloud, Ridgeway Health, Fernwood Technologies, etc.) are made up.
- **Honesty note:** the tailored-resume and cover-letter text in the shots is hand-written sample content loaded into the app's real screens. It is not live AI output, because the AI backend returned errors during capture. The screens and features are real, and the wording is illustrative.
- Seed entrypoint used: `marketing/seed/marketing_main.dart` (not part of the shipped app). It pins the Pro tier in memory and never starts AdMob, so no ads appear.
