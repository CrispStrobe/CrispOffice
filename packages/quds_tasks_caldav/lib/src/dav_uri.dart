bool safeDavUri(Uri uri, Uri origin) =>
    uri.isAbsolute &&
    uri.hasAuthority &&
    uri.host.isNotEmpty &&
    uri.scheme == origin.scheme &&
    uri.origin == origin.origin &&
    uri.userInfo.isEmpty &&
    !uri.hasQuery &&
    !uri.hasFragment &&
    uri.toString().length <= 16384 &&
    uri.pathSegments.every(
      (segment) =>
          segment != '.' &&
          segment != '..' &&
          !segment.contains(RegExp(r'[\x00-\x1f\x7f/\\]')),
    );

Uri? davHref(Uri base, String href) {
  // Validate the raw href before URI resolution can normalize path traversal.
  if (href.isEmpty ||
      href.length > 16384 ||
      href.contains(RegExp(r'[\x00-\x20\x7f\\]|%(?![0-9a-fA-F]{2})'))) {
    return null;
  }
  try {
    if (href.split('/').any((segment) {
      final decoded = Uri.decodeComponent(segment);
      return decoded == '.' || decoded == '..';
    })) {
      return null;
    }
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
  final reference = Uri.tryParse(href);
  if (reference == null || (!reference.isAbsolute && !href.startsWith('/'))) {
    return null;
  }
  final uri = base.resolveUri(reference);
  return safeDavUri(uri, base) ? uri : null;
}

Uri collectionUri(Uri uri) =>
    uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');

bool directMember(Uri collection, Uri resource) {
  final parent = collectionUri(collection).path;
  if (!resource.path.startsWith(parent)) return false;
  final suffix = resource.path.substring(parent.length);
  return suffix.isNotEmpty && !suffix.contains('/');
}

Uri withoutTrailingSlash(Uri uri) => uri.path.endsWith('/')
    ? uri.replace(path: uri.path.substring(0, uri.path.length - 1))
    : uri;
