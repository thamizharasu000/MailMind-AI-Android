import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/email_item.dart';
import '../services/api_service.dart';

const _ink = Color(0xFF24243D);
const _muted = Color(0xFF7D7E98);
const _purple = Color(0xFF6554D9);
const _line = Color(0xFFECECF5);

const _demoEmails = <EmailItem>[
  EmailItem(
    id: 'demo-assignment', sender: 'Dr. Priya Kumar',
    subject: 'Assignment submission reminder',
    preview: 'Please submit the Unit 3 assignment before Friday.',
    body: 'Please submit your Unit 3 assignment before Friday. Review the assignment instructions and upload it to the college portal.',
    date: '9:10 AM', isImportant: true, isDemo: true,
  ),
  EmailItem(
    id: 'demo-placement', sender: 'Campus Placement Cell',
    subject: 'Upcoming aptitude training',
    preview: 'Training session is scheduled for tomorrow at 10 AM.',
    body: 'The aptitude training session is scheduled for tomorrow at 10 AM. Please be on time and bring your notebook.',
    date: '8:42 AM', isDemo: true,
  ),
  EmailItem(
    id: 'demo-project', sender: 'Project Team',
    subject: 'Smart Campus project update',
    preview: 'Can you share the latest UI progress by this evening?',
    body: 'Can you share the latest UI progress by this evening? We would like to review the dashboard and task screens.',
    date: 'Yesterday', isDemo: true,
  ),
  EmailItem(
    id: 'demo-security', sender: 'Account Security',
    subject: 'Review your account activity',
    preview: 'Review the sign-in details in your account settings.',
    body: 'Please review account activity through the official website or application. Do not share passwords or one-time codes by email.',
    date: 'Yesterday', isDemo: true,
  ),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiService _api = ApiService();
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  final Set<String> _doneTasks = <String>{};
  int _tab = 0;
  bool _connected = false;
  bool _loading = false;
  String? _token;
  String? _notice;
  List<EmailItem> _emails = _demoEmails;
  final List<String> _tasks = <String>[
    'Review Unit 3 assignment instructions',
    'Prepare for aptitude training',
    'Share the Smart Campus UI progress',
  ];

  @override
  void initState() {
    super.initState();
    _restoreSession();
    _listenForOAuthReturn();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final token = await _api.readToken();
    if (!mounted) return;
    if (token != null && token.isNotEmpty) {
      setState(() {
        _token = token;
        _connected = true;
      });
      await _refreshInbox(showError: false);
    }
  }

  Future<void> _listenForOAuthReturn() async {
    _linkSubscription = _appLinks.uriLinkStream.listen(
      _handleIncomingLink,
      onError: (_) {
        if (mounted) setState(() => _notice = 'Could not complete Google sign-in. Try again.');
      },
    );
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) await _handleIncomingLink(initial);
    } catch (_) {
      // A normal app launch does not have an incoming URI.
    }
  }

  Future<void> _handleIncomingLink(Uri uri) async {
    if (uri.scheme != 'mailmind' || uri.host != 'auth') return;
    final ticket = uri.queryParameters['ticket'];
    if (ticket == null || ticket.isEmpty) {
      if (mounted) setState(() => _notice = 'Login callback did not include a ticket.');
      return;
    }
    setState(() {
      _loading = true;
      _notice = 'Finishing secure Google sign-in…';
    });
    try {
      await _api.exchangeTicket(ticket);
      final token = await _api.readToken();
      if (!mounted) return;
      setState(() {
        _token = token;
        _connected = token != null;
        _notice = 'Gmail connected successfully.';
      });
      await _refreshInbox();
    } catch (error) {
      if (mounted) setState(() => _notice = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectGmail() async {
    final uri = Uri.parse('${ApiService.baseUrl}/auth/google');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) setState(() => _notice = 'Could not open browser for Google sign-in.');
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Set MAILMIND_API_BASE to your reachable backend HTTPS URL first.');
      }
    }
  }

  Future<void> _refreshInbox({bool showError = true}) async {
    if (_token == null) return;
    setState(() => _loading = true);
    try {
      final data = await _api.loadEmails(_token!);
      if (!mounted) return;
      setState(() {
        _emails = data.map(EmailItem.fromJson).toList();
        _notice = _emails.isEmpty ? 'Your Gmail inbox is empty.' : null;
      });
    } catch (error) {
      if (!mounted) return;
      if (showError) setState(() => _notice = error.toString());
      if (error.toString().contains('Session expired')) {
        await _api.clearToken();
        setState(() {
          _token = null;
          _connected = false;
          _emails = _demoEmails;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    await _api.logout(_token);
    if (!mounted) return;
    setState(() {
      _token = null;
      _connected = false;
      _emails = _demoEmails;
      _notice = 'Disconnected from Gmail. Showing sample emails.';
      _tab = 0;
    });
  }

  Future<void> _runAnalysis(EmailItem email, String action, {bool closeSheet = false}) async {
    if (closeSheet) Navigator.of(context).maybePop();
    final title = _analysisTitle(action);
    String result;
    if (_connected && _token != null && !email.isDemo) {
      setState(() {
        _loading = true;
        _notice = 'Analyzing securely…';
      });
      try {
        result = await _api.analyze(token: _token!, emailId: email.id, task: action);
      } catch (error) {
        result = 'Could not analyze this email.\n\n$error';
      } finally {
        if (mounted) setState(() { _loading = false; _notice = null; });
      }
    } else {
      result = _demoAnalysis(email, action);
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(22, 8, 22, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _actionIcon(action, size: 42),
                const SizedBox(width: 12),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: _ink))),
              ]),
              const SizedBox(height: 12),
              Text(email.subject, style: const TextStyle(fontWeight: FontWeight.w700, color: _ink)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: const Color(0xFFF7F6FD), borderRadius: BorderRadius.circular(16)),
                child: action == 'reply'
                    ? TextFormField(
                        initialValue: result,
                        minLines: 5,
                        maxLines: 12,
                        keyboardType: TextInputType.multiline,
                        decoration: const InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          hintText: 'Review and edit the reply before using it.',
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: const TextStyle(height: 1.55, color: _ink, fontSize: 14),
                      )
                    : SelectableText(result, style: const TextStyle(height: 1.55, color: _ink, fontSize: 14)),
              ),
              if (email.isDemo || !_connected) ...[
                const SizedBox(height: 12),
                const Text('Demo output only — connect Gmail and configure the AI backend for real analysis.', style: TextStyle(color: _muted, fontSize: 12)),
              ],
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == 'tasks' && email.isDemo) {
      setState(() {
        final taskName = email.subject;
        if (!_tasks.contains(taskName)) _tasks.insert(0, taskName);
      });
    }
  }

  String _analysisTitle(String action) => switch (action) {
        'summary' => 'AI Email Summary',
        'tasks' => 'Extracted Tasks',
        'reply' => 'Suggested Reply',
        'phishing' => 'Email Security Check',
        _ => 'Email Analysis',
      };

  String _demoAnalysis(EmailItem email, String action) => switch (action) {
        'summary' => 'Key points\n• ${email.preview}\n• Sender: ${email.sender}\n• Open the original email to confirm all details.',
        'tasks' => 'Suggested action\n• Review: ${email.subject}\n• Deadline: check the original email to confirm.\n• This sample is not saved to a calendar.',
        'reply' => 'Hello ${email.sender},\n\nThank you for the update. I have received your email and will review the details.\n\nRegards',
        'phishing' => 'Safety checklist\n• Verify the full sender address.\n• Avoid unexpected links and attachments.\n• Never share passwords or OTPs by email.\n\nThis demo did not scan the real message or its links.',
        _ => 'No analysis available.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 18,
        title: Row(children: [
          Image.asset('assets/brand/mailmind_logo.png', width: 38, height: 38),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('MailMind AI', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _ink)),
            Text('YOUR SMART EMAIL ASSISTANT', style: TextStyle(fontSize: 9, letterSpacing: 1.0, color: _muted, fontWeight: FontWeight.w600)),
          ]),
        ]),
        actions: [
          IconButton(tooltip: 'Refresh inbox', onPressed: _loading ? null : () => _refreshInbox(), icon: const Icon(Icons.refresh_rounded)),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: PopupMenuButton<String>(
              onSelected: (value) => value == 'logout' ? _logout() : _connectGmail(),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'connect', child: Text(_connected ? 'Reconnect Gmail' : 'Connect Gmail')),
                if (_connected) const PopupMenuItem(value: 'logout', child: Text('Disconnect Gmail')),
              ],
              child: CircleAvatar(radius: 18, backgroundColor: const Color(0xFFE7E2FF), child: Icon(_connected ? Icons.verified_user_outlined : Icons.person_outline, color: _purple, size: 20)),
            ),
          ),
        ],
      ),
      body: SafeArea(child: _pageBody()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        height: 72,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEAE6FF),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.inbox_outlined), selectedIcon: Icon(Icons.inbox_rounded), label: 'Inbox'),
          NavigationDestination(icon: Icon(Icons.checklist_rounded), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_outlined), selectedIcon: Icon(Icons.auto_awesome), label: 'AI Assist'),
          NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Security'),
        ],
      ),
    );
  }

  Widget _pageBody() {
    return RefreshIndicator(
      onRefresh: () => _refreshInbox(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
        children: [
          if (_tab == 0) ..._inboxPage(),
          if (_tab == 1) ..._tasksPage(),
          if (_tab == 2) ..._assistantPage(),
          if (_tab == 3) ..._securityPage(),
          if (_notice != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFFFF3D9), borderRadius: BorderRadius.circular(14)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline, color: Color(0xFF8A5C00), size: 20),
                const SizedBox(width: 9),
                Expanded(child: Text(_notice!, style: const TextStyle(color: Color(0xFF694A0B), fontSize: 12, height: 1.4))),
                IconButton(onPressed: () => setState(() => _notice = null), icon: const Icon(Icons.close, size: 16), visualDensity: VisualDensity.compact),
              ]),
            ),
          ],
          if (_loading) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }

  List<Widget> _inboxPage() => [
    const SizedBox(height: 8),
    Text(_connected ? 'Your inbox, simplified.' : 'Good morning 👋', style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: _ink, letterSpacing: -.5)),
    const SizedBox(height: 5),
    Text(_connected ? 'Here is what needs your attention.' : 'Let AI take the busywork out of email.', style: const TextStyle(color: _muted, fontSize: 14)),
    const SizedBox(height: 18),
    _heroCard(),
    const SizedBox(height: 15),
    Row(children: [
      Expanded(child: _statCard(Icons.mail_outline, '${_emails.length}', 'Emails', const Color(0xFFEAE6FF), _purple)),
      const SizedBox(width: 10),
      Expanded(child: _statCard(Icons.priority_high_rounded, '${_emails.where((e) => e.isImportant).length + (_connected ? 0 : 1)}', 'Important', const Color(0xFFFFE9DD), const Color(0xFFD96A35))),
      const SizedBox(width: 10),
      Expanded(child: _statCard(Icons.task_alt_rounded, '${_tasks.length - _doneTasks.length}', 'Tasks', const Color(0xFFDDF7E9), const Color(0xFF16845E))),
    ]),
    const SizedBox(height: 23),
    Row(children: [const Expanded(child: Text('Recent emails', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: _ink))), Text(_connected ? 'LIVE GMAIL' : 'SAMPLE PREVIEW', style: TextStyle(fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w800, color: _connected ? const Color(0xFF15835D) : _muted))]),
    const SizedBox(height: 12),
    if (!_connected) _demoHint(),
    ..._emails.map(_emailCard),
  ];

  Widget _heroCard() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: const LinearGradient(colors: [Color(0xFF4C3CC2), Color(0xFF7B63EC)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      boxShadow: [BoxShadow(color: _purple.withValues(alpha: .18), blurRadius: 20, offset: const Offset(0, 9))],
    ),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(99)), child: const Text('✦  YOUR AI BRIEFING', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .8))),
        const SizedBox(height: 13),
        const Text('Less email.\nMore focus.', style: TextStyle(color: Colors.white, fontSize: 24, height: 1.12, fontWeight: FontWeight.w900)),
        const SizedBox(height: 9),
        Text(_connected ? 'Your messages are ready to analyze.' : 'Connect Gmail to unlock your daily summary.', style: TextStyle(color: Colors.white.withValues(alpha: .86), fontSize: 12, height: 1.4)),
        const SizedBox(height: 14),
        FilledButton.tonal(
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: _purple, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10)),
          onPressed: _connected ? () => setState(() => _tab = 2) : _connectGmail,
          child: Text(_connected ? 'Open AI Assist' : 'Connect Gmail'),
        ),
      ])),
      const SizedBox(width: 8),
      Container(width: 82, height: 82, decoration: BoxDecoration(color: Colors.white.withValues(alpha: .15), borderRadius: BorderRadius.circular(24)), child: const Icon(Icons.mark_email_unread_rounded, color: Colors.white, size: 48)),
    ]),
  );

  Widget _statCard(IconData icon, String value, String label, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 9),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 32, height: 32, decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: fg, size: 18)),
      const SizedBox(height: 10),
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: _ink)),
      Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
    ]),
  );

  Widget _demoHint() => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFEDEAFF), borderRadius: BorderRadius.circular(14)),
    child: const Row(children: [Icon(Icons.lightbulb_outline, color: _purple, size: 19), SizedBox(width: 9), Expanded(child: Text('These are sample emails. Connect Gmail to load your real inbox.', style: TextStyle(fontSize: 12, color: Color(0xFF4F429C), height: 1.35)))]),
  );

  Widget _emailCard(EmailItem email) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => _showEmailActions(email),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _line)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _senderAvatar(email.sender),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: Text(email.sender, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _ink))), const SizedBox(width: 6), Text(email.date.isEmpty ? '' : _shortDate(email.date), style: const TextStyle(color: _muted, fontSize: 10))]),
            const SizedBox(height: 5),
            Row(children: [Expanded(child: Text(email.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _ink))), if (email.isImportant) Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: const Color(0xFFFFE6DF), borderRadius: BorderRadius.circular(99)), child: const Text('Important', style: TextStyle(fontSize: 9, color: Color(0xFFC14D30), fontWeight: FontWeight.w700))) ]),
            const SizedBox(height: 5),
            Text(email.preview.isEmpty ? email.body : email.preview, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              _miniAction('Summary', Icons.auto_awesome, () => _runAnalysis(email, 'summary')),
              _miniAction('Tasks', Icons.checklist, () => _runAnalysis(email, 'tasks')),
              _miniAction('Security', Icons.shield_outlined, () => _runAnalysis(email, 'phishing')),
            ]),
          ])),
        ]),
      ),
    ),
  );

  Widget _senderAvatar(String sender) {
    final initials = sender.trim().split(RegExp(r'\s+')).take(2).map((s) => s.isEmpty ? '' : s[0]).join().toUpperCase();
    return Container(width: 43, height: 43, alignment: Alignment.center, decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFEAE5FF), Color(0xFFD9D2FF)]), borderRadius: BorderRadius.circular(14)), child: Text(initials.isEmpty ? 'M' : initials, style: const TextStyle(color: _purple, fontWeight: FontWeight.w900, fontSize: 12)));
  }

  String _shortDate(String value) => value.length > 17 ? value.substring(0, 16) : value;

  Widget _miniAction(String text, IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(9),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6), decoration: BoxDecoration(color: const Color(0xFFF3F1FF), borderRadius: BorderRadius.circular(9)), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 13, color: _purple), const SizedBox(width: 5), Text(text, style: const TextStyle(fontSize: 10, color: _purple, fontWeight: FontWeight.w700))])),
  );

  Future<void> _showEmailActions(EmailItem email) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(email.subject, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 5),
          Text('From ${email.sender}', style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 12),
          Text(email.body.isEmpty ? email.preview : email.body, style: const TextStyle(height: 1.45, color: _ink)),
          const SizedBox(height: 15),
          const Text('QUICK ACTIONS', style: TextStyle(color: _muted, fontSize: 10, letterSpacing: 1, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ActionChip(avatar: const Icon(Icons.auto_awesome, size: 17), label: const Text('Summarize'), onPressed: () => _runAnalysis(email, 'summary', closeSheet: true)),
            ActionChip(avatar: const Icon(Icons.checklist, size: 17), label: const Text('Extract tasks'), onPressed: () => _runAnalysis(email, 'tasks', closeSheet: true)),
            ActionChip(avatar: const Icon(Icons.reply, size: 17), label: const Text('Draft reply'), onPressed: () => _runAnalysis(email, 'reply', closeSheet: true)),
            ActionChip(avatar: const Icon(Icons.shield_outlined, size: 17), label: const Text('Check security'), onPressed: () => _runAnalysis(email, 'phishing', closeSheet: true)),
          ]),
        ]),
      )),
    );
  }

  List<Widget> _tasksPage() => [
    const SizedBox(height: 12),
    const Text('Your action list', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: _ink)),
    const SizedBox(height: 5),
    const Text('Turn email requests into clear next steps.', style: TextStyle(color: _muted, fontSize: 13)),
    const SizedBox(height: 17),
    Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: const Color(0xFFEAE6FF), borderRadius: BorderRadius.circular(18)), child: Row(children: [const Icon(Icons.task_alt, color: _purple, size: 28), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${_doneTasks.length} of ${_tasks.length} completed', style: const TextStyle(color: _ink, fontWeight: FontWeight.w800)), const Text('Tasks below are local demo tasks until you extract from Gmail.', style: TextStyle(color: Color(0xFF5F5794), fontSize: 11, height: 1.4))]))])),
    const SizedBox(height: 15),
    ..._tasks.map((task) => Container(margin: const EdgeInsets.only(bottom: 9), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(16)), child: CheckboxListTile(value: _doneTasks.contains(task), onChanged: (v) => setState(() => v == true ? _doneTasks.add(task) : _doneTasks.remove(task)), controlAffinity: ListTileControlAffinity.leading, activeColor: _purple, title: Text(task, style: TextStyle(color: _doneTasks.contains(task) ? _muted : _ink, fontSize: 13, fontWeight: FontWeight.w600, decoration: _doneTasks.contains(task) ? TextDecoration.lineThrough : null)), subtitle: const Text('Deadline: confirm from original email', style: TextStyle(fontSize: 11, color: _muted)))),
    const SizedBox(height: 8),
    OutlinedButton.icon(onPressed: () => setState(() => _tab = 0), icon: const Icon(Icons.email_outlined), label: const Text('Choose an email to extract tasks')),
  ];

  List<Widget> _assistantPage() => [
    const SizedBox(height: 12),
    const Text('AI email assistant', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: _ink)),
    const SizedBox(height: 5),
    const Text('Pick an email and choose what AI should do.', style: TextStyle(color: _muted, fontSize: 13)),
    const SizedBox(height: 20),
    _featureCard('summary', 'Smart summaries', 'Turn long emails into clear key points.', () => _showInboxPicker('summary')),
    _featureCard('tasks', 'Task extraction', 'Find requests, actions and stated deadlines.', () => _showInboxPicker('tasks')),
    _featureCard('reply', 'AI reply writer', 'Draft a polite reply for you to review.', () => _showInboxPicker('reply')),
    _featureCard('security', 'Phishing warning', 'Look for suspicious sender and message signals.', () => _showInboxPicker('phishing')),
    const SizedBox(height: 10),
    const Text('AI may make mistakes. Always verify dates, facts and security warnings before acting.', style: TextStyle(fontSize: 11, color: _muted, height: 1.4)),
  ];

  Widget _featureCard(String asset, String title, String desc, VoidCallback onTap) => Padding(padding: const EdgeInsets.only(bottom: 11), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(18)), child: Row(children: [Image.asset('assets/features/$asset.png', width: 52, height: 52), const SizedBox(width: 13), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: _ink, fontSize: 14, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(desc, style: const TextStyle(color: _muted, fontSize: 11, height: 1.35))])), const Icon(Icons.arrow_forward_ios_rounded, size: 15, color: _muted)]))));

  Future<void> _showInboxPicker(String task) async {
    await showModalBottomSheet<void>(context: context, showDragHandle: true, backgroundColor: Colors.white, builder: (context) => SafeArea(child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(18, 4, 18, 24), children: [const Text('Choose an email', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _ink)), const SizedBox(height: 10), ..._emails.map((email) => ListTile(leading: _actionIcon(task, size: 40), title: Text(email.subject, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text(email.sender, maxLines: 1), onTap: () => _runAnalysis(email, task, closeSheet: true)))])));
  }

  List<Widget> _securityPage() => [
    const SizedBox(height: 12),
    const Text('Stay safe in your inbox', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: _ink)),
    const SizedBox(height: 5),
    const Text('A warning system, not a guarantee of safety.', style: TextStyle(color: _muted, fontSize: 13)),
    const SizedBox(height: 18),
    Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF25306F), Color(0xFF6554D9)]), borderRadius: BorderRadius.circular(22)), child: const Row(children: [Icon(Icons.shield_moon_rounded, color: Colors.white, size: 48), SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Think before you click', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)), SizedBox(height: 5), Text('Check links, sender addresses and requests for sensitive information.', style: TextStyle(color: Color(0xFFE2DDFF), fontSize: 12, height: 1.4))]))])),
    const SizedBox(height: 16),
    _securityTip(Icons.alternate_email, 'Check the full sender', 'Look for look-alike domains and unexpected sender addresses.'),
    _securityTip(Icons.link_off_rounded, 'Avoid suspicious links', 'Do not trust a displayed link label alone; inspect the destination.'),
    _securityTip(Icons.password_rounded, 'Never share OTPs', 'Legitimate support staff should not ask you to email passwords or OTPs.'),
    _securityTip(Icons.payments_outlined, 'Verify urgent payments', 'Confirm money transfers through a separate trusted channel.'),
    const SizedBox(height: 10),
    FilledButton.icon(onPressed: () => _showInboxPicker('phishing'), icon: const Icon(Icons.search), label: const Text('Check an email')),
  ];

  Widget _securityTip(IconData icon, String title, String desc) => Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.white, border: Border.all(color: _line), borderRadius: BorderRadius.circular(16)), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: const Color(0xFFFFE8EA), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: const Color(0xFFC93E52), size: 20)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(desc, style: const TextStyle(color: _muted, fontSize: 11, height: 1.45))]))]));

  Widget _actionIcon(String action, {double size = 42}) {
    final details = switch (action) {
      'summary' => (Icons.auto_awesome, const Color(0xFFEAE6FF), _purple),
      'tasks' => (Icons.checklist_rounded, const Color(0xFFDDF7E9), const Color(0xFF16845E)),
      'reply' => (Icons.reply_rounded, const Color(0xFFE3EEFF), const Color(0xFF3569E8)),
      _ => (Icons.shield_outlined, const Color(0xFFFFE4E7), const Color(0xFFDD3A53)),
    };
    return Container(width: size, height: size, decoration: BoxDecoration(color: details.$2, borderRadius: BorderRadius.circular(size * .28)), child: Icon(details.$1, color: details.$3, size: size * .48));
  }
}
