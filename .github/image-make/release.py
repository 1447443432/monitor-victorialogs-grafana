#!/usr/bin/env python3
"""Create the release manifest and write the Release job summary."""

import glob
import hashlib
import json
import os


def digest(path):
    result = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


tag = os.environ["RELEASE_TAG"]
release_name = os.environ["RELEASE_NAME"]
primary = {"amd64": os.environ["TARGET_IMAGE_AMD64"], "arm64": os.environ["TARGET_IMAGE_ARM64"]}
aliyun = {"amd64": os.environ["ALIYUN_IMAGE_AMD64"], "arm64": os.environ["ALIYUN_IMAGE_ARM64"]}
source = os.environ.get("RELEASE_IMAGE_SOURCE", "primary")

base = f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/releases/download/{tag}"
images = []
for path in sorted(glob.glob("release-assets/*.tar.gz")):
    archive = os.path.basename(path)
    image_name = archive.removesuffix(f"_{tag}.tar.gz")
    archive_image_name = image_name.split("@", 1)[0].rsplit(":", 1)[0]
    architecture = next((item for item in ("amd64", "arm64") if archive_image_name == primary[item].rsplit("/", 1)[-1].split("@", 1)[0].rsplit(":", 1)[0]), "")
    if not architecture:
        raise RuntimeError(f"cannot determine architecture from archive: {archive}")
    image = aliyun[architecture] if source == "aliyun" else primary[architecture]
    images.append({
        "architecture": architecture,
        "platform": f"linux/{architecture}",
        "image": image,
        "archive": archive,
        "sha256": digest(path),
        "download_url": f"{base}/{archive}",
    })

by_architecture = {item["architecture"]: item for item in images}
release_url = f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/releases/tag/{tag}"
attachment_urls = [item["download_url"] for item in images]

# Keep the HAP payload compatible with nginx-make. The attachment_urls field is
# intentionally a JSON string because this is how the HAP Webhook field is stored.
manifest = {
    "project_name": release_name,
    "repository": os.environ["GITHUB_REPOSITORY"],
    "version": tag,
    "tag": tag,
    "release_url": release_url,
    "amd64_name": by_architecture.get("amd64", {}).get("archive", ""),
    "amd64_url": by_architecture.get("amd64", {}).get("download_url", ""),
    "amd64_sha256": by_architecture.get("amd64", {}).get("sha256", ""),
    "arm64_name": by_architecture.get("arm64", {}).get("archive", ""),
    "arm64_url": by_architecture.get("arm64", {}).get("download_url", ""),
    "arm64_sha256": by_architecture.get("arm64", {}).get("sha256", ""),
    "attachment_urls": json.dumps(attachment_urls, ensure_ascii=False),
    "commit_sha": os.environ.get("GITHUB_SHA", ""),
    "run_id": os.environ.get("GITHUB_RUN_ID", ""),
    "run_url": f"{os.environ['GITHUB_SERVER_URL']}/{os.environ['GITHUB_REPOSITORY']}/actions/runs/{os.environ.get('GITHUB_RUN_ID', '')}",
    "build_status": "success",
}
with open("release-assets/release-manifest.json", "w", encoding="utf-8") as output:
    json.dump(manifest, output, indent=2)

with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
    summary.write("# Create Release summary\n\n")
    summary.write(f"- **Repository:** `{os.environ['GITHUB_REPOSITORY']}`\n- **Tag:** `{tag}`\n\n")
    summary.write("| Architecture | Image | Archive | SHA256 |\n|---|---|---|---|\n")
    for item in images:
        summary.write(f"| `{item['architecture']}` | `{item['image']}` | [{item['archive']}]({item['download_url']}) | `{item['sha256']}` |\n")
    summary.write("\n## HAP sync\n\n")
    if os.environ.get("HAP_ENABLED") != "true":
        summary.write("HAP Webhook skipped: module is disabled.\n")
    elif not os.environ.get("HAP_WEBHOOK_URL", "").strip():
        summary.write("HAP Webhook skipped: HAP_WEBHOOK_URL is missing.\n")
    else:
        summary.write("HAP Webhook: configured; see the notification step for the request result.\n")

print("========== release manifest ==========")
print("[OK] release manifest created")
print(f"tag={tag}")
print(f"archives={len(images)}")
