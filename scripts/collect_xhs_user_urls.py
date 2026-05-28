#!/usr/bin/env python3
"""Collect Xiaohongshu note/video URLs from a user profile page."""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlencode, urljoin, urlparse


XHS_ORIGIN = "https://www.xiaohongshu.com"
NOTE_PATH_RE = re.compile(r"^/(?:explore|discovery/item)/([^/?#]+)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Open a Xiaohongshu user profile, scroll it, and write note/video URLs."
    )
    parser.add_argument("profile_url", help="Xiaohongshu user profile URL.")
    parser.add_argument("-o", "--output", default="urls.txt", help="Output file. Default: urls.txt")
    parser.add_argument(
        "--profile-dir",
        default=".browser-profiles/xhs",
        help="Persistent browser profile directory. Default: .browser-profiles/xhs",
    )
    parser.add_argument(
        "--all-notes",
        action="store_true",
        help="Collect all note URLs instead of only notes reported as videos by XHS JSON responses.",
    )
    parser.add_argument("--max-scrolls", type=int, default=80, help="Maximum scroll rounds. Default: 80")
    parser.add_argument(
        "--scroll-wait",
        type=float,
        default=1.2,
        help="Seconds to wait after each scroll. Default: 1.2",
    )
    parser.add_argument(
        "--stable-rounds",
        type=int,
        default=4,
        help="Stop after this many scrolls with no new URLs or height change. Default: 4",
    )
    parser.add_argument(
        "--headed",
        action="store_true",
        help="Show the browser. Useful for the first run if login or verification is required.",
    )
    parser.add_argument(
        "--login-wait",
        type=int,
        default=0,
        help="Seconds to wait after opening the page before collecting. Useful with --headed.",
    )
    parser.add_argument(
        "--browser-channel",
        default="chrome",
        help="Playwright browser channel, for example chrome or msedge. Use empty string for bundled Chromium.",
    )
    parser.add_argument(
        "--append",
        action="store_true",
        help="Append to the output file and de-duplicate with existing URLs.",
    )
    return parser.parse_args()


def note_url(note_id: str, xsec_token: str | None = None, source: str = "pc_user") -> str:
    query: dict[str, str] = {}
    if xsec_token:
        query["xsec_token"] = xsec_token
        query["xsec_source"] = source
    suffix = f"?{urlencode(query)}" if query else ""
    return f"{XHS_ORIGIN}/explore/{note_id}{suffix}"


def normalize_note_href(href: str, base_url: str) -> str | None:
    if not href:
        return None
    absolute = urljoin(base_url, href)
    parsed = urlparse(absolute)
    if not parsed.netloc.endswith("xiaohongshu.com"):
        return None
    match = NOTE_PATH_RE.match(parsed.path)
    if not match:
        return None

    note_id = match.group(1)
    query = parse_qs(parsed.query)
    xsec_token = query.get("xsec_token", [None])[0]
    xsec_source = query.get("xsec_source", ["pc_user"])[0]
    return note_url(note_id, xsec_token, xsec_source)


