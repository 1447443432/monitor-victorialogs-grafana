#!/usr/bin/env python3
"""Resolve image workflow configuration and write GitHub outputs/summary."""

import json
import os
import re


def load_file(path):
    values = {}
    if not os.path.exists(path):
        return values
    with open(path, encoding="utf-8") as stream:
        for raw in stream:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip("\"'")
    return values


config = load_file(os.environ.get("CONFIG_FILE", ".image-build.env"))
event = os.environ.get("EVENT_NAME", "push")


def value(key, input_key=None, variable_key=None, default=""):
    if event != "push" and input_key and os.environ.get(input_key, "").strip():
        return os.environ[input_key].strip()
    if variable_key and os.environ.get(variable_key, "").strip():
        return os.environ[variable_key].strip()
    return config.get(key, default).strip()


def image_name(reference):
    """Return the archive-safe image name without registry, tag, or digest."""
    name = reference.rsplit("/", 1)[-1].split("@", 1)[0]
    return name.rsplit(":", 1)[0]


if event != "push":
    tag = os.environ.get("INPUT_TAG", "").strip() or "latest"
else:
    tag = value("IMAGE_TAG", None, "VAR_IMAGE_TAG", "latest")
tag_valid = bool(re.fullmatch(r"[A-Za-z0-9._-]+", tag))
repository_name = os.environ.get("GITHUB_REPOSITORY", "image").rsplit("/", 1)[-1]
release_name = value("RELEASE_NAME", None, "VAR_RELEASE_NAME", repository_name)
base_amd64 = value("BASE_IMAGE_AMD64", None, "VAR_BASE_IMAGE_AMD64")
base_arm64 = value("BASE_IMAGE_ARM64", None, "VAR_BASE_IMAGE_ARM64")
target_amd64 = value("TARGET_IMAGE_AMD64", "INPUT_TARGET_IMAGE_AMD64", "VAR_TARGET_IMAGE_AMD64")
target_arm64 = value("TARGET_IMAGE_ARM64", "INPUT_TARGET_IMAGE_ARM64", "VAR_TARGET_IMAGE_ARM64")
aliyun_registry = value("ALIYUN_REGISTRY", None, "VAR_ALIYUN_REGISTRY")
aliyun_amd64 = value("ALIYUN_IMAGE_AMD64", "INPUT_ALIYUN_IMAGE_AMD64", "VAR_ALIYUN_IMAGE_AMD64")
aliyun_arm64 = value("ALIYUN_IMAGE_ARM64", "INPUT_ALIYUN_IMAGE_ARM64", "VAR_ALIYUN_IMAGE_ARM64")
aliyun_amd64 = aliyun_amd64 or target_amd64
aliyun_arm64 = aliyun_arm64 or target_arm64
dockerfile = config.get("DOCKERFILE", "Dockerfile").strip()
build_context = config.get("BUILD_CONTEXT", ".").strip()
alpine_mirror = config.get("ALPINE_MIRROR", "https://mirrors.aliyun.com/alpine").strip()
alpine_version = config.get("ALPINE_VERSION", "3.23").strip()
architecture_selection = os.environ.get("WORKFLOW_ARCHITECTURES", "").strip() or config.get("ARCHITECTURES", "all").strip()
architectures = {
    "amd64": ["amd64"],
    "arm64": ["arm64"],
    "all": ["amd64", "arm64"],
}.get(architecture_selection, [])
aliyun_enabled = value("ENABLE_ALIYUN_PUSH", None, "VAR_ENABLE_ALIYUN_PUSH", "true").lower() == "true"
release_enabled = value("ENABLE_RELEASE", "INPUT_CREATE_RELEASE", "VAR_ENABLE_RELEASE", "true").lower() == "true"
hap_enabled = value("ENABLE_HAP_WEBHOOK", "INPUT_NOTIFY_HAP", "VAR_ENABLE_HAP_WEBHOOK", "true").lower() == "true"

