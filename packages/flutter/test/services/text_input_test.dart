// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.


import 'dart:convert' show utf8;
import 'dart:convert' show jsonDecode;
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart' show TestWidgetsFlutterBinding;
import 'package:vector_math/vector_math_64.dart';
import '../flutter_test_alternative.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TextInput message channels', () {
    late FakeTextChannel fakeTextChannel;

    setUp(() {
      fakeTextChannel = FakeTextChannel((MethodCall call) async {});
      TextInput.setChannel(fakeTextChannel);
    });

    tearDown(() {
      TextInputConnection.debugResetId();
      TextInput.setChannel(SystemChannels.textInput);
    });

    test('text input client handler responds to reattach with setClient', () async {
      final FakeTextInputClient client = FakeTextInputClient(const TextEditingValue(text: 'test1'));
      TextInput.attach(client, client.configuration);
      fakeTextChannel.validateOutgoingMethodCalls(<MethodCall>[
        MethodCall('TextInput.setClient', <dynamic>[1, client.configuration.toJson()]),
      ]);

      fakeTextChannel.incoming!(const MethodCall('TextInputClient.requestExistingInputState', null));

      expect(fakeTextChannel.outgoingCalls.length, 3);
      fakeTextChannel.validateOutgoingMethodCalls(<MethodCall>[
        // From original attach
        MethodCall('TextInput.setClient', <dynamic>[1, client.configuration.toJson()]),
        // From requestExistingInputState
        MethodCall('TextInput.setClient', <dynamic>[1, client.configuration.toJson()]),
        MethodCall('TextInput.setEditingState', client.currentTextEditingValue.toJSON()),
      ]);
    });

    test('text input client handler responds to reattach with setClient (null TextEditingValue)', () async {
      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      TextInput.attach(client, client.configuration);
      fakeTextChannel.validateOutgoingMethodCalls(<MethodCall>[
        MethodCall('TextInput.setClient', <dynamic>[1, client.configuration.toJson()]),
      ]);

      fakeTextChannel.incoming!(const MethodCall('TextInputClient.requestExistingInputState', null));

      expect(fakeTextChannel.outgoingCalls.length, 3);
      fakeTextChannel.validateOutgoingMethodCalls(<MethodCall>[
        // From original attach
        MethodCall('TextInput.setClient', <dynamic>[1, client.configuration.toJson()]),
        // From original attach
        MethodCall('TextInput.setClient', <dynamic>[1, client.configuration.toJson()]),
        // From requestExistingInputState
        const MethodCall(
            'TextInput.setEditingState',
            <String, dynamic>{
              'text': '',
              'selectionBase': -1,
              'selectionExtent': -1,
              'selectionAffinity': 'TextAffinity.downstream',
              'selectionIsDirectional': false,
              'composingBase': -1,
              'composingExtent': -1,
            }),
      ]);
    });
  });

  group('TextInputConfiguration', () {
    tearDown(() {
      TextInputConnection.debugResetId();
    });

    test('sets expected defaults', () {
      const TextInputConfiguration configuration = TextInputConfiguration();
      expect(configuration.inputType, TextInputType.text);
      expect(configuration.readOnly, false);
      expect(configuration.obscureText, false);
      expect(configuration.autocorrect, true);
      expect(configuration.actionLabel, null);
      expect(configuration.textCapitalization, TextCapitalization.none);
      expect(configuration.keyboardAppearance, Brightness.light);
    });

    test('text serializes to JSON', () async {
      const TextInputConfiguration configuration = TextInputConfiguration(
        inputType: TextInputType.text,
        readOnly: true,
        obscureText: true,
        autocorrect: false,
        actionLabel: 'xyzzy',
      );
      final Map<String, dynamic> json = configuration.toJson();
      expect(json['inputType'], <String, dynamic>{
        'name': 'TextInputType.text',
        'signed': null,
        'decimal': null,
      });
      expect(json['readOnly'], true);
      expect(json['obscureText'], true);
      expect(json['autocorrect'], false);
      expect(json['actionLabel'], 'xyzzy');
    });

    test('number serializes to JSON', () async {
      const TextInputConfiguration configuration = TextInputConfiguration(
        inputType: TextInputType.numberWithOptions(decimal: true),
        obscureText: true,
        autocorrect: false,
        actionLabel: 'xyzzy',
      );
      final Map<String, dynamic> json = configuration.toJson();
      expect(json['inputType'], <String, dynamic>{
        'name': 'TextInputType.number',
        'signed': false,
        'decimal': true,
      });
      expect(json['readOnly'], false);
      expect(json['obscureText'], true);
      expect(json['autocorrect'], false);
      expect(json['actionLabel'], 'xyzzy');
    });

    test('basic structure', () async {
      const TextInputType text = TextInputType.text;
      const TextInputType number = TextInputType.number;
      const TextInputType number2 = TextInputType.numberWithOptions(); // ignore: use_named_constants
      const TextInputType signed = TextInputType.numberWithOptions(signed: true);
      const TextInputType signed2 = TextInputType.numberWithOptions(signed: true);
      const TextInputType decimal = TextInputType.numberWithOptions(decimal: true);
      const TextInputType signedDecimal =
        TextInputType.numberWithOptions(signed: true, decimal: true);

      expect(text.toString(), 'TextInputType(name: TextInputType.text, signed: null, decimal: null)');
      expect(number.toString(), 'TextInputType(name: TextInputType.number, signed: false, decimal: false)');
      expect(signed.toString(), 'TextInputType(name: TextInputType.number, signed: true, decimal: false)');
      expect(decimal.toString(), 'TextInputType(name: TextInputType.number, signed: false, decimal: true)');
      expect(signedDecimal.toString(), 'TextInputType(name: TextInputType.number, signed: true, decimal: true)');

      expect(text == number, false);
      expect(number == number2, true);
      expect(number == signed, false);
      expect(signed == signed2, true);
      expect(signed == decimal, false);
      expect(signed == signedDecimal, false);
      expect(decimal == signedDecimal, false);

      expect(text.hashCode == number.hashCode, false);
      expect(number.hashCode == number2.hashCode, true);
      expect(number.hashCode == signed.hashCode, false);
      expect(signed.hashCode == signed2.hashCode, true);
      expect(signed.hashCode == decimal.hashCode, false);
      expect(signed.hashCode == signedDecimal.hashCode, false);
      expect(decimal.hashCode == signedDecimal.hashCode, false);
    });

    test('TextInputClient onConnectionClosed method is called', () async {
      // Assemble a TextInputConnection so we can verify its change in state.
      final FakeTextInputClient client = FakeTextInputClient(const TextEditingValue(text: 'test3'));
      const TextInputConfiguration configuration = TextInputConfiguration();
      TextInput.attach(client, configuration);

      expect(client.latestMethodCall, isEmpty);

      // Send onConnectionClosed message.
      final ByteData? messageBytes = const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'args': <dynamic>[1],
        'method': 'TextInputClient.onConnectionClosed',
      });
      await ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        messageBytes,
        (ByteData? _) {},
      );

      expect(client.latestMethodCall, 'connectionClosed');
    });

    test('TextInputClient performPrivateCommand method is called', () async {
      // Assemble a TextInputConnection so we can verify its change in state.
      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      const TextInputConfiguration configuration = TextInputConfiguration();
      TextInput.attach(client, configuration);

      expect(client.latestMethodCall, isEmpty);

      // Send performPrivateCommand message.
      final ByteData? messageBytes = const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'args': <dynamic>[
          1,
          jsonDecode(
              '{"action": "actionCommand", "data": {"input_context" : "abcdefg"}}')
        ],
        'method': 'TextInputClient.performPrivateCommand',
      });
      await ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        messageBytes,
        (ByteData? _) {},
      );

      expect(client.latestMethodCall, 'performPrivateCommand');
    });

    test('TextInputClient performPrivateCommand method is called with float',
        () async {
      // Assemble a TextInputConnection so we can verify its change in state.
      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      const TextInputConfiguration configuration = TextInputConfiguration();
      TextInput.attach(client, configuration);

      expect(client.latestMethodCall, isEmpty);

      // Send performPrivateCommand message.
      final ByteData? messageBytes = const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'args': <dynamic>[
          1,
          jsonDecode(
              '{"action": "actionCommand", "data": {"input_context" : 0.5}}')
        ],
        'method': 'TextInputClient.performPrivateCommand',
      });
      await ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        messageBytes,
        (ByteData? _) {},
      );

      expect(client.latestMethodCall, 'performPrivateCommand');
    });

    test(
        'TextInputClient performPrivateCommand method is called with CharSequence array',
        () async {
      // Assemble a TextInputConnection so we can verify its change in state.
      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      const TextInputConfiguration configuration = TextInputConfiguration();
      TextInput.attach(client, configuration);

      expect(client.latestMethodCall, isEmpty);

      // Send performPrivateCommand message.
      final ByteData? messageBytes = const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'args': <dynamic>[
          1,
          jsonDecode(
              '{"action": "actionCommand", "data": {"input_context" : ["abc", "efg"]}}')
        ],
        'method': 'TextInputClient.performPrivateCommand',
      });
      await ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        messageBytes,
        (ByteData? _) {},
      );

      expect(client.latestMethodCall, 'performPrivateCommand');
    });

    test(
        'TextInputClient performPrivateCommand method is called with CharSequence',
        () async {
      // Assemble a TextInputConnection so we can verify its change in state.
      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      const TextInputConfiguration configuration = TextInputConfiguration();
      TextInput.attach(client, configuration);

      expect(client.latestMethodCall, isEmpty);

      // Send performPrivateCommand message.
      final ByteData? messageBytes =
          const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'args': <dynamic>[
          1,
          jsonDecode(
              '{"action": "actionCommand", "data": {"input_context" : "abc"}}')
        ],
        'method': 'TextInputClient.performPrivateCommand',
      });
      await ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        messageBytes,
        (ByteData? _) {},
      );

      expect(client.latestMethodCall, 'performPrivateCommand');
    });

    test(
        'TextInputClient performPrivateCommand method is called with float array',
        () async {
      // Assemble a TextInputConnection so we can verify its change in state.
      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      const TextInputConfiguration configuration = TextInputConfiguration();
      TextInput.attach(client, configuration);

      expect(client.latestMethodCall, isEmpty);

      // Send performPrivateCommand message.
      final ByteData? messageBytes =
          const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'args': <dynamic>[
          1,
          jsonDecode(
              '{"action": "actionCommand", "data": {"input_context" : [0.5, 0.8]}}')
        ],
        'method': 'TextInputClient.performPrivateCommand',
      });
      await ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        messageBytes,
        (ByteData? _) {},
      );

      expect(client.latestMethodCall, 'performPrivateCommand');
    });

    test('TextInputClient showAutocorrectionPromptRect method is called',
        () async {
      // Assemble a TextInputConnection so we can verify its change in state.
      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      const TextInputConfiguration configuration = TextInputConfiguration();
      TextInput.attach(client, configuration);

      expect(client.latestMethodCall, isEmpty);

      // Send onConnectionClosed message.
      final ByteData? messageBytes =
          const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'args': <dynamic>[1, 0, 1],
        'method': 'TextInputClient.showAutocorrectionPromptRect',
      });
      await ServicesBinding.instance!.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        messageBytes,
        (ByteData? _) {},
      );

      expect(client.latestMethodCall, 'showAutocorrectionPromptRect');
    });
  });

  test('TextEditingValue.isComposingRangeValid', () async {
    // The composing range is empty.
    expect(TextEditingValue.empty.isComposingRangeValid, isFalse);

    expect(
      const TextEditingValue(text: 'test', composing: TextRange(start: 1, end: 0)).isComposingRangeValid,
      isFalse,
    );

    // The composing range is out of range for the text.
    expect(
      const TextEditingValue(text: 'test', composing: TextRange(start: 1, end: 5)).isComposingRangeValid,
      isFalse,
    );

    // The composing range is out of range for the text.
    expect(
      const TextEditingValue(text: 'test', composing: TextRange(start: -1, end: 4)).isComposingRangeValid,
      isFalse,
    );

    expect(
      const TextEditingValue(text: 'test', composing: TextRange(start: 1, end: 4)).isComposingRangeValid,
      isTrue,
    );
  });

  group('TextInputHandler', () {
    tearDown(() {
      TextInputConnection.debugResetId();
    });

    test('all handlers get called', () {
      final FakeTextInputHandler handler1 = FakeTextInputHandler();
      final FakeTextInputHandler handler2 = FakeTextInputHandler();
      TextInput.addInputHandler(handler1);
      TextInput.addInputHandler(handler2);

      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      final TextInputConnection connection = TextInput.attach(client, const TextInputConfiguration());

      final List<String> expectedMethodCalls = <String>['attach'];
      expect(handler1.methodCalls, expectedMethodCalls);
      expect(handler2.methodCalls, expectedMethodCalls);

      connection.updateConfig(const TextInputConfiguration());

      expectedMethodCalls.add('updateConfig');
      expect(handler1.methodCalls, expectedMethodCalls);
      expect(handler2.methodCalls, expectedMethodCalls);

      connection.setEditingState(TextEditingValue.empty);

      expectedMethodCalls.add('setEditingState');
      expect(handler1.methodCalls, expectedMethodCalls);
      expect(handler2.methodCalls, expectedMethodCalls);

      connection.close();

      expectedMethodCalls.add('detach');
      expect(handler1.methodCalls, expectedMethodCalls);
      expect(handler2.methodCalls, expectedMethodCalls);
    });

    test('editing value updates are delivered to other handlers', () {
      final FakeTextInputHandler handler1 = FakeTextInputHandler();
      final FakeTextInputHandler handler2 = FakeTextInputHandler();
      TextInput.addInputHandler(handler1);
      TextInput.addInputHandler(handler2);

      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      TextInput.attach(client, const TextInputConfiguration());

      handler1.updateEditingValue(TextEditingValue.empty);
      expect(handler1.methodCalls, <String>['attach']);
      expect(handler2.methodCalls, <String>['attach', 'setEditingState']);

      handler2.updateEditingValue(TextEditingValue.empty);
      expect(handler1.methodCalls, <String>['attach', 'setEditingState']);
      expect(handler2.methodCalls, <String>['attach', 'setEditingState']);
    });

    test('duplicate handlers are rejected', () {
      final FakeTextInputHandler handler = FakeTextInputHandler();
      TextInput.addInputHandler(handler);
      TextInput.addInputHandler(handler);

      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      const TextInputConfiguration configuration = TextInputConfiguration();
      TextInput.attach(client, configuration);
      expect(handler.methodCalls, <String>['attach']);
    });

    test('duplicate handlers are rejected', () {
      final FakeTextInputHandler handler1 = FakeTextInputHandler();
      TextInput.addInputHandler(handler1);
      TextInput.addInputHandler(handler1);

      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      const TextInputConfiguration configuration = TextInputConfiguration();
      TextInput.attach(client, configuration);
      expect(handler1.methodCalls, <String>['attach']);
    });
  });

  group('TextInputControl', () {
    late FakeTextChannel fakeTextChannel;

    setUp(() {
      fakeTextChannel = FakeTextChannel((MethodCall call) async {});
      TextInput.setChannel(fakeTextChannel);
    });

    tearDown(() {
      TextInput.restorePlatformInputControl();
      TextInputConnection.debugResetId();
      TextInput.setChannel(SystemChannels.textInput);
    });

    test('custom input control does not interfere with platform input', () {
      final FakeTextInputControl control = FakeTextInputControl();
      TextInput.setInputControl(control);

      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      final TextInputConnection connection = TextInput.attach(client, const TextInputConfiguration());

      fakeTextChannel.outgoingCalls.clear();

      fakeTextChannel.incoming!(MethodCall('TextInputClient.updateEditingState', <dynamic>[1, TextEditingValue.empty.toJSON()]));

      expect(client.latestMethodCall, 'updateEditingValue');
      expect(control.methodCalls, <String>['attach', 'setEditingState']);
      expect(fakeTextChannel.outgoingCalls, isEmpty);
    });

    test('custom input control receives requests', () async {
      final FakeTextInputControl control = FakeTextInputControl();
      TextInput.setInputControl(control);

      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      final TextInputConnection connection = TextInput.attach(client, const TextInputConfiguration());

      final List<String> expectedMethodCalls = <String>['attach'];
      expect(control.methodCalls, expectedMethodCalls);

      connection.show();
      expectedMethodCalls.add('show');
      expect(control.methodCalls, expectedMethodCalls);

      connection.setComposingRect(Rect.zero);
      expectedMethodCalls.add('setComposingRect');
      expect(control.methodCalls, expectedMethodCalls);

      connection.setEditableSizeAndTransform(Size.zero, Matrix4.identity());
      expectedMethodCalls.add('setEditableSizeAndTransform');
      expect(control.methodCalls, expectedMethodCalls);

      connection.setStyle(
        fontFamily: null,
        fontSize: null,
        fontWeight: null,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      expectedMethodCalls.add('setStyle');
      expect(control.methodCalls, expectedMethodCalls);

      connection.close();
      expectedMethodCalls.add('detach');
      expect(control.methodCalls, expectedMethodCalls);

      expectedMethodCalls.add('hide');
      final TestWidgetsFlutterBinding binding = TestWidgetsFlutterBinding.ensureInitialized() as TestWidgetsFlutterBinding;
      await binding.runAsync(() async {});
      await expectLater(control.methodCalls, expectedMethodCalls);
    });

    test('change input control', () async {
      final FakeTextInputControl control = FakeTextInputControl();
      TextInput.setInputControl(control);

      final FakeTextInputClient client = FakeTextInputClient(TextEditingValue.empty);
      final TextInputConnection connection = TextInput.attach(client, const TextInputConfiguration());

      TextInput.setInputControl(null);
      expect(client.latestMethodCall, 'didChangeInputControl');

      connection.show();
      expect(client.latestMethodCall, 'didChangeInputControl');
    });
  });
}