def walk_json(value: Any):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk_json(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk_json(child)


def note_type(raw: dict[str, Any]) -> str:
    for key in ("type", "note_type", "card_type"):
        value = raw.get(key)
        if isinstance(value, str):
            return value.lower()
    card = raw.get("note_card")
    if isinstance(card, dict):
        return note_type(card)
    return ""


def collect_notes_from_json(data: Any, include_all: bool) -> list[str]:
    urls: list[str] = []
    seen_ids: set[str] = set()

    for obj in walk_json(data):
        note_id = obj.get("note_id") or obj.get("id")
        if not isinstance(note_id, str) or note_id in seen_ids:
            continue

        raw_type = note_type(obj)
        card = obj.get("note_card")
        if isinstance(card, dict) and not raw_type:
            raw_type = note_type(card)

        if not include_all and raw_type and raw_type != "video":
            continue
        if not include_all and not raw_type:
            continue

        xsec_token = obj.get("xsec_token")
        if not isinstance(xsec_token, str) and isinstance(card, dict):
            xsec_token = card.get("xsec_token")
        if not isinstance(xsec_token, str):
            xsec_token = None

        seen_ids.add(note_id)
        urls.append(note_url(note_id, xsec_token))

    return urls


def extract_dom_urls(page: Any, include_all: bool) -> list[str]:
    script = """
    ({ includeAll }) => {
      const anchors = Array.from(document.querySelectorAll('a[href]'));
      const isVideoCard = (anchor) => {
        if (includeAll) return true;
        const card = anchor.closest('[class*="note"], [class*="card"], section, li, div') || anchor;
        const text = (card.innerText || '').toLowerCase();
        const html = (card.innerHTML || '').toLowerCase();
        return text.includes('视频') ||
          text.includes('播放') ||
          html.includes('play') ||
          html.includes('video') ||
          html.includes('volume');
      };
      return anchors
        .filter(isVideoCard)
        .map((anchor) => anchor.getAttribute('href'))
        .filter(Boolean);
    }
    """
    hrefs = page.evaluate(script, {"includeAll": include_all})
    return [url for url in (normalize_note_href(href, page.url) for href in hrefs) if url]


def write_urls(path: Path, urls: list[str], append: bool) -> None:
    existing: list[str] = []
    if append and path.exists():
        existing = [
            line.strip()
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]

    merged = list(dict.fromkeys(existing + urls))
    path.write_text("\n".join(merged) + ("\n" if merged else ""), encoding="utf-8")


def main() -> int:
    args = parse_args()

    try:
        from playwright.sync_api import sync_playwright
    except ModuleNotFoundError:
        print("Missing dependency: playwright. Run collect-xhs-user-urls.sh to install it.", file=sys.stderr)
        return 2

    output = Path(args.output)
    profile_dir = Path(args.profile_dir)
    profile_dir.mkdir(parents=True, exist_ok=True)

    include_all = args.all_notes
    collected: dict[str, str] = {}
    api_hits = 0
    last_page_url = ""
    last_page_title = ""
    last_body_text = ""

    def add_urls(urls: list[str], source: str) -> int:
        before = len(collected)
        for url in urls:
            collected.setdefault(url, source)
        return len(collected) - before

    with sync_playwright() as playwright:
        launch_options: dict[str, Any] = {
            "headless": not args.headed,
            "viewport": {"width": 1440, "height": 1000},
            "locale": "zh-CN",
            "args": ["--disable-blink-features=AutomationControlled"],
        }
        if args.browser_channel:
            launch_options["channel"] = args.browser_channel

        context = playwright.chromium.launch_persistent_context(str(profile_dir), **launch_options)
        page = context.new_page()

        def handle_response(response: Any) -> None:
            nonlocal api_hits
            if "xiaohongshu.com/api/" not in response.url and "/api/sns/" not in response.url:
                return
            content_type = response.headers.get("content-type", "")
            if "json" not in content_type:
                return
            try:
                data = response.json()
            except Exception:
                try:
                    data = json.loads(response.text())
                except Exception:
                    return
            urls = collect_notes_from_json(data, include_all=include_all)
            if urls:
                api_hits += 1
                new_count = add_urls(urls, "api")
                if new_count:
                    print(f"Captured {new_count} new URL(s) from API responses; total={len(collected)}")

        page.on("response", handle_response)
        page.goto(args.profile_url, wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(3000)
        if args.login_wait > 0:
            print(f"Waiting {args.login_wait}s before collecting; use the browser window if needed.")
            page.wait_for_timeout(args.login_wait * 1000)

        current_url = page.url
        title = page.title()
        body_text = page.locator("body").inner_text(timeout=5000)[:500]
        if "/website-login/error" in current_url or "安全限制" in title or "IP at risk" in body_text:
            context.close()
            print("Xiaohongshu returned a security restriction page.", file=sys.stderr)
            print(f"URL: {current_url}", file=sys.stderr)
            print(f"Title: {title}", file=sys.stderr)
            if body_text.strip():
                print(body_text.strip(), file=sys.stderr)
            return 1

        stable = 0
        last_height = 0
        last_count = len(collected)

        for index in range(args.max_scrolls):
            dom_new = add_urls(extract_dom_urls(page, include_all=include_all), "dom")
            if dom_new:
                print(f"Captured {dom_new} new URL(s) from DOM; total={len(collected)}")

            height = page.evaluate("() => document.body.scrollHeight")
            page.evaluate("() => window.scrollTo(0, document.body.scrollHeight)")
            page.wait_for_timeout(int(args.scroll_wait * 1000))

            next_height = page.evaluate("() => document.body.scrollHeight")
            count = len(collected)
            if next_height == last_height and count == last_count:
                stable += 1
            else:
                stable = 0
            last_height = next_height
            last_count = count

            if stable >= args.stable_rounds:
                print(f"Stopping after {index + 1} scroll(s); page looks stable.")
                break

        add_urls(extract_dom_urls(page, include_all=include_all), "dom")
        last_page_url = page.url
        last_page_title = page.title()
        last_body_text = page.locator("body").inner_text(timeout=5000)[:500]
        context.close()

    urls = list(collected.keys())
    if not urls:
        print(
            "No URLs were collected. If the profile requires login or verification, "
            "rerun with --headed and complete it in the opened browser.",
            file=sys.stderr,
        )
        if last_page_url:
            print(f"Last URL: {last_page_url}", file=sys.stderr)
        if last_page_title:
            print(f"Last title: {last_page_title}", file=sys.stderr)
        if last_body_text.strip():
            print(last_body_text.strip(), file=sys.stderr)
        return 1

    write_urls(output, urls, append=args.append)

    print(f"Wrote {len(urls)} URL(s) to {output}")
    if not include_all and api_hits == 0:
        print(
            "Warning: no XHS JSON API responses were captured; video filtering used DOM heuristics only.",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