selected = set(architectures)
primary_missing = [
    name for architecture, name, item in (
        ("amd64", "TARGET_IMAGE_AMD64", target_amd64),
        ("arm64", "TARGET_IMAGE_ARM64", target_arm64),
    ) if architecture in selected and not item
]
selected_primary_names = [
    image_name(item) for architecture, item in (
        ("amd64", target_amd64),
        ("arm64", target_arm64),
    ) if architecture in selected and item
]
duplicate_primary_names = len(selected_primary_names) != len(set(selected_primary_names))
primary = bool(architectures) and not primary_missing and not duplicate_primary_names
aliyun_user = os.environ.get("ALIYUN_USERNAME", "").strip()
aliyun_password = os.environ.get("ALIYUN_PASSWORD", "").strip()
aliyun_missing = [name for name, item in (
    ("ALIYUN_REGISTRY", aliyun_registry),
    ("ALIYUN_USERNAME", aliyun_user),
    ("ALIYUN_PASSWORD", aliyun_password),
) if not item]
aliyun_missing.extend(
    name for architecture, name, item in (
        ("amd64", "ALIYUN_IMAGE_AMD64", aliyun_amd64),
        ("arm64", "ALIYUN_IMAGE_ARM64", aliyun_arm64),
    ) if architecture in selected and not item
)
aliyun_configured = not aliyun_missing and primary
base = all(item for architecture, item in (("amd64", base_amd64), ("arm64", base_arm64)) if architecture in selected)
build_configuration_ready = primary and base and bool(architectures) and tag_valid
valid_operations = ("auto", "build-release", "pull-release", "build-push-release")
push_operation = value("PUSH_OPERATION", None, "VAR_PUSH_OPERATION", "auto").lower()
requested_operation = os.environ.get("OPERATION", "build-release")
if event == "push" and requested_operation == "auto":
    if push_operation == "auto":
        operation = "build-push-release" if aliyun_enabled and aliyun_configured else "build-release"
    elif push_operation in valid_operations[1:]:
        operation = push_operation
    else:
        operation = "invalid"
else:
    operation = requested_operation
can_push_aliyun = operation == "build-push-release" and aliyun_enabled and aliyun_configured
can_pull_aliyun = operation == "pull-release" and aliyun_configured
can_build = build_configuration_ready and (
    operation in ("build-release", "build-push-release")
    and (operation != "build-push-release" or can_push_aliyun)
)
can_package = release_enabled and operation in ("build-release", "build-push-release", "pull-release") and (can_pull_aliyun if operation == "pull-release" else can_build)
can_release = can_package

reasons = []
if event == "push" and requested_operation == "auto":
    if push_operation not in valid_operations:
        reasons.append("Invalid PUSH_OPERATION; expected auto, build-release, pull-release or build-push-release.")
    elif push_operation == "auto" and operation == "build-push-release":
        reasons.append("Push event selected build-push-release; Aliyun push configuration is complete.")
    elif push_operation == "auto" and aliyun_enabled:
        reasons.append("Push event selected build-release; Aliyun push configuration is incomplete, so the build continues without Aliyun Push.")
    elif push_operation == "auto":
        reasons.append("Push event selected build-release; Aliyun Push is disabled.")
    else:
        reasons.append(f"Push event selected {operation} from PUSH_OPERATION.")
if operation == "pull-release" and not can_pull_aliyun:
    reasons.append("Aliyun pull skipped; missing: " + ", ".join(aliyun_missing))
elif operation == "build-push-release" and not aliyun_enabled:
    reasons.append("Aliyun push skipped; module is disabled.")
elif operation == "build-push-release" and not can_push_aliyun:
    reasons.append("Aliyun push skipped; missing: " + ", ".join(aliyun_missing))
if not primary:
    reasons.append("Build skipped; missing primary image names: " + ", ".join(primary_missing))
if duplicate_primary_names:
    reasons.append("Build skipped; selected architecture image names must be different.")
if not architectures:
    reasons.append("Build skipped; architectures must be amd64, arm64 or all.")
if not base:
    reasons.append("Build skipped; BASE_IMAGE_AMD64 or BASE_IMAGE_ARM64 is missing.")