class FakeTextInputClient implements TextInputClient {
  FakeTextInputClient(this.currentTextEditingValue);

  String latestMethodCall = '';

  @override
  TextEditingValue currentTextEditingValue;

  @override
  AutofillScope? get currentAutofillScope => null;

  @override
  void performAction(TextInputAction action) {
    latestMethodCall = 'performAction';
  }

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {
    latestMethodCall = 'performPrivateCommand';
  }

  @override
  void updateEditingValue(TextEditingValue value) {
    latestMethodCall = 'updateEditingValue';
  }

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {
    latestMethodCall = 'updateFloatingCursor';
  }

  @override
  void connectionClosed() {
    latestMethodCall = 'connectionClosed';
  }

  @override
  void showAutocorrectionPromptRect(int start, int end) {
    latestMethodCall = 'showAutocorrectionPromptRect';
  }

  TextInputConfiguration get configuration => const TextInputConfiguration();

  @override
  void didChangeInputControl(TextInputControl? oldControl, TextInputControl? newControl) {
    latestMethodCall = 'didChangeInputControl';
  }
}

class FakeTextChannel implements MethodChannel {
  FakeTextChannel(this.outgoing) : assert(outgoing != null);

  Future<dynamic> Function(MethodCall) outgoing;
  Future<void> Function(MethodCall)? incoming;

