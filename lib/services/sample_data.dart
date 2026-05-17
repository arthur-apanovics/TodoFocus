import 'package:uuid/uuid.dart';
import '../models/enums.dart';
import '../models/goal.dart';
import '../models/sub_task.dart';

/// Static sample data for UI/QA testing.
///
/// Call [SampleData.build()] to get a fresh list with unique IDs — safe to
/// load into the live Hive repository multiple times without key collisions.
/// The legacy [SampleData.goals] getter is kept for InMemoryGoalRepository.
class SampleData {
  SampleData._();

  static const _uuid = Uuid();

  // ── helpers ──────────────────────────────────────────────────────────────

  static String _id() => _uuid.v4();

  static DateTime _ago(int days) =>
      DateTime.now().subtract(Duration(days: days));

  static DateTime _in(int days) =>
      DateTime.now().add(Duration(days: days));

  static SubTask _done(String desc, {int daysAgo = 2, int? effort}) => SubTask(
        subtaskId: _id(),
        description: desc,
        state: SubTaskState.completed,
        assignedDate: _ago(daysAgo + 1),
        completionDate: _ago(daysAgo),
        lastSeenDate: _ago(daysAgo),
        effortEstimate: effort,
      );

  static SubTask _pending(String desc, {int? effort}) => SubTask(
        subtaskId: _id(),
        description: desc,
        effortEstimate: effort,
      );

  // ── public API ───────────────────────────────────────────────────────────

