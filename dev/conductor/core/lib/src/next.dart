// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:args/command_runner.dart';
import 'package:file/file.dart' show File;
import 'package:meta/meta.dart' show visibleForTesting;

import 'context.dart';
import 'git.dart';
import 'globals.dart';
import 'proto/conductor_state.pb.dart' as pb;
import 'proto/conductor_state.pbenum.dart';
import 'repository.dart';
import 'state.dart' as state_import;

const String kStateOption = 'state-file';
const String kYesFlag = 'yes';

/// Command to proceed from one [pb.ReleasePhase] to the next.
class NextCommand extends Command<void> {
  NextCommand({
    required this.checkouts,
  }) {
    final String defaultPath = state_import.defaultStateFilePath(checkouts.platform);
    argParser.addOption(
      kStateOption,
      defaultsTo: defaultPath,
      help: 'Path to persistent state file. Defaults to $defaultPath',
    );
    argParser.addFlag(
      kYesFlag,
      help: 'Auto-accept any confirmation prompts.',
      hide: true, // primarily for integration testing
    );
    argParser.addFlag(
      kForceFlag,
      help: 'Force push when updating remote git branches.',
    );
  }

  final Checkouts checkouts;

  @override
  String get name => 'next';

  @override
  String get description => 'Proceed to the next release phase.';

  @override
  Future<void> run() {
    final File stateFile = checkouts.fileSystem.file(argResults![kStateOption]);
    if (!stateFile.existsSync()) {
      throw ConductorException(
          'No persistent state file found at ${stateFile.path}.',
      );
    }
    final pb.ConductorState state = state_import.readStateFromFile(stateFile);

    return NextContext(
      autoAccept: argResults![kYesFlag] as bool,
      checkouts: checkouts,
      force: argResults![kForceFlag] as bool,
      stateFile: stateFile,
    ).run(state);
  }
}

/// Utility class for proceeding to the next step in a release.
///
/// Any calls to functions that cause side effects are wrapped in methods to
/// allow overriding in unit tests.
class NextContext extends Context {
  const NextContext({
    required this.autoAccept,
    required this.force,
    required super.checkouts,
    required super.stateFile,
  });

  final bool autoAccept;
  final bool force;