  List<MethodCall> outgoingCalls = <MethodCall>[];

  @override
  BinaryMessenger get binaryMessenger => throw UnimplementedError();

  @override
  MethodCodec get codec => const JSONMethodCodec();

  @override
  Future<List<T>> invokeListMethod<T>(String method, [dynamic arguments]) => throw UnimplementedError();

  @override
  Future<Map<K, V>> invokeMapMethod<K, V>(String method, [dynamic arguments]) => throw UnimplementedError();

  @override
  Future<T> invokeMethod<T>(String method, [dynamic arguments]) async {
    final MethodCall call = MethodCall(method, arguments);
    outgoingCalls.add(call);
    return await outgoing(call) as T;
  }

  @override
  String get name => 'flutter/textinput';

  @override
  void setMethodCallHandler(Future<void> Function(MethodCall call)? handler) => incoming = handler;

  @override
  bool checkMethodCallHandler(Future<void> Function(MethodCall call)? handler) => throw UnimplementedError();


  @override
  void setMockMethodCallHandler(Future<void>? Function(MethodCall call)? handler)  => throw UnimplementedError();

  @override
  bool checkMockMethodCallHandler(Future<void> Function(MethodCall call)? handler) => throw UnimplementedError();

  void validateOutgoingMethodCalls(List<MethodCall> calls) {
    expect(outgoingCalls.length, calls.length);
    bool hasError = false;
    for (int i = 0; i < calls.length; i++) {
      final ByteData outgoingData = codec.encodeMethodCall(outgoingCalls[i]);
      final ByteData expectedData = codec.encodeMethodCall(calls[i]);
      final String outgoingString = utf8.decode(outgoingData.buffer.asUint8List());
      final String expectedString = utf8.decode(expectedData.buffer.asUint8List());

      if (outgoingString != expectedString) {
        print(
          'Index $i did not match:\n'
          '  actual:   $outgoingString\n'
          '  expected: $expectedString');
        hasError = true;
      }
    }
    if (hasError) {
      fail('Calls did not match.');
    }
  }
}

