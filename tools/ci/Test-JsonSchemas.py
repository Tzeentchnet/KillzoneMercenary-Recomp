# SPDX-License-Identifier: GPL-2.0-or-later

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import subprocess
import sys
from typing import Any

from jsonschema import Draft202012Validator


ROOT = pathlib.Path(__file__).resolve().parents[2]


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key {key!r}")
        result[key] = value
    return result


def load_json(path: pathlib.Path) -> Any:
    with path.open("r", encoding="utf-8") as stream:
        return json.load(stream, object_pairs_hook=reject_duplicate_keys)


def canonical_bytes(value: Any) -> bytes:
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            separators=(",", ":"),
            sort_keys=True,
        )
        + "\n"
    ).encode("utf-8")


def assert_rejected(
    validator: Draft202012Validator, instance: Any, label: str
) -> None:
    if not list(validator.iter_errors(instance)):
        raise AssertionError(f"schema accepted invalid fixture: {label}")


def tracked_json_files() -> list[pathlib.Path]:
    completed = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "*.json"],
        check=False,
        capture_output=True,
        encoding="utf-8",
    )
    if completed.returncode == 0:
        tracked = [
            ROOT / line
            for line in completed.stdout.splitlines()
            if line and not line.startswith("third_party/")
        ]
        public_config = list((ROOT / "config").glob("*.schema.json"))
        public_config += list((ROOT / "config").glob("*.example.json"))
        return sorted(set(tracked + public_config))

    excluded = {
        ".git",
        "build",
        "out",
        "third_party",
    }
    return sorted(
        path
        for path in ROOT.rglob("*.json")
        if not any(part in excluded for part in path.relative_to(ROOT).parts)
    )


def main() -> int:
    files = tracked_json_files()
    loaded = {path.relative_to(ROOT).as_posix(): load_json(path) for path in files}

    pairs = (
        (
            "config/content-pipeline.schema.json",
            "config/content-pipeline.example.json",
        ),
        (
            "config/runtime-manifest.schema.json",
            "config/runtime-manifest.example.json",
        ),
        (
            "config/generated-source-provenance.schema.json",
            "config/generated-source-provenance.example.json",
        ),
    )
    validators: dict[str, Draft202012Validator] = {}
    for schema_name, example_name in pairs:
        schema = loaded[schema_name]
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema)
        validator.validate(loaded[example_name])
        validators[schema_name] = validator

    bad_pipeline = copy.deepcopy(loaded["config/content-pipeline.example.json"])
    bad_pipeline["titleId"] = "WRONG0000"
    assert_rejected(
        validators["config/content-pipeline.schema.json"],
        bad_pipeline,
        "wrong content-pipeline title ID",
    )

    bad_manifest = copy.deepcopy(loaded["config/runtime-manifest.example.json"])
    bad_manifest["modules"][0]["path"] = "../private.elf"
    assert_rejected(
        validators["config/runtime-manifest.schema.json"],
        bad_manifest,
        "runtime-manifest path traversal",
    )
    bad_manifest = copy.deepcopy(loaded["config/runtime-manifest.example.json"])
    bad_manifest["privatePath"] = "<absolute-private-path>"
    assert_rejected(
        validators["config/runtime-manifest.schema.json"],
        bad_manifest,
        "runtime-manifest private extension",
    )

    provenance_name = "config/generated-source-provenance.example.json"
    provenance_schema = validators[
        "config/generated-source-provenance.schema.json"
    ]
    bad_provenance = copy.deepcopy(loaded[provenance_name])
    bad_provenance["generatedFiles"][0]["path"] = "../registry.c"
    assert_rejected(
        provenance_schema,
        bad_provenance,
        "generated-source provenance path traversal",
    )
    bad_provenance = copy.deepcopy(loaded[provenance_name])
    bad_provenance["generator"]["commands"][0]["arguments"][3] = (
        "C:/synthetic/module.elf"
    )
    assert_rejected(
        provenance_schema,
        bad_provenance,
        "generated-source provenance absolute command path",
    )
    bad_provenance = copy.deepcopy(loaded[provenance_name])
    bad_provenance["privateExtension"] = True
    assert_rejected(
        provenance_schema,
        bad_provenance,
        "generated-source provenance private extension",
    )

    inventory = [
        {
            "path": name,
            "sha256": hashlib.sha256(canonical_bytes(value)).hexdigest(),
        }
        for name, value in sorted(loaded.items())
    ]
    first = canonical_bytes(inventory)
    second = canonical_bytes(inventory)
    if first != second:
        raise AssertionError("JSON inventory serialization is not deterministic")
    digest = hashlib.sha256(first).hexdigest()
    print(
        f"JSON Schema/examples passed: {len(pairs)} pairs, "
        f"{len(files)} tracked JSON files; inventory SHA-256 {digest}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
