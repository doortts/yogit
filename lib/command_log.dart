import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import 'git.dart';

/// What a line in the console is: something the user asked for, or something
/// the app ran on its own behalf.
enum CommandLogKind { action, command }

enum CommandLogState { running, ok, failed }

/// One line of the console. Mutable in one direction only — a command starts
/// [CommandLogState.running] and is settled once, when the process returns.
class CommandLogEntry {
  /// A heading, not a job: it holds no exit code and never runs or fails on
  /// its own. It appears when the first command under it does, so a menu item
  /// the user backed out of at the confirmation leaves nothing behind.
  CommandLogEntry.action({required this.id, required this.label})
    : kind = CommandLogKind.action,
      actionId = null,
      executable = '',
      arguments = const [],
      workingDirectory = null,
      redacted = false,
      startedAt = DateTime.now(),
      duration = Duration.zero;

  CommandLogEntry.command({
    required this.id,
    required this.actionId,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.redacted,
  }) : kind = CommandLogKind.command,
       label = '',
       startedAt = DateTime.now();

  final int id;
  final CommandLogKind kind;

  /// The action this command was run for, or null when the app ran it on its
  /// own — a reload, a poll, a lookup nobody asked for by name. Cleared if the
  /// action's own line falls off the end before this one does, so the id never
  /// points at a line that is no longer there.
  int? actionId;

  /// An action's name, in the words the user just read off the menu.
  final String label;

  final String executable;
  final List<String> arguments;

  /// Only shown when it is not the repository the console belongs to.
  final String? workingDirectory;

  /// Whether this command's output is withheld. Set from the command itself,
  /// before it runs, so a failure cannot leak what a success would have hidden.
  final bool redacted;

  final DateTime startedAt;

  Duration? duration;
  int? exitCode;
  String stdout = '';
  String stderr = '';

  /// How many bytes of each stream were thrown away, when more arrived than is
  /// kept. Null when the whole thing is here.
  int? droppedStdoutBytes;
  int? droppedStderrBytes;

  /// What the process threw instead of answering — no exit code, no output.
  String? failure;

  /// A heading is never running and never failed: it is a name, and the lines
  /// under it are what succeeded or did not.
  CommandLogState get state => duration == null
      ? CommandLogState.running
      : failure == null && (exitCode == null || exitCode == 0)
      ? CommandLogState.ok
      : CommandLogState.failed;

  /// The command as a line someone could paste into a terminal.
  String get commandLine => [executable, ...arguments.map(_quoted)].join(' ');

  static final _needsQuoting = RegExp(r'''[\s'"$`\\]''');

  static String _quoted(String argument) =>
      argument.isNotEmpty && !argument.contains(_needsQuoting)
      ? argument
      : "'${argument.replaceAll("'", r"'\''")}'";
}

/// Every process the app runs, in the order it ran them, and the user actions
/// they were run for.
///
/// The app reaches the outside world through one function type — [CommandRunner]
/// — so wrapping that function once catches every git call the app makes,
/// wherever it is made from. Nothing else has to know this exists.
class CommandLog extends ChangeNotifier {
  CommandLog({this.limit = 500, this.outputLimit = 8 * 1024});

  /// How many lines are kept. The oldest goes when the next one arrives.
  final int limit;

  /// How much of each stream is kept, in characters. A diff answers in
  /// megabytes and none of it belongs in memory twice.
  final int outputLimit;

  final _entries = <CommandLogEntry>[];
  var _nextId = 0;

  /// The action a command started inside, carried by the zone rather than
  /// through every call: the code between the button and `git` is a dozen
  /// frames deep and none of it should have to know about the console.
  static const _actionKey = #yogitCommandLogAction;

  List<CommandLogEntry> get entries => List.unmodifiable(_entries);

  int get runningCount =>
      _entries.where((entry) => entry.state == CommandLogState.running).length;

  int get failedCount =>
      _entries.where((entry) => entry.state == CommandLogState.failed).length;

  void clear() {
    _entries.clear();
    _notify();
  }