class FakeTextInputHandler extends TextInputHandler {
  final List<String> methodCalls = <String>[];

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    methodCalls.add('attach');
  }

  @override
  void detach(TextInputClient client) {
    methodCalls.add('detach');
  }

  @override
  void setEditingState(TextEditingValue value) {
    methodCalls.add('setEditingState');
  }

  @override
  void updateConfig(TextInputConfiguration configuration) {
    methodCalls.add('updateConfig');
  }
}

class FakeTextInputControl extends TextInputControl {
  final List<String> methodCalls = <String>[];

  @override
  void attach(TextInputClient client, TextInputConfiguration configuration) {
    methodCalls.add('attach');
  }

  @override
  void detach(TextInputClient client) {
    methodCalls.add('detach');
  }

  @override
  void setEditingState(TextEditingValue value) {
    methodCalls.add('setEditingState');
  }

  @override
  void updateConfig(TextInputConfiguration configuration) {
    methodCalls.add('updateConfig');
  }

  @override
  void show() {
    methodCalls.add('show');
  }

  @override
  void hide() {
    methodCalls.add('hide');
  }

  @override
  void setComposingRect(Rect rect) {
    methodCalls.add('setComposingRect');
  }

  @override
  void setEditableSizeAndTransform(Size editableBoxSize, Matrix4 transform) {
    methodCalls.add('setEditableSizeAndTransform');
  }

  @override
  void setStyle({
    required String? fontFamily,
    required double? fontSize,
    required FontWeight? fontWeight,
    required TextDirection textDirection,
    required TextAlign textAlign,
  }) {
    methodCalls.add('setStyle');
  }

  @override
  void finishAutofillContext({bool shouldSave = true}) {
    methodCalls.add('finishAutofillContext');
  }

  @override
  void requestAutofill() {
    methodCalls.add('requestAutofill');
  }
}
