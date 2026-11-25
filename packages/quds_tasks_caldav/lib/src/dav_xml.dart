import 'dart:convert';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

const dav = 'DAV:';
const cal = 'urn:ietf:params:xml:ns:caldav';
const namespaces = 'xmlns:D="$dav" xmlns:C="$cal"';
const maxDavRows = 4096;

String xmlText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

String? xmlValue(XmlElement? element) {
  if (element == null) return null;
  if (element.childElements.isNotEmpty) {
    throw const FormatException('DAV text expected.');
  }
  return element.innerText;
}

bool named(XmlElement element, String namespace, String name) =>
    element.name.local == name && element.namespaceUri == namespace;

XmlElement? child(XmlElement parent, String namespace, String name) => _one(
  parent.childElements.where((element) => named(element, namespace, name)),
);

T? _one<T>(Iterable<T> values) {
  final iterator = values.iterator;
  if (!iterator.moveNext()) return null;
  final value = iterator.current;
  if (iterator.moveNext()) {
    throw const FormatException('Duplicate DAV element.');
  }
  return value;
}

XmlElement davRoot(List<int> bytes) {
  final source = utf8.decode(bytes);
  var depth = 0;
  var events = 0;
  for (final event in parseEvents(source)) {
    if (++events > 160000 ||
        event is XmlDoctypeEvent ||
        event is XmlProcessingEvent) {
      throw const FormatException('Unsupported DAV XML.');
    }
    if (event is XmlStartElementEvent) {
      if (event.attributes.length > 32 || depth >= 24) {
        throw const FormatException(
          'DAV XML nesting or attribute limit exceeded.',
        );
      }
      if (!event.isSelfClosing) depth++;
    } else if (event is XmlEndElementEvent) {
      depth--;
    }
  }
  return _one(XmlDocument.parse(source).childElements) ??
      (throw const FormatException('Missing DAV XML root.'));
}

int? _status(XmlElement parent) {
  final value = xmlValue(child(parent, dav, 'status'));
  if (value == null) return null;
  final match = RegExp(
    r'^HTTP/\d(?:\.\d)? ([1-5]\d\d)(?:[ \t]|$)',
  ).firstMatch(value.trim());
  if (match == null) throw const FormatException('Invalid DAV status.');
  return int.parse(match.group(1)!);
}

final class DavRow {
  DavRow(XmlElement element)
    : href = xmlValue(child(element, dav, 'href'))?.trim() ?? '',
      status = _status(element) {
    for (final propstat in element.childElements.where(
      (element) => named(element, dav, 'propstat'),
    )) {
      final status = _status(propstat);
      final prop = child(propstat, dav, 'prop');
      if (status == null || prop == null) {
        throw const FormatException('Incomplete DAV property status.');
      }
      _properties.addAll(
        prop.childElements.map((element) => (element: element, status: status)),
      );
    }
    if (href.isEmpty ||
        (status == null && childCount(element, dav, 'propstat') == 0) ||
        (status != null && childCount(element, dav, 'propstat') != 0)) {
      throw const FormatException('Incomplete DAV response.');
    }
  }

  final String href;
  final int? status;
  final _properties = <({XmlElement element, int status})>[];

  ({XmlElement element, int status})? _lookup(String namespace, String name) =>
      _one(
        _properties.where(
          (property) => named(property.element, namespace, name),
        ),
      );

  int? propertyStatus(String namespace, String name) =>
      _lookup(namespace, name)?.status;

  XmlElement? property(String namespace, String name) {
    final property = _lookup(namespace, name);
    return property != null && property.status >= 200 && property.status < 300
        ? property.element
        : null;
  }
}

int childCount(XmlElement parent, String namespace, String name) => parent
    .childElements
    .where((element) => named(element, namespace, name))
    .length;

final class DavMultistatus {
  DavMultistatus(List<int> bytes) {
    final root = davRoot(bytes);
    if (!named(root, dav, 'multistatus')) {
      throw const FormatException('Expected DAV multistatus.');
    }
    token = xmlValue(child(root, dav, 'sync-token'))?.trim();
    for (final element in root.childElements) {
      final name = element.name.local;
      if ((name == 'response' || name == 'sync-token') &&
          element.namespaceUri != dav) {
        throw const FormatException('Invalid DAV response namespace.');
      }
      if (!named(element, dav, 'response')) continue;
      if (rows.length >= maxDavRows) {
        throw const FormatException('Too many DAV responses.');
      }
      rows.add(DavRow(element));
    }
  }

  late final String? token;
  final rows = <DavRow>[];
}
