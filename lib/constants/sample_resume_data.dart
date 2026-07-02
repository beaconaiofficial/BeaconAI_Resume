import '../models/app_enums.dart';
import '../models/resume_sections.dart';
import '../widgets/resume_template_renderer.dart';

// Static sample personas used in the first-time template picker.
// These are never written to Hive and never carry over into the user's resume.
class SampleResumeData {
  SampleResumeData._();

  // ── Persona A — John Carter (business/professional) ──────────────────────────
  static final ResumeRenderData johnCarter = ResumeRenderData(
    contact: ContactInfo(
      firstName: 'John',
      lastName: 'Carter',
      professionalTitle: 'Marketing Manager',
      city: 'Austin',
      state: 'TX',
      phone: '(512) 555-0142',
      email: 'john.carter@email.com',
      linkedInUrl: 'linkedin.com/in/johncarter',
    ),
    summary: 'Results-driven marketing manager with 8 years of experience '
        'leading demand generation and brand strategy for B2B software companies. '
        'Proven track record growing pipeline by 120% and reducing customer '
        'acquisition cost by 30%.',
    experience: [
      ExperienceEntry(
        id: 'jc_e1',
        title: 'Senior Marketing Manager',
        company: 'Brightline Software',
        location: 'Austin, TX',
        startDate: 'Mar 2021',
        endDate: 'Present',
        isCurrent: true,
        bullets: [
          'Led demand generation strategy growing qualified pipeline by 120% '
              'over 18 months',
          r'Managed $1.2M annual paid media budget across Google Ads, LinkedIn, '
              'and programmatic channels',
          'Built and scaled marketing team from 2 to 8 contributors',
        ],
      ),
      ExperienceEntry(
        id: 'jc_e2',
        title: 'Marketing Manager',
        company: 'Vector Analytics',
        location: 'Dallas, TX',
        startDate: 'Jun 2018',
        endDate: 'Mar 2021',
        isCurrent: false,
        bullets: [
          'Owned email lifecycle marketing for 50,000-contact database, '
              'improving open rates from 18% to 31%',
          'Reduced customer acquisition cost by 30% through landing page '
              'testing and audience refinement',
        ],
      ),
    ],
    education: [
      EducationEntry(
        id: 'jc_edu1',
        degree: 'Bachelor of Arts',
        institution: 'University of Texas at Austin',
        fieldOfStudy: 'Communications',
        graduationYear: '2016',
        gpa: '3.6',
      ),
    ],
    skills: [
      SkillEntry(
          id: 'jc_s1',
          name: 'HubSpot',
          category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'jc_s2',
          name: 'Salesforce',
          category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'jc_s3',
          name: 'Google Ads',
          category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(
          id: 'jc_s4', name: 'SQL', category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'jc_s5',
          name: 'A/B Testing',
          category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'jc_s6',
          name: 'Team Leadership',
          category: SkillCategoryEnum.softSkill),
      SkillEntry(
          id: 'jc_s7',
          name: 'Strategic Planning',
          category: SkillCategoryEnum.softSkill),
      SkillEntry(
          id: 'jc_s8',
          name: 'Google Analytics',
          category: SkillCategoryEnum.toolsSoftware),
    ],
    certifications: [
      CertificationEntry(
        id: 'jc_c1',
        name: 'HubSpot Inbound Marketing',
        issuer: 'HubSpot Academy',
        dateEarned: 'Jan 2022',
      ),
      CertificationEntry(
        id: 'jc_c2',
        name: 'Google Ads Search Certification',
        issuer: 'Google',
        dateEarned: 'Mar 2023',
      ),
    ],
  );

  // ── Persona B — Jane Rivera (technical/IT) ────────────────────────────────────
  static final ResumeRenderData janeRivera = ResumeRenderData(
    contact: ContactInfo(
      firstName: 'Jane',
      lastName: 'Rivera',
      professionalTitle: 'Network Systems Engineer',
      city: 'Denver',
      state: 'CO',
      phone: '(720) 555-0198',
      email: 'jane.rivera@email.com',
      linkedInUrl: 'linkedin.com/in/janerivera',
      gitHubUrl: 'github.com/janerivera',
    ),
    summary: 'Network systems engineer with 6 years of experience designing '
        'and maintaining enterprise network infrastructure. Specializes in '
        'IP-based nodal systems, cybersecurity frameworks, and network '
        'operations center management.',
    experience: [
      ExperienceEntry(
        id: 'jr_e1',
        title: 'Senior Network Systems Engineer',
        company: 'Apex Defense Solutions',
        location: 'Denver, CO',
        startDate: 'Jan 2022',
        endDate: 'Present',
        isCurrent: true,
        bullets: [
          'Designed and deployed IP-based nodal network infrastructure '
              'supporting 500+ endpoints',
          'Reduced network downtime by 45% through implementation of automated '
              'monitoring systems',
          'Led team of 6 engineers across network operations and cybersecurity '
              'functions',
        ],
      ),
      ExperienceEntry(
        id: 'jr_e2',
        title: 'Network Administrator',
        company: 'Frontier Communications',
        location: 'Colorado Springs, CO',
        startDate: 'Aug 2019',
        endDate: 'Jan 2022',
        isCurrent: false,
        bullets: [
          'Administered Cisco enterprise network across 12 locations serving '
              '2,000+ users',
          'Implemented COMSEC protocols reducing security incidents by 60%',
        ],
      ),
    ],
    education: [
      EducationEntry(
        id: 'jr_edu1',
        degree: 'Bachelor of Science',
        institution: 'Colorado State University',
        fieldOfStudy: 'Information Technology',
        graduationYear: '2019',
        gpa: '3.7',
      ),
    ],
    skills: [
      SkillEntry(
          id: 'jr_s1',
          name: 'Network Administration',
          category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'jr_s2',
          name: 'Cisco Systems',
          category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(
          id: 'jr_s3',
          name: 'Cybersecurity',
          category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'jr_s4',
          name: 'ISYSCON/JNMS',
          category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(
          id: 'jr_s5',
          name: 'Python',
          category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'jr_s6',
          name: 'Server Administration',
          category: SkillCategoryEnum.technical),
      SkillEntry(
          id: 'jr_s7',
          name: 'Problem Solving',
          category: SkillCategoryEnum.softSkill),
      SkillEntry(
          id: 'jr_s8',
          name: 'Team Leadership',
          category: SkillCategoryEnum.softSkill),
    ],
    certifications: [
      CertificationEntry(
        id: 'jr_c1',
        name: 'CompTIA Security+',
        issuer: 'CompTIA',
        dateEarned: 'Jun 2021',
      ),
      CertificationEntry(
        id: 'jr_c2',
        name: 'Cisco CCNA',
        issuer: 'Cisco',
        dateEarned: 'Sep 2020',
      ),
    ],
  );

  // ── Persona C — Marcus Chen (software/IT, civilian) ───────────────────────────
  static final ResumeRenderData marcusChen = ResumeRenderData(
    contact: ContactInfo(
      firstName: 'Marcus',
      lastName: 'Chen',
      professionalTitle: 'Backend Software Engineer',
      city: 'Seattle',
      state: 'WA',
      phone: '(206) 555-0173',
      email: 'marcus.chen@email.com',
      linkedInUrl: 'linkedin.com/in/marcuschen',
      gitHubUrl: 'github.com/marcuschen',
    ),
    summary: 'Backend software engineer with 5 years of experience building '
        'and scaling distributed systems for high-traffic web applications. '
        'Specializes in API design, cloud infrastructure, and database '
        'performance optimization.',
    experience: [
      ExperienceEntry(
        id: 'mc_e1',
        title: 'Senior Backend Engineer',
        company: 'Fernwood Technologies',
        location: 'Seattle, WA',
        startDate: 'Feb 2022',
        endDate: 'Present',
        isCurrent: true,
        bullets: [
          'Designed and built a microservices architecture handling 2M+ '
              'requests per day, reducing average latency by 35%',
          'Led migration of a monolithic billing system to AWS, cutting '
              r'infrastructure costs by $180K annually',
          'Mentored 3 junior engineers and led weekly code review sessions',
        ],
      ),
      ExperienceEntry(
        id: 'mc_e2',
        title: 'Software Engineer',
        company: 'Northline Data',
        location: 'Portland, OR',
        startDate: 'Jul 2019',
        endDate: 'Feb 2022',
        isCurrent: false,
        bullets: [
          'Built RESTful APIs consumed by 3 internal product teams, '
              'improving cross-team release velocity by 20%',
          'Optimized PostgreSQL queries reducing average page load time '
              'from 2.1s to 400ms',
        ],
      ),
    ],
    education: [
      EducationEntry(
        id: 'mc_edu1',
        degree: 'Bachelor of Science',
        institution: 'University of Washington',
        fieldOfStudy: 'Computer Science',
        graduationYear: '2019',
        gpa: '3.8',
      ),
    ],
    skills: [
      SkillEntry(id: 'mc_s1', name: 'Python', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'mc_s2', name: 'AWS', category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(id: 'mc_s3', name: 'Docker', category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(id: 'mc_s4', name: 'PostgreSQL', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'mc_s5', name: 'System Design', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'mc_s6', name: 'CI/CD', category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(id: 'mc_s7', name: 'Mentorship', category: SkillCategoryEnum.softSkill),
      SkillEntry(id: 'mc_s8', name: 'Cross-team Collaboration', category: SkillCategoryEnum.softSkill),
    ],
    certifications: [
      CertificationEntry(
        id: 'mc_c1',
        name: 'AWS Certified Solutions Architect – Associate',
        issuer: 'Amazon Web Services',
        dateEarned: 'Nov 2022',
      ),
    ],
  );

  // ── Persona D — Elena Vasquez (corporate/finance/consulting) ──────────────────
  static final ResumeRenderData elenaVasquez = ResumeRenderData(
    contact: ContactInfo(
      firstName: 'Elena',
      lastName: 'Vasquez',
      professionalTitle: 'Senior Financial Analyst',
      city: 'Chicago',
      state: 'IL',
      phone: '(312) 555-0164',
      email: 'elena.vasquez@email.com',
      linkedInUrl: 'linkedin.com/in/elenavasquez',
    ),
    summary: 'Senior financial analyst with 7 years of experience in '
        'corporate finance, forecasting, and M&A due diligence for mid-market '
        'firms. Skilled at translating complex financial data into clear '
        'recommendations for executive leadership.',
    experience: [
      ExperienceEntry(
        id: 'ev_e1',
        title: 'Senior Financial Analyst',
        company: 'Redmark Capital Partners',
        location: 'Chicago, IL',
        startDate: 'Apr 2021',
        endDate: 'Present',
        isCurrent: true,
        bullets: [
          'Built financial models supporting '
              r'$40M+ in annual budgeting decisions across 4 business units',
          'Led due diligence on 6 acquisition targets, identifying '
              r'$2.3M in projected synergies',
          'Presented quarterly forecasts directly to the CFO and executive team',
        ],
      ),
      ExperienceEntry(
        id: 'ev_e2',
        title: 'Financial Analyst',
        company: 'Bishop & Cole Advisory',
        location: 'Chicago, IL',
        startDate: 'Aug 2018',
        endDate: 'Apr 2021',
        isCurrent: false,
        bullets: [
          'Prepared monthly variance reports for 12 client accounts, '
              'identifying cost-saving opportunities averaging 8% per account',
          'Automated a manual reporting process, reducing close time from 5 '
              'days to 2',
        ],
      ),
    ],
    education: [
      EducationEntry(
        id: 'ev_edu1',
        degree: 'Bachelor of Business Administration',
        institution: 'University of Illinois Urbana-Champaign',
        fieldOfStudy: 'Finance',
        graduationYear: '2018',
        gpa: '3.7',
      ),
    ],
    skills: [
      SkillEntry(id: 'ev_s1', name: 'Financial Modeling', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'ev_s2', name: 'Excel', category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(id: 'ev_s3', name: 'Forecasting', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'ev_s4', name: 'Due Diligence', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'ev_s5', name: 'Power BI', category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(id: 'ev_s6', name: 'Executive Presentations', category: SkillCategoryEnum.softSkill),
    ],
    certifications: [
      CertificationEntry(
        id: 'ev_c1',
        name: 'Chartered Financial Analyst (CFA) Level II',
        issuer: 'CFA Institute',
        dateEarned: 'Aug 2022',
      ),
    ],
  );

  // ── Persona E — Priya Nair (marketing/design-adjacent) ─────────────────────────
  static final ResumeRenderData priyaNair = ResumeRenderData(
    contact: ContactInfo(
      firstName: 'Priya',
      lastName: 'Nair',
      professionalTitle: 'Brand & Digital Marketing Lead',
      city: 'San Diego',
      state: 'CA',
      phone: '(619) 555-0187',
      email: 'priya.nair@email.com',
      linkedInUrl: 'linkedin.com/in/priyanair',
      websiteUrl: 'priyanair.design',
    ),
    summary: 'Brand and digital marketing lead with 6 years of experience '
        'shaping visual identity and campaign strategy for consumer brands. '
        'Combines design sensibility with data-driven decision making to '
        'grow engagement and brand recognition.',
    experience: [
      ExperienceEntry(
        id: 'pn_e1',
        title: 'Brand & Digital Marketing Lead',
        company: 'Coastal & Co.',
        location: 'San Diego, CA',
        startDate: 'May 2021',
        endDate: 'Present',
        isCurrent: true,
        bullets: [
          'Led rebrand and website redesign that increased organic traffic '
              'by 65% within 6 months',
          'Directed a team of 4 designers and copywriters across seasonal '
              'campaigns for a \$12M product line',
          'Grew Instagram engagement rate from 1.8% to 4.6% through a '
              'refreshed content and visual strategy',
        ],
      ),
      ExperienceEntry(
        id: 'pn_e2',
        title: 'Marketing Designer',
        company: 'Tidewater Studio',
        location: 'Los Angeles, CA',
        startDate: 'Jun 2018',
        endDate: 'May 2021',
        isCurrent: false,
        bullets: [
          'Designed campaign assets for 20+ clients spanning retail, '
              'hospitality, and consumer goods',
          'Built a reusable brand template system adopted studio-wide, '
              'cutting turnaround time by 30%',
        ],
      ),
    ],
    education: [
      EducationEntry(
        id: 'pn_edu1',
        degree: 'Bachelor of Fine Arts',
        institution: 'California College of the Arts',
        fieldOfStudy: 'Graphic Design',
        graduationYear: '2018',
      ),
    ],
    skills: [
      SkillEntry(id: 'pn_s1', name: 'Brand Strategy', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'pn_s2', name: 'Adobe Creative Suite', category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(id: 'pn_s3', name: 'Figma', category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(id: 'pn_s4', name: 'Campaign Management', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'pn_s5', name: 'Team Leadership', category: SkillCategoryEnum.softSkill),
      SkillEntry(id: 'pn_s6', name: 'Social Media Strategy', category: SkillCategoryEnum.technical),
    ],
    certifications: [
      CertificationEntry(
        id: 'pn_c1',
        name: 'Google Analytics Certification',
        issuer: 'Google',
        dateEarned: 'Feb 2023',
      ),
    ],
  );

  // ── Persona F — Owen Bennett (creative/communications/PR) ─────────────────────
  static final ResumeRenderData owenBennett = ResumeRenderData(
    contact: ContactInfo(
      firstName: 'Owen',
      lastName: 'Bennett',
      professionalTitle: 'Communications & PR Manager',
      city: 'Boston',
      state: 'MA',
      phone: '(617) 555-0129',
      email: 'owen.bennett@email.com',
      linkedInUrl: 'linkedin.com/in/owenbennett',
    ),
    summary: 'Communications and PR manager with 6 years of experience '
        'building media relationships and shaping public narrative for '
        'nonprofit and consumer organizations. Skilled storyteller with a '
        'track record of securing top-tier press coverage.',
    experience: [
      ExperienceEntry(
        id: 'ob_e1',
        title: 'Communications & PR Manager',
        company: 'Harborview Nonprofit Alliance',
        location: 'Boston, MA',
        startDate: 'Jan 2022',
        endDate: 'Present',
        isCurrent: true,
        bullets: [
          'Secured coverage in 15+ regional and national outlets for annual '
              'fundraising campaign, contributing to a 22% increase in donations',
          'Wrote and distributed press releases, op-eds, and executive talking '
              'points for the CEO and board',
          'Managed crisis communications during a public policy dispute, '
              'preserving key media relationships',
        ],
      ),
      ExperienceEntry(
        id: 'ob_e2',
        title: 'Communications Coordinator',
        company: 'Millbrook Public Relations',
        location: 'Boston, MA',
        startDate: 'Sep 2018',
        endDate: 'Jan 2022',
        isCurrent: false,
        bullets: [
          'Coordinated media outreach for 8 client accounts, building a '
              'press contact list of 300+ journalists',
          'Drafted newsletters and social content that grew subscriber base '
              'by 40%',
        ],
      ),
    ],
    education: [
      EducationEntry(
        id: 'ob_edu1',
        degree: 'Bachelor of Arts',
        institution: 'Boston University',
        fieldOfStudy: 'Communications',
        graduationYear: '2018',
        gpa: '3.6',
      ),
    ],
    skills: [
      SkillEntry(id: 'ob_s1', name: 'Media Relations', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'ob_s2', name: 'Press Releases', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'ob_s3', name: 'Crisis Communications', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'ob_s4', name: 'Storytelling', category: SkillCategoryEnum.softSkill),
      SkillEntry(id: 'ob_s5', name: 'Stakeholder Management', category: SkillCategoryEnum.softSkill),
    ],
    certifications: [],
  );

  // ── Persona G — Maya Thompson (recent graduate / entry-level) ──────────────────
  static final ResumeRenderData mayaThompson = ResumeRenderData(
    contact: ContactInfo(
      firstName: 'Maya',
      lastName: 'Thompson',
      professionalTitle: 'Aspiring Business Analyst',
      city: 'Columbus',
      state: 'OH',
      phone: '(614) 555-0116',
      email: 'maya.thompson@email.com',
      linkedInUrl: 'linkedin.com/in/mayathompson',
    ),
    summary: 'Recent business graduate with internship experience in data '
        'analysis and process improvement. Strong analytical and '
        'communication skills developed through coursework, a Fortune 500 '
        'internship, and part-time retail leadership.',
    experience: [
      ExperienceEntry(
        id: 'mt_e1',
        title: 'Business Analyst Intern',
        company: 'Greenfield Consumer Goods',
        location: 'Columbus, OH',
        startDate: 'Jun 2025',
        endDate: 'Aug 2025',
        isCurrent: false,
        bullets: [
          'Analyzed sales data across 5 regions to identify a 12% underperforming '
              'product line, presenting findings to the regional director',
          'Built a dashboard in Excel that automated a weekly reporting process, '
              'saving the team an estimated 3 hours per week',
        ],
      ),
      ExperienceEntry(
        id: 'mt_e2',
        title: 'Shift Lead',
        company: 'Northgate Retail Co.',
        location: 'Columbus, OH',
        startDate: 'Sep 2023',
        endDate: 'Present',
        isCurrent: true,
        bullets: [
          'Supervise a team of 6 associates during evening shifts, coordinating '
              'scheduling and daily sales targets',
          'Recognized as Employee of the Quarter for consistently exceeding '
              'customer satisfaction benchmarks',
        ],
      ),
    ],
    education: [
      EducationEntry(
        id: 'mt_edu1',
        degree: 'Bachelor of Science',
        institution: 'Ohio State University',
        fieldOfStudy: 'Business Administration',
        graduationYear: '2026',
        gpa: '3.6',
      ),
    ],
    skills: [
      SkillEntry(id: 'mt_s1', name: 'Excel', category: SkillCategoryEnum.toolsSoftware),
      SkillEntry(id: 'mt_s2', name: 'Data Analysis', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'mt_s3', name: 'SQL', category: SkillCategoryEnum.technical),
      SkillEntry(id: 'mt_s4', name: 'Team Leadership', category: SkillCategoryEnum.softSkill),
      SkillEntry(id: 'mt_s5', name: 'Communication', category: SkillCategoryEnum.softSkill),
    ],
    certifications: [],
  );
}