if not tag_valid:
    reasons.append("Build skipped; tag may contain only letters, numbers, '.', '_' or '-'.")
if release_enabled and can_release:
    reasons.append("GitHub Release: enabled.")
if not os.environ.get("HAP_WEBHOOK_URL", "").strip() or not hap_enabled:
    reasons.append("HAP Webhook skipped; disabled or HAP_WEBHOOK_URL is missing.")
else:
    reasons.append("HAP Webhook: configured and will be notified after Release.")


def status(ok, missing=""):
    return "ready" if ok else "skipped: " + missing


with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as summary:
    summary.write("# Image Make configuration\n\n")
    summary.write(f"- **Operation:** `{operation}`\n- **Release name:** `{release_name}`\n- **Release tag:** `{tag}`\n")
    if event == "push":
        summary.write(f"- **Push operation setting:** `{push_operation}`\n")
    summary.write(f"- **Dockerfile:** `{dockerfile}`\n- **Build context:** `{build_context}`\n\n")
    summary.write("| Module | Status | Details |\n|---|---|---|\n")
    summary.write(f"| Build | **{status(can_build)}** | architectures: `{', '.join(architectures) or 'invalid'}`, bases: `{base_amd64 or 'missing'}` / `{base_arm64 or 'missing'}` |\n")
    primary_reason = ", ".join(primary_missing) or ("duplicate image names" if duplicate_primary_names else "")
    summary.write(f"| Primary image names | **{status(primary, primary_reason)}** | `{target_amd64 or 'missing'}` / `{target_arm64 or 'missing'}` |\n")
    aliyun_status = "ready" if can_push_aliyun or can_pull_aliyun else "not selected"
    if operation in ("build-push-release", "pull-release") and not (can_push_aliyun or can_pull_aliyun):
        aliyun_status = status(False, ", ".join(aliyun_missing))
    summary.write(f"| Aliyun image | **{aliyun_status}** | `{aliyun_registry}` |\n")
    summary.write(f"| GitHub Release | **{status(can_release)}** | enabled: `{str(release_enabled).lower()}` |\n")
    summary.write(f"| HAP Webhook | **{'ready' if hap_enabled and os.environ.get('HAP_WEBHOOK_URL', '').strip() else 'skipped'}** | enabled: `{str(hap_enabled).lower()}` |\n\n")
    summary.write("## Decisions and skip reasons\n\n")
    summary.write("\n".join(f"- {item}" for item in reasons) + "\n")

outputs = {
    "operation": operation, "push_operation": push_operation,
    "tag": tag, "release_name": release_name, "architectures": json.dumps(architectures),
    "base_image_amd64": base_amd64, "base_image_arm64": base_arm64,
    "target_image_amd64": target_amd64, "target_image_arm64": target_arm64,
    "aliyun_image_amd64": aliyun_amd64, "aliyun_image_arm64": aliyun_arm64,
    "release_image_source": "aliyun" if operation in ("pull-release", "build-push-release") else "primary",
    "aliyun_registry": aliyun_registry,
    "aliyun_push_enabled": str(can_push_aliyun).lower(), "aliyun_pull_enabled": str(can_pull_aliyun).lower(),
    "release_enabled": str(release_enabled).lower(), "hap_enabled": str(hap_enabled).lower(),
    "dockerfile": dockerfile, "build_context": build_context,
    "alpine_mirror": alpine_mirror, "alpine_version": alpine_version,
    "can_primary": str(primary).lower(), "can_aliyun": str(can_push_aliyun).lower(),
    "can_build": str(can_build).lower(), "can_package": str(can_package).lower(),
    "can_release": str(can_release).lower(),
}
with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
    for key, item in outputs.items():
        output.write(f"{key}={item}\n")

print("========== configuration result ==========")
print("[OK] configuration resolved")
print(f"operation={operation}")
if event == "push":
    print(f"push_operation={push_operation}")
print(f"tag={tag}")
print(f"build={'ready' if can_build else 'skipped'}")
print(f"aliyun_push={'ready' if can_push_aliyun else 'skipped'}")
print(f"release={'ready' if can_release else 'skipped'}")
