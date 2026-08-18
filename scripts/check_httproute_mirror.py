#!/usr/bin/env python3
"""Verify every internet-gateway HTTPRoute has a matching private-gateway mirror.

Rule: for any HTTPRoute attached to the "internet" Gateway, there must be a
sibling HTTPRoute (defined in the same file, as is the repo convention --
see apps/httpbin/httproute.yaml or apps-helm/jellyfin/manifests/httproute.yaml)
attached to the "private" Gateway that is otherwise identical:

  1. same `spec.rules` (backendRefs, matches, timeouts, ...) -- the private
     route must serve the same backend the same way.
  2. every desertbluffs.com hostname on the internet route must also appear
     directly on the private route (see apps/pms/httproute.yaml). A
     radoncanyon.com mirror with the same subdomain (see
     apps/httpbin/httproute.yaml) is allowed but no longer required -- split
     horizon DNS now resolves the desertbluffs.com hostname to the private
     gateway internally too.
  3. the `external-dns.alpha.kubernetes.io/hostname` annotation is exempt
     from the comparison -- it's expected to differ (or be absent) since it
     drives DNS record creation, not routing.

This is one-directional -- private-only HTTPRoutes (no internet-gateway
counterpart) are allowed, since some apps are intentionally internal-only.

Exit non-zero and print actionable errors if any mirror is missing or diverges.
"""

from __future__ import annotations

import pathlib
import sys
from typing import Any

import yaml

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
INTERNET_DOMAIN = "desertbluffs.com"
EXTERNAL_DNS_ANNOTATION = "external-dns.alpha.kubernetes.io/hostname"


def iter_httproute_files() -> list[pathlib.Path]:
    return sorted(REPO_ROOT.glob("**/httproute.yaml"))


def load_httproutes(path: pathlib.Path) -> list[dict[str, Any]]:
    docs = []
    for doc in yaml.safe_load_all(path.read_text()):
        if doc and doc.get("kind") == "HTTPRoute":
            docs.append(doc)
    return docs


def parent_gateways(doc: dict[str, Any]) -> set[str]:
    return {
        ref.get("name")
        for ref in doc.get("spec", {}).get("parentRefs", [])
    }


def subdomain(hostname: str, domain: str) -> str | None:
    suffix = f".{domain}"
    if hostname == domain:
        return ""
    if hostname.endswith(suffix):
        return hostname[: -len(suffix)]
    return None


def route_name(doc: dict[str, Any]) -> str:
    meta = doc.get("metadata", {})
    ns = meta.get("namespace")
    name = meta.get("name", "<unnamed>")
    return f"{ns}/{name}" if ns else name


def find_private_match(
    internet_doc: dict[str, Any], private_docs: list[dict[str, Any]]
) -> dict[str, Any] | None:
    """Pick the private-gateway doc whose rules match the internet doc's."""
    internet_rules = internet_doc.get("spec", {}).get("rules")
    exact = [d for d in private_docs if d.get("spec", {}).get("rules") == internet_rules]
    if exact:
        return exact[0]
    # Fall back to the only private route in the file, if unambiguous.
    if len(private_docs) == 1:
        return private_docs[0]
    return None


def check_file(path: pathlib.Path, errors: list[str]) -> None:
    docs = load_httproutes(path)
    internet_docs = [d for d in docs if "internet" in parent_gateways(d)]
    private_docs = [d for d in docs if "private" in parent_gateways(d)]

    for internet_doc in internet_docs:
        name = route_name(internet_doc)
        private_doc = find_private_match(internet_doc, private_docs)
        if private_doc is None:
            errors.append(
                f"{path}: {name} is on the internet gateway but has no "
                f"private-gateway mirror HTTPRoute in this file."
            )
            continue

        internet_hostnames = internet_doc.get("spec", {}).get("hostnames", [])
        private_hostnames = set(private_doc.get("spec", {}).get("hostnames", []))
        for hostname in internet_hostnames:
            sd = subdomain(hostname, INTERNET_DOMAIN)
            if sd is None:
                continue
            if hostname not in private_hostnames:
                errors.append(
                    f"{path}: {name} hostname {hostname} is not listed "
                    f"directly on private-gateway route {route_name(private_doc)}."
                )

        internet_rules = internet_doc.get("spec", {}).get("rules")
        private_rules = private_doc.get("spec", {}).get("rules")
        if internet_rules != private_rules:
            errors.append(
                f"{path}: {name} and its private-gateway mirror "
                f"{route_name(private_doc)} have diverging spec.rules "
                f"(backendRefs/matches must match)."
            )


def main() -> int:
    errors: list[str] = []
    for path in iter_httproute_files():
        check_file(path, errors)

    if errors:
        print("HTTPRoute mirror check failed:\n", file=sys.stderr)
        for error in errors:
            print(f"  {error}", file=sys.stderr)
        print(
            "\nAdd or fix an HTTPRoute for the private gateway with the same "
            "spec.rules as the internet-gateway route above -- see "
            "apps/httpbin/httproute.yaml or "
            "apps-helm/jellyfin/manifests/httproute.yaml for the "
            "radoncanyon.com mirror pattern, and apps/pms/httproute.yaml "
            "for also listing the desertbluffs.com hostname directly on "
            "the private-gateway route. The "
            f"{EXTERNAL_DNS_ANNOTATION} annotation is not compared and may "
            "differ.",
            file=sys.stderr,
        )
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
