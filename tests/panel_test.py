"""Smoke-test the panel with a mocked Mallard bridge; optionally save a preview."""
from pathlib import Path
import sys
from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parent.parent
with sync_playwright() as p:
    browser = p.chromium.launch(headless=True, args=["--no-sandbox"])
    page = browser.new_page(viewport={"width": 360, "height": 360}, device_scale_factor=2)
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.add_init_script("""
        window.messages = [];
        window.handlers = {};
        window.panel = {
            on: (name, fn) => { window.handlers[name] = fn; },
            post: (name, data) => { window.messages.push({name, data}); }
        };
    """)
    page.goto((root / "ui/panel.html").as_uri())
    page.evaluate("window.handlers.update({recording: false, places: ['casino', 'dojo', 'lancre', 'savannah', 'smugglers']})")
    assert page.locator(".place-entry").count() == 5
    assert page.locator("#stop").is_disabled()
    page.locator("#search").fill("DOJ")
    assert page.locator(".place-entry").count() == 1
    assert page.locator(".place-name").inner_text() == "dojo"
    page.locator(".go-btn").click()
    assert page.evaluate("window.messages.at(-1)") == {"name": "go", "data": {"name": "dojo"}}
    page.locator(".see-btn").click()
    assert page.evaluate("window.messages.at(-1)") == {"name": "see", "data": {"name": "dojo"}}
    go = page.locator(".go-btn").bounding_box()
    trash = page.locator(".remove-btn").bounding_box()
    see = page.locator(".see-btn").bounding_box()
    assert go["width"] >= 40 and trash["x"] - (see["x"] + see["width"]) >= 12
    page.locator(".remove-btn").click()
    assert page.evaluate("window.messages.at(-1)") == {"name": "remove", "data": {"name": "dojo"}}
    page.locator("#search").fill("missing")
    assert page.locator(".place-entry").count() == 0
    assert page.locator("#empty").inner_text() == "No matching blorps."
    page.locator("#clear-search").click()
    assert page.locator("#search").input_value() == ""
    assert page.locator(".place-entry").count() == 5
    page.locator("#search").fill("casino")
    page.locator("#search").fill("")
    assert page.locator(".place-entry").count() == 5
    page.locator("#search").fill("dojo")
    page.evaluate("window.handlers.update({recording: true, places: ['casino', 'dojo', 'dojo annex']})")
    assert page.locator(".place-entry").count() == 2
    assert page.locator("#start").is_disabled()
    page.locator("#clear-search").click()
    page.evaluate("window.handlers.update({recording: false, places: ['casino', 'dojo', 'lancre', 'savannah', 'smugglers']})")
    assert not errors, errors
    if len(sys.argv) > 1:
        page.screenshot(path=sys.argv[1])
    browser.close()
print("PASS: panel search, clear, live updates, Go/See/remove, button spacing, and recording status")
