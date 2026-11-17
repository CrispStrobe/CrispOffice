#!/usr/bin/env python3
"""Independently check the three bounded ODF fixtures emitted by Dart tests.

Uses Python's ZIP reader and ElementTree rather than Quds XML/text readers.
This checks package members, XML well-formedness, known paragraph text and the
combined-indent regression. It is not an ODF schema or rendering validator.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET
import zipfile

NS = {
    "office": "urn:oasis:names:tc:opendocument:xmlns:office:1.0",
    "text": "urn:oasis:names:tc:opendocument:xmlns:text:1.0",
    "style": "urn:oasis:names:tc:opendocument:xmlns:style:1.0",
    "fo": "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0",
}
T = "{" + NS["text"] + "}"
EXPECTED = {
    "word-text.odt": {
        "mime": "application/vnd.oasis.opendocument.text",
        "paragraphs": ["  A\tB  C\nD "],
    },
    "slide-text.odp": {
        "mime": "application/vnd.oasis.opendocument.presentation",
        "paragraphs": [" Head\tA  B ", "", "Tail ", "  Cell\tend ", "  Note\tend "],
    },
    "word-indents.odt": {
        "mime": "application/vnd.oasis.opendocument.text",
        "paragraphs": ["Body"],
        "indent": "-18.00pt",
    },
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def paragraph_text(paragraph: ET.Element) -> str:
    """Apply ODF literal-whitespace collapse to these span/text fixtures.

    Raw character-data segments are merged across span boundaries first.
    Explicit whitespace elements stay separate until literal collapse is done.
    The fixtures intentionally contain no notes, fields or nested drawing text
    inside a paragraph; this is not a general-purpose ODF consumer.
    """
    tokens: list[tuple[str, str]] = []

    def raw(value: str | None) -> None:
        if not value:
            return
        if tokens and tokens[-1][0] == "raw":
            tokens[-1] = ("raw", tokens[-1][1] + value)
        else:
            tokens.append(("raw", value))

    def visit(node: ET.Element) -> None:
        if node.tag == T + "s":
            count = int(node.get(T + "c", "1"))
            if not 0 <= count <= 65536:
                raise ValueError("Unexpected fixture whitespace count")
            tokens.append(("explicit", " " * count))
        elif node.tag == T + "tab":
            tokens.append(("explicit", "\t"))
        elif node.tag == T + "line-break":
            tokens.append(("explicit", "\n"))
        elif node.tag in {T + name for name in ("p", "h", "span", "a")}:
            raw(node.text)
            for child in node:
                visit(child)
                raw(child.tail)
        else:
            raise ValueError(f"Unexpected element in fixture paragraph: {node.tag}")

    visit(paragraph)
    collapsed = [
        (kind, re.sub(r"[ \t\r\n]+", " ", value) if kind == "raw" else value)
        for kind, value in tokens
    ]
    if collapsed and collapsed[0][0] == "raw":
        collapsed[0] = ("raw", collapsed[0][1].lstrip(" "))
    if collapsed and collapsed[-1][0] == "raw":
        collapsed[-1] = ("raw", collapsed[-1][1].rstrip(" "))
    return "".join(value for _, value in collapsed)


def verify_fixture(path: Path, expected: dict) -> dict:
    before = path.read_bytes()
    with zipfile.ZipFile(path) as package:
        members = package.infolist()
        if not members or members[0].filename != "mimetype":
            raise ValueError(f"{path.name}: mimetype is not the first ZIP member")
        if members[0].compress_type != zipfile.ZIP_STORED:
            raise ValueError(f"{path.name}: mimetype ZIP member is compressed")
        if package.read("mimetype").decode("ascii") != expected["mime"]:
            raise ValueError(f"{path.name}: incorrect mimetype")
        if package.testzip() is not None:
            raise ValueError(f"{path.name}: ZIP CRC failure")
        xml = {}
        for name in ("content.xml", "styles.xml", "meta.xml", "META-INF/manifest.xml"):
            payload = package.read(name)
            # ElementTree rejects duplicate attributes, which Quds's low-level
            # in-memory node reader does not independently establish.
            xml[name] = (ET.fromstring(payload), digest(payload))
    content = xml["content.xml"][0]
    paragraphs = [
        paragraph_text(node)
        for node in content.iter()
        if node.tag in (T + "p", T + "h")
    ]
    if paragraphs != expected["paragraphs"]:
        raise ValueError(f"{path.name}: paragraph text differs: {paragraphs!r}")
    indent = None
    if "indent" in expected:
        properties = content.findall(".//style:paragraph-properties", NS)
        if len(properties) != 1:
            raise ValueError(f"{path.name}: expected one paragraph-property style")
        indent = properties[0].get("{" + NS["fo"] + "}text-indent")
        if indent != expected["indent"]:
            raise ValueError(f"{path.name}: incorrect hanging indent: {indent!r}")
    if path.read_bytes() != before:
        raise ValueError(f"{path.name}: fixture changed during verification")
    return {
        "file": path.name,
        "sha256": digest(before),
        "bytes": len(before),
        "mimetype": expected["mime"],
        "first_member_uncompressed_mimetype": True,
        "xml_sha256": {name: value[1] for name, value in xml.items()},
        "xml_well_formed": True,
        "paragraphs": paragraphs,
        "paragraph_text_matches": True,
        "indent": indent,
        "input_unchanged": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    receipt = {
        "started_at_utc": datetime.now(timezone.utc).isoformat(),
        "script_sha256": digest(Path(__file__).read_bytes()),
        "python": sys.version,
        "github_actions_used": False,
        "scope": "ZIP structure, XML well-formedness, known text semantics and hanging indent",
        "not_claimed": "ODF schema conformance, native-model roundtrip or visual rendering parity",
        "fixtures": [],
        "status": "running",
    }
    try:
        for filename, expected in EXPECTED.items():
            receipt["fixtures"].append(verify_fixture(args.directory / filename, expected))
        receipt["status"] = "passed"
    except Exception as error:
        receipt["status"] = "failed"
        receipt["error"] = str(error)
    receipt["finished_at_utc"] = datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps({"status": receipt["status"], "fixtures": len(receipt["fixtures"]), "receipt": str(args.output)}))
    return 0 if receipt["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
