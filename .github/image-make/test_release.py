#!/usr/bin/env python3
"""Small smoke test for release manifest source selection and digest references."""

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


SCRIPT = Path(__file__).with_name("release.py")


def run_case(source):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        assets = root / "release-assets"
        assets.mkdir()
        (assets / "image-amd64_1.0.0.tar.gz").write_bytes(b"test-image")
        environment = os.environ.copy()
        environment.update({
            "RELEASE_TAG": "1.0.0",
            "RELEASE_NAME": "test",
            "TARGET_IMAGE_AMD64": "registry.example.com/project/image-amd64@sha256:abc",
            "TARGET_IMAGE_ARM64": "registry.example.com/project/image-arm64:1.0.0",
            "ALIYUN_IMAGE_AMD64": "registry.example.com/aliyun/image-amd64:1.0.0",
            "ALIYUN_IMAGE_ARM64": "registry.example.com/aliyun/image-arm64:1.0.0",
            "RELEASE_IMAGE_SOURCE": source,
            "GITHUB_SERVER_URL": "https://github.com",
            "GITHUB_REPOSITORY": "example/repo",
            "GITHUB_STEP_SUMMARY": str(root / "summary.md"),
            "HAP_ENABLED": "false",
        })
        subprocess.run([sys.executable, str(SCRIPT)], cwd=root, env=environment, check=True, capture_output=True, text=True)
        manifest = json.loads((assets / "release-manifest.json").read_text(encoding="utf-8"))
        summary = (root / "summary.md").read_text(encoding="utf-8")
        return summary, manifest["build_status"]


primary_summary, primary_status = run_case("primary")
aliyun_summary, aliyun_status = run_case("aliyun")
assert "image-amd64@sha256:abc" in primary_summary
assert "aliyun/image-amd64:1.0.0" in aliyun_summary
assert primary_status == aliyun_status == "success"
print("release manifest smoke test: ok")