  Future<void> run(pb.ConductorState state) async {
    const List<CherrypickState> finishedStates = <CherrypickState>[
      CherrypickState.COMPLETED,
      CherrypickState.ABANDONED,
    ];
    switch (state.currentPhase) {
      case pb.ReleasePhase.APPLY_ENGINE_CHERRYPICKS:
        final Remote upstream = Remote(
            name: RemoteName.upstream,
            url: state.engine.upstream.url,
        );
        final EngineRepository engine = EngineRepository(
            checkouts,
            initialRef: state.engine.workingBranch,
            upstreamRemote: upstream,
            previousCheckoutLocation: state.engine.checkoutPath,
        );
        if (!state_import.requiresEnginePR(state)) {
          stdio.printStatus(
              'This release has no engine cherrypicks. No Engine PR is necessary.\n',
          );
          break;
        }

        final List<pb.Cherrypick> unappliedCherrypicks = <pb.Cherrypick>[];
        for (final pb.Cherrypick cherrypick in state.engine.cherrypicks) {
          if (!finishedStates.contains(cherrypick.state)) {
            unappliedCherrypicks.add(cherrypick);
          }
        }

        if (unappliedCherrypicks.isEmpty) {
          stdio.printStatus('All engine cherrypicks have been auto-applied by the conductor.\n');
        } else {
          if (unappliedCherrypicks.length == 1) {
            stdio.printStatus('There was ${unappliedCherrypicks.length} cherrypick that was not auto-applied.');
          } else {
            stdio.printStatus('There were ${unappliedCherrypicks.length} cherrypicks that were not auto-applied.');
          }
          stdio.printStatus('These must be applied manually in the directory '
              '${state.engine.checkoutPath} before proceeding.\n');
        }
        if (autoAccept == false) {
          final bool response = await prompt(
            'Are you ready to push your engine branch to the repository '
            '${state.engine.mirror.url}?',
          );
          if (!response) {
            stdio.printError('Aborting command.');
            updateState(state, stdio.logs);
            return;
          }
        }

        await pushWorkingBranch(engine, state.engine);
        break;
      case pb.ReleasePhase.CODESIGN_ENGINE_BINARIES:
        stdio.printStatus(<String>[
          'You must validate pre-submit CI for your engine PR, merge it, and codesign',
          'binaries before proceeding.\n',
        ].join('\n'));
        if (autoAccept == false) {
          // TODO(fujino): actually test if binaries have been codesigned on macOS
          final bool response = await prompt(
            'Has CI passed for the engine PR and binaries been codesigned?',
          );
          if (!response) {
            stdio.printError('Aborting command.');
            updateState(state, stdio.logs);
            return;
          }
        }
        break;
      case pb.ReleasePhase.APPLY_FRAMEWORK_CHERRYPICKS:
        if (state.engine.cherrypicks.isEmpty && state.engine.dartRevision.isEmpty) {
          stdio.printStatus(
              'This release has no engine cherrypicks, and thus the engine.version file\n'
              'in the framework does not need to be updated.',
          );

          if (state.framework.cherrypicks.isEmpty) {
            stdio.printStatus(
                'This release also has no framework cherrypicks. Therefore, a framework\n'
                'pull request is not required.',
            );
            break;
          }
        }
        final Remote engineUpstreamRemote = Remote(
            name: RemoteName.upstream,
            url: state.engine.upstream.url,
        );
        final EngineRepository engine = EngineRepository(
            checkouts,
            // We explicitly want to check out the merged version from upstream
            initialRef: '${engineUpstreamRemote.name}/${state.engine.candidateBranch}',
            upstreamRemote: engineUpstreamRemote,
            previousCheckoutLocation: state.engine.checkoutPath,
        );

        final String engineRevision = await engine.reverseParse('HEAD');

        final Remote upstream = Remote(
          name: RemoteName.upstream,
          url: state.framework.upstream.url,
        );
        final FrameworkRepository framework = FrameworkRepository(
          checkouts,
          initialRef: state.framework.workingBranch,
          upstreamRemote: upstream,
          previousCheckoutLocation: state.framework.checkoutPath,
        );
        stdio.printStatus('Writing candidate branch...');
        bool needsCommit = await framework.updateCandidateBranchVersion(state.releaseVersion);
        if (needsCommit) {
          final String revision = await framework.commit(
              'Create candidate branch version ${state.engine.candidateBranch} for ${state.releaseChannel}',
              addFirst: true,
          );
          // append to list of cherrypicks so we know a PR is required
          state.framework.cherrypicks.add(pb.Cherrypick(
                  appliedRevision: revision,
                  state: pb.CherrypickState.COMPLETED,
          ));
        }
        stdio.printStatus('Rolling new engine hash $engineRevision to framework checkout...');
        needsCommit = await framework.updateEngineRevision(engineRevision);
        if (needsCommit) {
          final String revision = await framework.commit(
              'Update Engine revision to $engineRevision for ${state.releaseChannel} release ${state.releaseVersion}',
              addFirst: true,
          );
          // append to list of cherrypicks so we know a PR is required
          state.framework.cherrypicks.add(pb.Cherrypick(
                  appliedRevision: revision,
                  state: pb.CherrypickState.COMPLETED,
          ));
        }

        final List<pb.Cherrypick> unappliedCherrypicks = <pb.Cherrypick>[];
        for (final pb.Cherrypick cherrypick in state.framework.cherrypicks) {
          if (!finishedStates.contains(cherrypick.state)) {
            unappliedCherrypicks.add(cherrypick);
          }
        }

        if (state.framework.cherrypicks.isEmpty) {
          stdio.printStatus(
              'This release has no framework cherrypicks. However, a framework PR is still\n'
              'required to roll engine cherrypicks.',
          );
        } else if (unappliedCherrypicks.isEmpty) {
          stdio.printStatus('All framework cherrypicks were auto-applied by the conductor.');
        } else {
          if (unappliedCherrypicks.length == 1) {
            stdio.printStatus('There was ${unappliedCherrypicks.length} cherrypick that was not auto-applied.',);
          }
          else {
            stdio.printStatus('There were ${unappliedCherrypicks.length} cherrypicks that were not auto-applied.',);
          }
          stdio.printStatus(
              'These must be applied manually in the directory '
              '${state.framework.checkoutPath} before proceeding.\n',
          );
        }

        if (autoAccept == false) {
          final bool response = await prompt(
            'Are you ready to push your framework branch to the repository '
            '${state.framework.mirror.url}?',
          );
          if (!response) {
            stdio.printError('Aborting command.');
            updateState(state, stdio.logs);
            return;
          }
        }

        await pushWorkingBranch(framework, state.framework);
        break;
      case pb.ReleasePhase.PUBLISH_VERSION:
        stdio.printStatus('Please ensure that you have merged your framework PR and that');
        stdio.printStatus('post-submit CI has finished successfully.\n');
        final Remote upstream = Remote(
            name: RemoteName.upstream,
            url: state.framework.upstream.url,
        );
        final FrameworkRepository framework = FrameworkRepository(
            checkouts,
            // We explicitly want to check out the merged version from upstream
            initialRef: '${upstream.name}/${state.framework.candidateBranch}',
            upstreamRemote: upstream,
            previousCheckoutLocation: state.framework.checkoutPath,
        );
        final String headRevision = await framework.reverseParse('HEAD');
        if (autoAccept == false) {
          final bool response = await prompt(
            'Are you ready to tag commit $headRevision as ${state.releaseVersion}\n'
            'and push to remote ${state.framework.upstream.url}?',
          );
          if (!response) {
            stdio.printError('Aborting command.');
            updateState(state, stdio.logs);
            return;
          }
        }
        await framework.tag(headRevision, state.releaseVersion, upstream.name);
        break;
      case pb.ReleasePhase.PUBLISH_CHANNEL:
        final Remote upstream = Remote(
            name: RemoteName.upstream,
            url: state.framework.upstream.url,
        );
        final FrameworkRepository framework = FrameworkRepository(
            checkouts,
            // We explicitly want to check out the merged version from upstream
            initialRef: '${upstream.name}/${state.framework.candidateBranch}',
            upstreamRemote: upstream,
            previousCheckoutLocation: state.framework.checkoutPath,
        );
        final String headRevision = await framework.reverseParse('HEAD');
        final List<String> releaseRefs = <String>[state.releaseChannel];
        if (kSynchronizeDevWithBeta && state.releaseChannel == 'beta') {
          releaseRefs.add('dev');
        }
        for (final String releaseRef in releaseRefs) {
          if (autoAccept == false) {
            // dryRun: true means print out git command
            await framework.pushRef(
              fromRef: headRevision,
              toRef: releaseRef,
              remote: state.framework.upstream.url,
              force: force,
              dryRun: true,
            );

            final bool response = await prompt(
              'Are you ready to publish version ${state.releaseVersion} to $releaseRef?',
            );
            if (!response) {
              stdio.printError('Aborting command.');
              updateState(state, stdio.logs);
              return;
            }
          }
          await framework.pushRef(
            fromRef: headRevision,
            toRef: releaseRef,
            remote: state.framework.upstream.url,
            force: force,
          );
        }
        break;
      case pb.ReleasePhase.VERIFY_RELEASE:
        stdio.printStatus(
            'The current status of packaging builds can be seen at:\n'
            '\t$kLuciPackagingConsoleLink',
        );
        if (autoAccept == false) {
          final bool response = await prompt(
              'Have all packaging builds finished successfully and post release announcements been completed?');
          if (!response) {
            stdio.printError('Aborting command.');
            updateState(state, stdio.logs);
            return;
          }
        }
        break;
      case pb.ReleasePhase.RELEASE_COMPLETED:
        throw ConductorException('This release is finished.');
    }
    final ReleasePhase nextPhase = state_import.getNextPhase(state.currentPhase);
    stdio.printStatus('\nUpdating phase from ${state.currentPhase} to $nextPhase...\n');
    state.currentPhase = nextPhase;
    stdio.printStatus(state_import.phaseInstructions(state));

    updateState(state, stdio.logs);
  }

  /// Push the working branch to the user's mirror.
  ///
  /// [repository] represents the actual Git repository on disk, and is used to
  /// call `git push`, while [pbRepository] represents the user-specified
  /// configuration for the repository, and is used to read the name of the
  /// working branch and the mirror's remote name.
  ///
  /// May throw either a [ConductorException] if the user already has a branch
  /// of the same name on their mirror, or a [GitException] for any other
  /// failures from the underlying git process call.
  @visibleForTesting
  Future<void> pushWorkingBranch(Repository repository, pb.Repository pbRepository) async {
    try {
      await repository.pushRef(
          fromRef: 'HEAD',
          // Explicitly create new branch
          toRef: 'refs/heads/${pbRepository.workingBranch}',
          remote: pbRepository.mirror.name,
          force: force,
      );
    } on GitException catch (exception) {
      if (exception.type == GitExceptionType.PushRejected && force == false) {
        throw ConductorException(
          'Push failed because the working branch named '
          '${pbRepository.workingBranch} already exists on your mirror. '
          'Re-run this command with --force to overwrite the remote branch.\n'
          '${exception.message}',
        );
      }
      rethrow;
    }
  }
}
