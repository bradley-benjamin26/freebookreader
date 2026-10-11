import 'dart:convert';
import 'dart:io';

/// Reads a JSON fixture from test/fixtures (tests run from the package root).
dynamic loadJson(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

String loadFixtureText(String name) =>
    File('test/fixtures/$name').readAsStringSync();
