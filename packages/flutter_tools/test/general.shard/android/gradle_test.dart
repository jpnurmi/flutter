// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart = 2.8

import 'package:file/memory.dart';
import 'package:flutter_tools/src/android/android_sdk.dart';
import 'package:flutter_tools/src/android/gradle.dart';
import 'package:flutter_tools/src/android/gradle_utils.dart';
import 'package:flutter_tools/src/artifacts.dart';
import 'package:flutter_tools/src/base/common.dart';
import 'package:flutter_tools/src/base/file_system.dart';
import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/base/platform.dart';
import 'package:flutter_tools/src/build_info.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/globals.dart' as globals;
import 'package:flutter_tools/src/project.dart';
import 'package:test/fake.dart';

import '../../src/common.dart';
import '../../src/context.dart';

const String kModulePubspec = '''
name: test
flutter:
  module:
    androidPackage: com.example
    androidX: true
''';

void main() {
  Cache.flutterRoot = getFlutterRoot();

  group('build artifacts', () {
    FileSystem fileSystem;

    setUp(() {
      fileSystem = MemoryFileSystem.test();
    });

    testWithoutContext('getApkDirectory in app projects', () {
      final FlutterProject project = FlutterProject.fromDirectoryTest(fileSystem.currentDirectory);

      expect(
        getApkDirectory(project).path, '/build/app/outputs/flutter-apk',
      );
    });

    testWithoutContext('getApkDirectory in module projects', () {
      fileSystem.currentDirectory
        .childFile('pubspec.yaml')
        .writeAsStringSync(kModulePubspec);
      final FlutterProject project = FlutterProject.fromDirectoryTest(fileSystem.currentDirectory);

      expect(project.isModule, true);
      expect(
        getApkDirectory(project).path, '/build/host/outputs/apk',
      );
    });

    testWithoutContext('getBundleDirectory in app projects', () {
      final FlutterProject project = FlutterProject.fromDirectoryTest(fileSystem.currentDirectory);

      expect(
        getBundleDirectory(project).path, '/build/app/outputs/bundle',
      );
    });

    testWithoutContext('getBundleDirectory in module projects', () {
      fileSystem.currentDirectory
        .childFile('pubspec.yaml')
        .writeAsStringSync(kModulePubspec);
      final FlutterProject project = FlutterProject.fromDirectoryTest(fileSystem.currentDirectory);

      expect(project.isModule, true);
      expect(
        getBundleDirectory(project).path, '/build/host/outputs/bundle',
      );
    });

    testWithoutContext('getRepoDirectory', () {
      expect(
        getRepoDirectory(fileSystem.directory('foo')).path,
        equals(fileSystem.path.join('foo','outputs', 'repo')),
      );
    });
  });

  group('gradle tasks', () {
    testWithoutContext('assemble release', () {
      expect(
        getAssembleTaskFor(const BuildInfo(BuildMode.release, null, treeShakeIcons: false)),
        equals('assembleRelease'),
      );
      expect(
        getAssembleTaskFor(const BuildInfo(BuildMode.release, 'flavorFoo', treeShakeIcons: false)),
        equals('assembleFlavorFooRelease'),
      );
    });

    testWithoutContext('assemble debug', () {
      expect(
        getAssembleTaskFor(BuildInfo.debug),
        equals('assembleDebug'),
      );
      expect(
        getAssembleTaskFor(const BuildInfo(BuildMode.debug, 'flavorFoo', treeShakeIcons: false)),
        equals('assembleFlavorFooDebug'),
      );
    });

    testWithoutContext('assemble profile', () {
      expect(
        getAssembleTaskFor(const BuildInfo(BuildMode.profile, null, treeShakeIcons: false)),
        equals('assembleProfile'),
      );
      expect(
        getAssembleTaskFor(const BuildInfo(BuildMode.profile, 'flavorFoo', treeShakeIcons: false)),
        equals('assembleFlavorFooProfile'),
      );
    });
  });

  group('listApkPaths', () {
    testWithoutContext('Finds APK without flavor in release', () {
      final Iterable<String> apks = listApkPaths(
        const AndroidBuildInfo(BuildInfo(BuildMode.release, '', treeShakeIcons: false)),
      );

      expect(apks, <String>['app-release.apk']);
    });

    testWithoutContext('Finds APK with flavor in release mode', () {
      final Iterable<String> apks = listApkPaths(
        const AndroidBuildInfo(BuildInfo(BuildMode.release, 'flavor1', treeShakeIcons: false)),
      );

      expect(apks, <String>['app-flavor1-release.apk']);
    });

    testWithoutContext('Finds APK with flavor in release mode', () {
      final Iterable<String> apks = listApkPaths(
        const AndroidBuildInfo(BuildInfo(BuildMode.release, 'flavorA', treeShakeIcons: false)),
      );

      expect(apks, <String>['app-flavora-release.apk']);
    });

    testWithoutContext('Finds APK with flavor in release mode - AGP v3', () {
      final Iterable<String> apks = listApkPaths(
        const AndroidBuildInfo(BuildInfo(BuildMode.release, 'flavor1', treeShakeIcons: false)),
      );

      expect(apks, <String>['app-flavor1-release.apk']);
    });

    testWithoutContext('Finds APK with split-per-abi', () {
      final Iterable<String> apks = listApkPaths(
        const AndroidBuildInfo(BuildInfo(BuildMode.release, 'flavor1', treeShakeIcons: false), splitPerAbi: true),
      );

      expect(apks, unorderedEquals(<String>[
        'app-armeabi-v7a-flavor1-release.apk',
        'app-arm64-v8a-flavor1-release.apk',
        'app-x86_64-flavor1-release.apk',
      ]));
    });

    testWithoutContext('Finds APK with split-per-abi when flavor contains uppercase letters', () {
      final Iterable<String> apks = listApkPaths(
        const AndroidBuildInfo(BuildInfo(BuildMode.release, 'flavorA', treeShakeIcons: false), splitPerAbi: true),
      );

      expect(apks, unorderedEquals(<String>[
        'app-armeabi-v7a-flavora-release.apk',
        'app-arm64-v8a-flavora-release.apk',
        'app-x86_64-flavora-release.apk',
      ]));
    });

  });

  group('gradle build', () {
    testUsingContext('do not crash if there is no Android SDK', () async {
      expect(() {
        updateLocalProperties(project: FlutterProject.fromDirectoryTest(globals.fs.currentDirectory));
      }, throwsToolExit(
        message: '${globals.logger.terminal.warningMark} No Android SDK found. Try setting the ANDROID_SDK_ROOT environment variable.',
      ));
    }, overrides: <Type, Generator>{
      AndroidSdk: () => null,
    });
  });

  group('Gradle local.properties', () {
    Artifacts localEngineArtifacts;
    FileSystem fs;

    setUp(() {
      fs = MemoryFileSystem.test();
      localEngineArtifacts = Artifacts.test(localEngine: 'out/android_arm');
    });

    void testUsingAndroidContext(String description, dynamic Function() testMethod) {
      testUsingContext(description, testMethod, overrides: <Type, Generator>{
        Artifacts: () => localEngineArtifacts,
        Platform: () => FakePlatform(),
        FileSystem: () => fs,
        ProcessManager: () => FakeProcessManager.any(),
      });
    }

    String propertyFor(String key, File file) {
      final Iterable<String> result = file.readAsLinesSync()
          .where((String line) => line.startsWith('$key='))
          .map((String line) => line.split('=')[1]);
      return result.isEmpty ? null : result.first;
    }

    Future<void> checkBuildVersion({
      String manifest,
      BuildInfo buildInfo,
      String expectedBuildName,
      String expectedBuildNumber,
    }) async {
      final File manifestFile = globals.fs.file('path/to/project/pubspec.yaml');
      manifestFile.createSync(recursive: true);
      manifestFile.writeAsStringSync(manifest);


      updateLocalProperties(
        project: FlutterProject.fromDirectoryTest(globals.fs.directory('path/to/project')),
        buildInfo: buildInfo,
        requireAndroidSdk: false,
      );

      final File localPropertiesFile = globals.fs.file('path/to/project/android/local.properties');
      expect(propertyFor('flutter.versionName', localPropertiesFile), expectedBuildName);
      expect(propertyFor('flutter.versionCode', localPropertiesFile), expectedBuildNumber);
    }

    testUsingAndroidContext('extract build name and number from pubspec.yaml', () async {
      const String manifest = '''
name: test
version: 1.0.0+1
dependencies:
  flutter:
    sdk: flutter
flutter:
''';

      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, treeShakeIcons: false);
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.0',
        expectedBuildNumber: '1',
      );
    });

    testUsingAndroidContext('extract build name from pubspec.yaml', () async {
      const String manifest = '''
name: test
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, treeShakeIcons: false);
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.0',
      );
    });

    testUsingAndroidContext('allow build info to override build name', () async {
      const String manifest = '''
name: test
version: 1.0.0+1
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildName: '1.0.2', treeShakeIcons: false);
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '1',
      );
    });

    testUsingAndroidContext('allow build info to override build number', () async {
      const String manifest = '''
name: test
version: 1.0.0+1
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildNumber: '3', treeShakeIcons: false);
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.0',
        expectedBuildNumber: '3',
      );
    });

    testUsingAndroidContext('allow build info to override build name and number', () async {
      const String manifest = '''
name: test
version: 1.0.0+1
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildName: '1.0.2', buildNumber: '3', treeShakeIcons: false);
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '3',
      );
    });

    testUsingAndroidContext('allow build info to override build name and set number', () async {
      const String manifest = '''
name: test
version: 1.0.0
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildName: '1.0.2', buildNumber: '3', treeShakeIcons: false);
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '3',
      );
    });

    testUsingAndroidContext('allow build info to set build name and number', () async {
      const String manifest = '''
name: test
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      const BuildInfo buildInfo = BuildInfo(BuildMode.release, null, buildName: '1.0.2', buildNumber: '3', treeShakeIcons: false);
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: buildInfo,
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '3',
      );
    });

    testUsingAndroidContext('allow build info to unset build name and number', () async {
      const String manifest = '''
name: test
dependencies:
  flutter:
    sdk: flutter
flutter:
''';
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: const BuildInfo(BuildMode.release, null, treeShakeIcons: false),
      );
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: const BuildInfo(BuildMode.release, null, buildName: '1.0.2', buildNumber: '3', treeShakeIcons: false),
        expectedBuildName: '1.0.2',
        expectedBuildNumber: '3',
      );
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: const BuildInfo(BuildMode.release, null, buildName: '1.0.3', buildNumber: '4', treeShakeIcons: false),
        expectedBuildName: '1.0.3',
        expectedBuildNumber: '4',
      );
      // Values don't get unset.
      await checkBuildVersion(
        manifest: manifest,
        expectedBuildName: '1.0.3',
        expectedBuildNumber: '4',
      );
      // Values get unset.
      await checkBuildVersion(
        manifest: manifest,
        buildInfo: const BuildInfo(BuildMode.release, null, treeShakeIcons: false),
      );
    });
  });

  group('gradle version', () {
    testWithoutContext('should be compatible with the Android plugin version', () {
      // Granular versions.
      expect(getGradleVersionFor('1.0.0'), '2.3');
      expect(getGradleVersionFor('1.0.1'), '2.3');
      expect(getGradleVersionFor('1.0.2'), '2.3');
      expect(getGradleVersionFor('1.0.4'), '2.3');
      expect(getGradleVersionFor('1.0.8'), '2.3');
      expect(getGradleVersionFor('1.1.0'), '2.3');
      expect(getGradleVersionFor('1.1.2'), '2.3');
      expect(getGradleVersionFor('1.1.2'), '2.3');
      expect(getGradleVersionFor('1.1.3'), '2.3');
      // Version Ranges.
      expect(getGradleVersionFor('1.2.0'), '2.9');
      expect(getGradleVersionFor('1.3.1'), '2.9');

      expect(getGradleVersionFor('1.5.0'), '2.2.1');

      expect(getGradleVersionFor('2.0.0'), '2.13');
      expect(getGradleVersionFor('2.1.2'), '2.13');

      expect(getGradleVersionFor('2.1.3'), '2.14.1');
      expect(getGradleVersionFor('2.2.3'), '2.14.1');

      expect(getGradleVersionFor('2.3.0'), '3.3');

      expect(getGradleVersionFor('3.0.0'), '4.1');

      expect(getGradleVersionFor('3.1.0'), '4.4');

      expect(getGradleVersionFor('3.2.0'), '4.6');
      expect(getGradleVersionFor('3.2.1'), '4.6');

      expect(getGradleVersionFor('3.3.0'), '4.10.2');
      expect(getGradleVersionFor('3.3.2'), '4.10.2');

      expect(getGradleVersionFor('3.4.0'), '5.6.2');
      expect(getGradleVersionFor('3.5.0'), '5.6.2');

      expect(getGradleVersionFor('4.0.0'), '6.7');
      expect(getGradleVersionFor('4.1.0'), '6.7');

      expect(getGradleVersionFor('7.0'), '7.4');
      expect(getGradleVersionFor('7.1.2'), '7.4');
      expect(getGradleVersionFor('7.2'), '7.4');
    });

    testWithoutContext('throws on unsupported versions', () {
      expect(() => getGradleVersionFor('3.6.0'),
          throwsA(predicate<Exception>((Exception e) => e is ToolExit)));
    });
  });

  group('isAppUsingAndroidX', () {
    FileSystem fs;

    setUp(() {
      fs = MemoryFileSystem.test();
    });

    testUsingContext('returns true when the project is using AndroidX', () async {
      final Directory androidDirectory = globals.fs.systemTempDirectory.createTempSync('flutter_android.');

      androidDirectory
        .childFile('gradle.properties')
        .writeAsStringSync('android.useAndroidX=true');

      expect(isAppUsingAndroidX(androidDirectory), isTrue);

    }, overrides: <Type, Generator>{
      FileSystem: () => fs,
      ProcessManager: () => FakeProcessManager.any(),
    });

    testUsingContext('returns false when the project is not using AndroidX', () async {
      final Directory androidDirectory = globals.fs.systemTempDirectory.createTempSync('flutter_android.');

      androidDirectory
        .childFile('gradle.properties')
        .writeAsStringSync('android.useAndroidX=false');

      expect(isAppUsingAndroidX(androidDirectory), isFalse);

    }, overrides: <Type, Generator>{
      FileSystem: () => fs,
      ProcessManager: () => FakeProcessManager.any(),
    });

    testUsingContext('returns false when gradle.properties does not exist', () async {
      final Directory androidDirectory = globals.fs.systemTempDirectory.createTempSync('flutter_android.');

      expect(isAppUsingAndroidX(androidDirectory), isFalse);

    }, overrides: <Type, Generator>{
      FileSystem: () => fs,
      ProcessManager: () => FakeProcessManager.any(),
    });
  });

  group('printHowToConsumeAar', () {
    BufferLogger logger;
    FileSystem fileSystem;

    setUp(() {
      logger = BufferLogger.test();
      fileSystem = MemoryFileSystem.test();
    });

    testWithoutContext('stdout contains release, debug and profile', () async {
      printHowToConsumeAar(
        buildModes: const <String>{'release', 'debug', 'profile'},
        androidPackage: 'com.mycompany',
        repoDirectory: fileSystem.directory('build/'),
        buildNumber: '2.2',
        logger: logger,
        fileSystem: fileSystem,
      );

      expect(
        logger.statusText,
        contains(
          '\n'
          'Consuming the Module\n'
          '  1. Open <host>/app/build.gradle\n'
          '  2. Ensure you have the repositories configured, otherwise add them:\n'
          '\n'
          '      String storageUrl = System.env.FLUTTER_STORAGE_BASE_URL ?: "https://storage.googleapis.com"\n'
          '      repositories {\n'
          '        maven {\n'
          "            url 'build/'\n"
          '        }\n'
          '        maven {\n'
          '            url "\$storageUrl/download.flutter.io"\n'
          '        }\n'
          '      }\n'
          '\n'
          '  3. Make the host app depend on the Flutter module:\n'
          '\n'
          '    dependencies {\n'
          "      releaseImplementation 'com.mycompany:flutter:2.2:release'\n"
          "      debugImplementation 'com.mycompany:flutter:2.2:debug'\n"
          "      profileImplementation 'com.mycompany:flutter:2.2:profile'\n"
          '    }\n'
          '\n'
          '\n'
          '  4. Add the `profile` build type:\n'
          '\n'
          '    android {\n'
          '      buildTypes {\n'
          '        profile {\n'
          '          initWith debug\n'
          '        }\n'
          '      }\n'
          '    }\n'
          '\n'
          'To learn more, visit https://flutter.dev/go/build-aar\n'
        )
      );
    });

    testWithoutContext('stdout contains release', () async {
      printHowToConsumeAar(
        buildModes: const <String>{'release'},
        androidPackage: 'com.mycompany',
        repoDirectory: fileSystem.directory('build/'),
        logger: logger,
        fileSystem: fileSystem,
      );

      expect(
        logger.statusText,
        contains(
          '\n'
          'Consuming the Module\n'
          '  1. Open <host>/app/build.gradle\n'
          '  2. Ensure you have the repositories configured, otherwise add them:\n'
          '\n'
          '      String storageUrl = System.env.FLUTTER_STORAGE_BASE_URL ?: "https://storage.googleapis.com"\n'
          '      repositories {\n'
          '        maven {\n'
          "            url 'build/'\n"
          '        }\n'
          '        maven {\n'
          '            url "\$storageUrl/download.flutter.io"\n'
          '        }\n'
          '      }\n'
          '\n'
          '  3. Make the host app depend on the Flutter module:\n'
          '\n'
          '    dependencies {\n'
          "      releaseImplementation 'com.mycompany:flutter:1.0:release'\n"
          '    }\n'
          '\n'
          'To learn more, visit https://flutter.dev/go/build-aar\n'
        )
      );
    });

    testWithoutContext('stdout contains debug', () async {
      printHowToConsumeAar(
        buildModes: const <String>{'debug'},
        androidPackage: 'com.mycompany',
        repoDirectory: fileSystem.directory('build/'),
        logger: logger,
        fileSystem: fileSystem,
      );

      expect(
        logger.statusText,
        contains(
          '\n'
          'Consuming the Module\n'
          '  1. Open <host>/app/build.gradle\n'
          '  2. Ensure you have the repositories configured, otherwise add them:\n'
          '\n'
          '      String storageUrl = System.env.FLUTTER_STORAGE_BASE_URL ?: "https://storage.googleapis.com"\n'
          '      repositories {\n'
          '        maven {\n'
          "            url 'build/'\n"
          '        }\n'
          '        maven {\n'
          '            url "\$storageUrl/download.flutter.io"\n'
          '        }\n'
          '      }\n'
          '\n'
          '  3. Make the host app depend on the Flutter module:\n'
          '\n'
          '    dependencies {\n'
          "      debugImplementation 'com.mycompany:flutter:1.0:debug'\n"
          '    }\n'
          '\n'
          'To learn more, visit https://flutter.dev/go/build-aar\n'
        )
      );
    });

    testWithoutContext('stdout contains profile', () async {
      printHowToConsumeAar(
        buildModes: const <String>{'profile'},
        androidPackage: 'com.mycompany',
        repoDirectory: fileSystem.directory('build/'),
        buildNumber: '1.0',
        logger: logger,
        fileSystem: fileSystem,
      );

      expect(
        logger.statusText,
        contains(
          '\n'
          'Consuming the Module\n'
          '  1. Open <host>/app/build.gradle\n'
          '  2. Ensure you have the repositories configured, otherwise add them:\n'
          '\n'
          '      String storageUrl = System.env.FLUTTER_STORAGE_BASE_URL ?: "https://storage.googleapis.com"\n'
          '      repositories {\n'
          '        maven {\n'
          "            url 'build/'\n"
          '        }\n'
          '        maven {\n'
          '            url "\$storageUrl/download.flutter.io"\n'
          '        }\n'
          '      }\n'
          '\n'
          '  3. Make the host app depend on the Flutter module:\n'
          '\n'
          '    dependencies {\n'
          "      profileImplementation 'com.mycompany:flutter:1.0:profile'\n"
          '    }\n'
          '\n'
          '\n'
          '  4. Add the `profile` build type:\n'
          '\n'
          '    android {\n'
          '      buildTypes {\n'
          '        profile {\n'
          '          initWith debug\n'
          '        }\n'
          '      }\n'
          '    }\n'
          '\n'
          'To learn more, visit https://flutter.dev/go/build-aar\n'
        )
      );
    });
  });

  test('Current settings.gradle is in our legacy settings.gradle file set', () {
    // If this test fails, you probably edited templates/app/android.tmpl.
    // That's fine, but you now need to add a copy of that file to gradle/settings.gradle.legacy_versions, separated
    // from the previous versions by a line that just says ";EOF".
    final File templateSettingsDotGradle = globals.fs.file(globals.fs.path.join(Cache.flutterRoot, 'packages', 'flutter_tools', 'templates', 'app', 'android.tmpl', 'settings.gradle'));
    final File legacySettingsDotGradleFiles = globals.fs.file(globals.fs.path.join(Cache.flutterRoot, 'packages','flutter_tools', 'gradle', 'settings.gradle.legacy_versions'));
    expect(
      legacySettingsDotGradleFiles.readAsStringSync().split(';EOF').map<String>((String body) => body.trim()),
      contains(templateSettingsDotGradle.readAsStringSync().trim()),
    );
    // TODO(zanderso): This is an integration test and should be moved to the integration shard.
  }, skip: true); // https://github.com/flutter/flutter/issues/87922
}

class FakeGradleUtils extends GradleUtils {
  @override
  String getExecutable(FlutterProject project) {
    return 'gradlew';
  }
}

class FakeAndroidSdk extends Fake implements AndroidSdk { }