  /// Runs [body] under [label]: every command it reaches is filed under that
  /// name, and the name appears in the console just above the first of them.
  ///
  /// Nothing is written for a body that runs no command. Half of what the user
  /// presses ends at a confirmation they decline, or at a guard that says
  /// something else is already running, and a console that announced those
  /// would be describing work that never happened.
  Future<T> action<T>(String label, Future<T> Function() body) => runZoned(
    body,
    zoneValues: {_actionKey: _PendingAction(_nextId++, label)},
  );

  /// [action] for a callback that is not itself asynchronous — a button whose
  /// handler starts the work and returns. Kept synchronous so an error thrown
  /// straight out of the handler still reaches the caller as one.
  void runNamed(String label, VoidCallback body) => runZoned(
    body,
    zoneValues: {_actionKey: _PendingAction(_nextId++, label)},
  );

  /// The same runner, with every call written down.
  CommandRunner wrap(CommandRunner runner) =>
      (
        executable,
        arguments, {
        String? workingDirectory,
        Map<String, String>? environment,
      }) => _record(
        executable,
        arguments,
        workingDirectory,
        () => runner(
          executable,
          arguments,
          workingDirectory: workingDirectory,
          environment: environment,
        ),
      );

  /// The byte-stream runner the large diffs go through, written down the same
  /// way. Its answer is bytes, and only the first [outputLimit] of them are
  /// ever turned into text.
  RawCommandRunner wrapRaw(RawCommandRunner runner) =>
      (executable, arguments, {String? workingDirectory}) => _record(
        executable,
        arguments,
        workingDirectory,
        () => runner(executable, arguments, workingDirectory: workingDirectory),
      );

  Future<ProcessResult> _record(
    String executable,
    List<String> arguments,
    String? workingDirectory,
    Future<ProcessResult> Function() run,
  ) async {
    final entry = _add(
      CommandLogEntry.command(
        id: _nextId++,
        actionId: _headingFor(Zone.current[_actionKey] as _PendingAction?),
        executable: executable,
        arguments: redactArguments(executable, arguments),
        workingDirectory: workingDirectory,
        redacted: hidesOutput(executable),
      ),
    );
    final started = DateTime.now();
    try {
      final result = await run();
      entry.exitCode = result.exitCode;
      if (!entry.redacted) {
        _fill(entry, result);
      }
      return result;
    } catch (error) {
      entry.failure = _failureText(error, redacted: entry.redacted);
      rethrow;
    } finally {
      entry.duration = DateTime.now().difference(started);
      _notify();
    }
  }

  /// What a thrown process becomes on screen. `ProcessException` prints the
  /// whole command line, arguments and all, so for a command whose arguments
  /// were masked its own text is a way straight back to the secret: only the
  /// operating system's own complaint is kept, and anything else it might be
  /// is not shown at all.
  static String _failureText(Object error, {required bool redacted}) {
    if (!redacted) return '$error';
    return error is ProcessException && error.message.isNotEmpty
        ? error.message
        : '실행하지 못했습니다';
  }

  /// The id a command should be filed under, writing the action's heading
  /// first if this is the first command to need it.
  int? _headingFor(_PendingAction? pending) {
    if (pending == null) return null;
    if (!pending.written) {
      pending.written = true;
      _add(CommandLogEntry.action(id: pending.id, label: pending.label));
    }
    return pending.id;
  }

  void _fill(CommandLogEntry entry, ProcessResult result) {
    final stdout = _text(result.stdout);
    final stderr = _text(result.stderr);
    entry.stdout = stdout.text;
    entry.stderr = stderr.text;
    entry.droppedStdoutBytes = stdout.dropped;
    entry.droppedStderrBytes = stderr.dropped;
  }