  /// Returns a fresh list with new UUIDs on every call.
  static List<Goal> build() => [
        // ── Active, focused today ─────────────────────────────────────────

        Goal(
          goalId: _id(),
          title: 'Learn Rust programming',
          notes: 'Work through the Rust Book and build a small CLI tool.',
          difficulty: GoalDifficulty.hard,
          dueDate: _in(45),
          isFocusedToday: true,
          todayOrder: 0,
          subtasks: [
            _done('Read chapters 1–4 of the Rust Book', daysAgo: 10, effort: 2),
            _done('Understand ownership and borrowing', daysAgo: 7, effort: 3),
            _done('Work through the guessing game tutorial', daysAgo: 5, effort: 1),
            _pending('Read chapters 5–10 (structs, enums, error handling)', effort: 3),
            _pending('Write a CLI tool using clap'),
            _pending('Explore async Rust with Tokio'),
            _pending('Build a small REST API with Axum'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Train for a 5K run',
          notes: 'Couch to 5K programme — three runs a week.',
          difficulty: GoalDifficulty.easy,
          emoji: 'running',
          dueDate: _ago(3), // overdue
          isFocusedToday: true,
          todayOrder: 1,
          subtasks: [
            _done('Complete week 1 runs', daysAgo: 20, effort: 1),
            _done('Complete week 2 runs', daysAgo: 14, effort: 1),
            _done('Complete week 3 runs', daysAgo: 8, effort: 2),
            _pending('Complete week 4 runs', effort: 2),
            _pending('Complete week 5 runs'),
            _pending('Complete week 6 runs'),
            _pending('Do the final 5K race'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Deep clean the apartment',
          notes: 'Tackle every room systematically before the family visit.',
          difficulty: GoalDifficulty.easy,
          dueDate: _in(1), // tomorrow
          isFocusedToday: true,
          todayOrder: 2,
          subtasks: [
            _done('Buy cleaning supplies', daysAgo: 3),
            _done('Declutter living room and hallway', daysAgo: 2),
            _pending('Scrub bathroom top to bottom'),
            _pending('Mop kitchen floor and clean appliances'),
            _pending('Vacuum and wipe bedroom surfaces'),
            _pending('Take recycling and rubbish to bins'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Train the dog new tricks',
          notes: 'Ten-minute sessions every day using positive reinforcement.',
          difficulty: GoalDifficulty.easy,
          emoji: 'pets',
          isFocusedToday: true,
          todayOrder: 3,
          subtasks: [
            _done('Master "sit" reliably', daysAgo: 14),
            _done('Master "stay" for 30 seconds', daysAgo: 10),
            _done('Master "down"', daysAgo: 6),
            _pending('Learn "roll over"'),
            _pending('Learn "shake"'),
            _pending('Practice recall off-lead in the garden'),
          ],
        ),

        // ── Active, not focused ───────────────────────────────────────────

        Goal(
          goalId: _id(),
          title: 'Read Atomic Habits',
          notes: 'One chapter a day before bed.',
          difficulty: GoalDifficulty.easy,
          emoji: 'reading',
          dueDate: _in(5),
          subtasks: [
            _done('Part 1 — The Fundamentals', daysAgo: 8, effort: 1),
            _done('Part 2 — The 1st & 2nd Laws', daysAgo: 5, effort: 2),
            _pending('Part 3 — The 3rd & 4th Laws', effort: 2),
            _pending('Part 4 — Advanced Tactics'),
            _pending('Write a one-page summary of key takeaways'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Launch MVP side project',
          notes: 'Productivity app. Must go live before the month ends.',
          difficulty: GoalDifficulty.impossible,
          emoji: 'launch',
          dueDate: DateTime.now(), // due today
          subtasks: [
            _done('Define feature scope for MVP', daysAgo: 30),
            _done('Set up repo and CI pipeline', daysAgo: 28),
            _done('Design wireframes', daysAgo: 25),
            _done('Implement authentication', daysAgo: 20),
            _done('Build core CRUD features', daysAgo: 14),
            _done('Integrate Stripe payments', daysAgo: 10),
            _pending('Write onboarding copy and landing page', effort: 3),
            _pending('Set up error monitoring (Sentry)'),
            _pending('Configure custom domain and SSL'),
            _pending('Soft launch to beta testers'),
            _pending('Fix beta feedback bugs'),
            _pending('Announce on social media'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Complete self-assessment tax return',
          notes: 'HMRC deadline passed. Late filing penalty may apply.',
          difficulty: GoalDifficulty.easy,
          dueDate: _ago(5), // overdue
          subtasks: [
            _pending('Gather P60s, invoices, and bank statements'),
            _pending('Log into HMRC and start the return'),
            _pending('Enter employment income'),
            _pending('Add self-employment income and expenses'),
            _pending('Claim allowable deductions'),
            _pending('Review and submit'),
            _pending('Pay any tax owed'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Update resume and LinkedIn profile',
          notes: 'Reflect the last two years of experience.',
          difficulty: GoalDifficulty.easy,
          dueDate: _ago(10), // overdue
          subtasks: [
            _done('List all recent projects and achievements', daysAgo: 14),
            _pending('Rewrite the professional summary'),
            _pending('Update work history with quantified impact'),
            _pending('Add new skills and certifications'),
            _pending('Sync LinkedIn with updated resume'),
            _pending('Ask two colleagues for endorsements'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Complete AWS Solutions Architect certification',
          difficulty: GoalDifficulty.hard,
          emoji: 'certificate',
          dueDate: _in(60),
          subtasks: [
            _done('Purchase Stephane Maarek Udemy course', daysAgo: 30),
            _done('Watch EC2, IAM, and S3 sections', daysAgo: 25),
            _done('Complete VPC and networking modules', daysAgo: 18),
            _pending('Finish remaining service modules', effort: 3),
            _pending('Do two full practice exams'),
            _pending('Review weak areas from practice results'),
            _pending('Book and sit the exam'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Set up home gym',
          difficulty: GoalDifficulty.easy,
          emoji: 'gym',
          dueDate: _in(20),
          subtasks: [
            _done('Research equipment and budget', daysAgo: 10),
            _done('Order adjustable dumbbells and mat', daysAgo: 7),
            _pending('Clear space in the spare room'),
            _pending('Assemble pull-up bar'),
            _pending('Set up resistance bands storage'),
            _pending('Download and follow a beginner programme'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Write a short story',
          notes: 'Target ~4 000 words. Submit to a local writing competition.',
          difficulty: GoalDifficulty.hard,
          dueDate: _in(30),
          subtasks: [
            _done('Brainstorm premise and protagonist', daysAgo: 8),
            _pending('Outline the three-act structure', effort: 2),
            _pending('Write first draft (aim for 5 000 words)', effort: 3),
            _pending('Cut to 4 000 words and tighten prose'),
            _pending('Get feedback from two readers'),
            _pending('Final proofread and format for submission'),
            _pending('Submit before the deadline'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Kitchen renovation',
          notes: 'Full gut and refit — new cabinets, worktops, and appliances.',
          difficulty: GoalDifficulty.impossible,
          dueDate: _in(180),
          subtasks: [
            _done('Get three quotes from contractors', daysAgo: 20),
            _done('Choose contractor and sign contract', daysAgo: 14),
            _pending('Finalise cabinet and worktop choices', effort: 2),
            _pending('Order all materials and appliances'),
            _pending('Demolition week — strip old kitchen'),
            _pending('Plumbing first fix'),
            _pending('Electrical first fix'),
            _pending('Install new cabinets'),
            _pending('Fit worktops'),
            _pending('Install appliances'),
            _pending('Tiling'),
            _pending('Plumbing and electrical second fix'),
            _pending('Snagging list and sign-off'),
            _pending('Paint and dress the room'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Plan European road trip',
          notes: 'Three weeks, five countries, one car.',
          difficulty: GoalDifficulty.hard,
          emoji: 'explore',
          dueDate: _in(120),
          subtasks: [
            _done('Pick countries and rough route', daysAgo: 15),
            _pending('Book ferry crossings', effort: 1),
            _pending('Book accommodation for first two nights'),
            _pending('Plan rough daily driving distances'),
            _pending('Sort travel insurance'),
            _pending('Apply for international driving permit'),
            _pending('Get the car serviced before departure'),
            _pending('Pack a Europe breakdown kit'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Redesign brand identity',
          notes: 'Logo, colour palette, typography, and brand guidelines doc.',
          difficulty: GoalDifficulty.hard,
          dueDate: _in(25),
          subtasks: [
            _done('Audit current branding and list pain points', daysAgo: 12),
            _done('Gather inspiration and mood board', daysAgo: 8),
            _pending('Brief designer with requirements'),
            _pending('Review first concepts and give feedback'),
            _pending('Approve final logo variations'),
            _pending('Compile brand guidelines document'),
            _pending('Roll out new identity across all touchpoints'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Build a React Native app',
          notes: 'Port the web dashboard to mobile for iOS and Android.',
          difficulty: GoalDifficulty.impossible,
          emoji: 'mobile',
          dueDate: _in(90),
          subtasks: [
            _done('Set up Expo project and configure CI', daysAgo: 21),
            _done('Implement navigation structure', daysAgo: 18),
            _done('Build authentication screens', daysAgo: 14),
            _done('Integrate REST API layer', daysAgo: 10),
            _pending('Dashboard screen — charts and stats', effort: 3),
            _pending('Notifications screen', effort: 2),
            _pending('Settings and profile screens'),
            _pending('Offline support with local cache'),
            _pending('Push notifications via Expo'),
            _pending('Submit to App Store review'),
            _pending('Submit to Google Play review'),
            _pending('Monitor crash reports post-launch'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Learn guitar basics',
          notes: 'Twenty minutes a day. Goal: play three songs end to end.',
          difficulty: GoalDifficulty.hard,
          dueDate: _in(90),
          subtasks: [
            _done('Buy a beginner acoustic guitar', daysAgo: 30),
            _done('Learn to tune by ear and with an app', daysAgo: 28),
            _done('Practice open chords: G, C, D, Em', daysAgo: 20),
            _pending('Practice Am and F chord transitions', effort: 2),
            _pending('Learn first full song (Wonderwall)', effort: 2),
            _pending('Learn fingerpicking pattern', effort: 3),
            _pending('Learn second song of choice'),
            _pending('Record a short video to track progress'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Write quarterly project proposal',
          notes: 'Due for the board meeting. Nearly there.',
          difficulty: GoalDifficulty.hard,
          subtasks: [
            _done('Research market and competitors', daysAgo: 10),
            _done('Define objectives and KPIs', daysAgo: 8),
            _done('Draft executive summary', daysAgo: 6),
            _done('Write main body — timeline and resource plan', daysAgo: 4),
            _done('Create supporting slides', daysAgo: 2),
            _pending('Final proofread and send to manager'), // one step left
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Cancel unused subscriptions',
          notes: 'Check bank statements for the last three months.',
          difficulty: GoalDifficulty.easy,
          dueDate: _ago(2), // slightly overdue
          isFocusedToday: true,
          todayOrder: 4,
          subtasks: [
            _done('Export bank statement to spreadsheet', daysAgo: 3),
            _pending('Highlight recurring charges to review'),
            _pending('Cancel streaming services no longer used'),
            _pending('Cancel SaaS trials that auto-converted'),
            _pending('Set a calendar reminder to review again in 3 months'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Start a vegetable garden',
          notes: 'Raised beds in the back garden. Start with easy crops.',
          difficulty: GoalDifficulty.easy,
          // No subtasks — just created, waiting to be decomposed
          subtasks: [],
        ),

        Goal(
          goalId: _id(),
          title: 'Sort through storage boxes',
          notes: 'Five boxes in the loft that have not been opened since 2019.',
          difficulty: GoalDifficulty.easy,
          subtasks: [
            _pending('Bring boxes down from loft'),
            _pending('Sort into keep, donate, and bin piles'),
            _pending('Drop donations at charity shop'),
            _pending('Label and repack the keep items'),
            _pending('Return boxes to loft or dispose'),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Do the weekly grocery run',
          difficulty: GoalDifficulty.easy,
          emoji: 'grocery',
          // No due date, no notes, no subtasks — minimal goal
          subtasks: [],
        ),

        // ── Completed ─────────────────────────────────────────────────────

        Goal(
          goalId: _id(),
          title: 'Set up development environment',
          notes: 'Flutter, VS Code, and all tooling configured and verified.',
          difficulty: GoalDifficulty.easy,
          emoji: 'computer',
          status: GoalStatus.completed,
          subtasks: [
            _done('Install Flutter SDK and configure PATH', daysAgo: 25),
            _done('Install VS Code and Flutter/Dart extensions', daysAgo: 24),
            _done('Run flutter doctor and resolve all issues', daysAgo: 23),
            _done('Connect physical device for testing', daysAgo: 22),
            _done('Create and run a hello-world app', daysAgo: 21),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Book summer holiday',
          notes: 'Two weeks in Portugal.',
          difficulty: GoalDifficulty.easy,
          status: GoalStatus.completed,
          subtasks: [
            _done('Research destinations and dates', daysAgo: 40),
            _done('Book flights', daysAgo: 38),
            _done('Book villa for two weeks', daysAgo: 37),
            _done('Arrange pet care for the cats', daysAgo: 35),
            _done('Buy travel insurance', daysAgo: 34),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Back up old photos to cloud',
          difficulty: GoalDifficulty.easy,
          status: GoalStatus.completed,
          subtasks: [
            _done('Install Google Photos on old laptop', daysAgo: 15),
            _done('Upload 2015–2020 folders', daysAgo: 14),
            _done('Upload phone camera roll backup', daysAgo: 13),
            _done('Verify upload count matches source', daysAgo: 12),
          ],
        ),

        // ── Archived ──────────────────────────────────────────────────────

        Goal(
          goalId: _id(),
          title: 'Get car serviced',
          difficulty: GoalDifficulty.easy,
          status: GoalStatus.archived,
          subtasks: [
            _done('Book service appointment', daysAgo: 45),
            _done('Drop car at garage', daysAgo: 42),
            _done('Collect car and pay', daysAgo: 42),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Open a high-yield savings account',
          notes: 'Move emergency fund to a better rate.',
          difficulty: GoalDifficulty.easy,
          emoji: 'savings',
          status: GoalStatus.archived,
          subtasks: [
            _done('Compare rates on MoneySuperMarket', daysAgo: 60),
            _done('Apply online — identity verification', daysAgo: 58),
            _done('Transfer emergency fund', daysAgo: 57),
            _done('Set up standing order for monthly top-up', daysAgo: 56),
          ],
        ),

        // ── Inbox ─────────────────────────────────────────────────────────

        Goal(
          goalId: _id(),
          title: 'Research standing desk options',
          notes: 'Budget around £400. Must fit in 120 cm wide alcove.',
          status: GoalStatus.inbox,
          difficulty: GoalDifficulty.easy,
          subtasks: [],
        ),

        Goal(
          goalId: _id(),
          title: 'Plan surprise birthday party',
          notes: 'For Alex. Mid-October. Around 20 people.',
          status: GoalStatus.inbox,
          difficulty: GoalDifficulty.hard,
          emoji: '🎉',
          // Mid-planning — subtasks drafted but not yet queued.
          subtasks: [
            SubTask(
              subtaskId: _id(),
              description: 'Pick a date and confirm Alex is free',
            ),
            SubTask(
              subtaskId: _id(),
              description: 'Lock in a venue (Aunt May\'s back garden?)',
            ),
            SubTask(
              subtaskId: _id(),
              description: 'Draft the guest list',
            ),
          ],
        ),

        Goal(
          goalId: _id(),
          title: 'Explore meditation practice',
          status: GoalStatus.inbox,
          difficulty: GoalDifficulty.easy,
          emoji: '🧘',
          subtasks: [],
        ),
      ];

  /// Legacy getter for InMemoryGoalRepository — uses fixed IDs.
  static List<Goal> get goals => build();
}
