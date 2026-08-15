#!/usr/bin/env python3
"""Verify every internet-gateway HTTPRoute hostname has a private mirror.

Rule: any hostname on the "internet" Gateway (*.desertbluffs.com) must have a
matching hostname on the "private" Gateway (*.radoncanyon.com) with the same
subdomain. This is one-directional -- private-only hosts (radoncanyon.com
without a desertbluffs.com counterpart) are allowed, since some apps are
intentionally internal-only.

Exit non-zero and print actionable errors if any mirror is missing.
"""

from __future__ import annotations

import pathlib
import sys

import yaml

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
INTERNET_DOMAIN = "desertbluffs.com"
PRIVATE_DOMAIN = "radoncanyon.com"
GATEWAY_NAMES = {"internet": INTERNET_DOMAIN, "private": PRIVATE_DOMAIN}


def iter_httproute_files() -> list[pathlib.Path]:
    return sorted(REPO_ROOT.glob("**/httproute.yaml"))


def hostnames_by_gateway(paths: list[pathlib.Path]) -> dict[str, set[str]]:
    """Map gateway name -> set of hostnames attached to it, across all files."""
    result: dict[str, set[str]] = {name: set() for name in GATEWAY_NAMES}
    for path in paths:
        text = path.read_text()
        for doc in yaml.safe_load_all(text):
            if not doc or doc.get("kind") != "HTTPRoute":
                continue
            spec = doc.get("spec", {})
            hostnames = spec.get("hostnames", [])
            for parent_ref in spec.get("parentRefs", []):
                gw_name = parent_ref.get("name")
                if gw_name in GATEWAY_NAMES:
                    result[gw_name].update(hostnames)
    return result


def subdomain(hostname: str, domain: str) -> str | None:
    suffix = f".{domain}"
    if hostname == domain or hostname.endswith(suffix):
        return hostname[: -len(suffix)] if hostname.endswith(suffix) else ""
    return None


def main() -> int:
    paths = iter_httproute_files()
    by_gateway = hostnames_by_gateway(paths)

    private_subdomains = {
        sd
        for h in by_gateway["private"]
        if (sd := subdomain(h, PRIVATE_DOMAIN)) is not None
    }

    missing = []
    for hostname in sorted(by_gateway["internet"]):
        sd = subdomain(hostname, INTERNET_DOMAIN)
        if sd is None:
            continue
        if sd not in private_subdomains:
            expected = f"{sd}.{PRIVATE_DOMAIN}" if sd else PRIVATE_DOMAIN
            missing.append((hostname, expected))

    if missing:
        print("HTTPRoute mirror check failed:\n", file=sys.stderr)
        for hostname, expected in missing:
            print(
                f"  {hostname} is on the internet gateway but has no "
                f"private-gateway mirror ({expected} not found).",
                file=sys.stderr,
            )
        print(
            "\nAdd an HTTPRoute for the private gateway with the missing "
            "hostname(s) above -- see apps/httpbin/httproute.yaml or "
            "apps-helm/jellyfin/manifests/httproute.yaml for the pattern.",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