  /// The head of a stream, and how many bytes were left behind. `Process.run`
  /// answers with text and the raw runner with bytes; both are measured in
  /// bytes here, so one number means one thing wherever it is shown.
  ({String text, int? dropped}) _text(Object? stream) {
    if (stream is List<int>) {
      return stream.length > outputLimit
          ? (
              text: utf8.decode(
                stream.sublist(0, outputLimit),
                allowMalformed: true,
              ),
              dropped: stream.length - outputLimit,
            )
          : (text: utf8.decode(stream, allowMalformed: true), dropped: null);
    }
    final full = stream is String ? stream : '';
    if (full.length <= outputLimit) return (text: full, dropped: null);
    // Never between the two halves of one character: a lone surrogate is a
    // broken glyph on screen and a wrong byte count underneath it.
    final cut = _isHighSurrogate(full.codeUnitAt(outputLimit - 1))
        ? outputLimit - 1
        : outputLimit;
    return (
      text: full.substring(0, cut),
      dropped: utf8.encode(full.substring(cut)).length,
    );
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

  CommandLogEntry _add(CommandLogEntry entry) {
    _entries.add(entry);
    if (_entries.length > limit) {
      final gone = _entries.removeAt(0);
      // An action's commands outlive its name here. They are set loose rather
      // than left pointing at a line the console no longer holds.
      if (gone.kind == CommandLogKind.action) {
        for (final left in _entries) {
          if (left.actionId == gone.id) left.actionId = null;
        }
      }
    }
    _notify();
    return entry;
  }

  var _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// A command outliving the window it was started from still comes back and
  /// settles its line; there is just nobody left to tell.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Commands whose output is a secret. The keychain hands back the token
  /// itself on stdout, so that stream is never read into the console — not on
  /// success, and not on the failure that would print it in an error.
  @visibleForTesting
  static bool hidesOutput(String executable) =>
      _basename(executable) == 'security';

  /// The arguments as they may be shown. A secret passed on the command line
  /// is already visible to every process on the machine, but that is no reason
  /// to put it on the screen too.
  @visibleForTesting
  static List<String> redactArguments(
    String executable,
    List<String> arguments,
  ) {
    if (!hidesOutput(executable)) return arguments;
    // `security add-generic-password -w <token>`: the flag's value is the
    // secret, and every other argument is the account it belongs to.
    final redacted = [...arguments];
    for (var index = 0; index < redacted.length - 1; index++) {
      if (redacted[index] == '-w') redacted[index + 1] = '••••••';
    }
    return redacted;
  }

  static String _basename(String path) => path.split('/').last;
}

/// A name waiting for something to happen under it. Carried by the zone from
/// the button that was pressed down to whatever runs git, and turned into a
/// line in the console the first time that happens.
class _PendingAction {
  _PendingAction(this.id, this.label);

  final int id;
  final String label;
  var written = false;
}

/// Hands the log down to the widgets that know what the user just pressed.
///
/// A menu item knows its own name and a button knows its tooltip; the code
/// that runs git a dozen frames later does not, and should not have to carry
/// it. This is how the name reaches [CommandLog.action] without becoming an
/// argument on everything in between.
class CommandLogScope extends InheritedWidget {
  const CommandLogScope({required this.log, required super.child, super.key});

  final CommandLog log;

  static CommandLog? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CommandLogScope>()?.log;

  /// Runs [body] as a named action when there is a console listening, and
  /// plainly when there is not.
  static void run(BuildContext context, String label, VoidCallback body) {
    final log = maybeOf(context);
    return log == null ? body() : log.runNamed(label, body);
  }

  @override
  bool updateShouldNotify(CommandLogScope oldWidget) =>
      !identical(oldWidget.log, log);
}

extension CommandLogRepository on CommandLog {
  /// A repository that runs its git through this log. Every place the app
  /// opens one goes through here, so none of them has to remember to wrap
  /// both runners — and the one that forgot would be a repository whose work
  /// never reaches the console.
  GitRepository repositoryAt(
    String root, {
    required String gitExecutable,
    CommandRunner? runner,
    RawCommandRunner? rawRunner,
  }) => GitRepository(
    root,
    gitExecutable: gitExecutable,
    runner: wrap(runner ?? runProcess),
    rawRunner: wrapRaw(rawRunner ?? runRawProcess),
  );
}
