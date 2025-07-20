import re
from playwright.sync_api import Page, expect


def test_visitor_counter_has_value(page: Page):
    page.goto("https://resume.nattapol.com")
    # Wait 5 seconds for DynamoDB to start
    page.wait_for_timeout(5000)
    locator = page.locator("#visitor-counter-value")
    expect(locator).to_have_text(re.compile(r"[0-9]+"))


def test_visitor_counter_increase(page: Page):
    page.goto("https://resume.nattapol.com")
    page.wait_for_timeout(5000)
    locator = page.locator("#visitor-counter-value")
    first_value = int(locator.text_content())

    page.goto("https://resume.nattapol.com")
    page.wait_for_timeout(5000)
    locator = page.locator("#visitor-counter-value")
    second_value = int(locator.text_content())

    assert second_value > first_value
