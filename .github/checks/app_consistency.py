"""Project rules the shared engine cannot know: the pinned Caddy version appears in two places, and
the option defaults (and the test fixture) must satisfy the schema the Supervisor enforces."""
import json
import re
import sys
from pathlib import Path

import yaml

APP = Path("caddy-forge")
FIXTURE = Path(".github/tests/fixtures/options.json")
CHOICE = re.compile(r"^list\((.+)\)\??$")


def is_optional(rule):
    """A schema entry is optional when its type (or, for a list, its item type) ends with `?`."""
    if isinstance(rule, list):
        return bool(rule) and isinstance(rule[0], str) and rule[0].endswith("?")
    return isinstance(rule, str) and rule.endswith("?")


def check_scalar(rule, value, where):
    choice = CHOICE.match(rule)
    if choice:
        allowed = choice.group(1).split("|")
        assert value in allowed, f"{where} is {value!r}, expected one of {allowed}"
    elif rule.rstrip("?") == "bool":
        assert isinstance(value, bool), f"{where} must be true or false"
    elif rule.rstrip("?") in ("str", "email", "password"):
        assert isinstance(value, str), f"{where} must be text"


def check_against_schema(options, schema, where=""):
    """Every option exists in the schema, has a fitting value, and no required option is missing."""
    for key, value in options.items():
        assert key in schema, f"{where}{key} is not part of the schema"
        rule = schema[key]
        if isinstance(rule, dict):
            check_against_schema(value, rule, f"{where}{key}.")
        elif isinstance(rule, list):
            assert isinstance(value, list), f"{where}{key} must be a list"
            for item in value:
                if isinstance(rule[0], dict):
                    check_against_schema(item, rule[0], f"{where}{key}[].")
                else:
                    check_scalar(rule[0], item, f"{where}{key}[]")
        else:
            check_scalar(rule, value, f"{where}{key}")
    for key, rule in schema.items():
        assert key in options or is_optional(rule), f"{where}{key} is required by the schema but has no value"


def check_pinned_caddy_version(config):
    """The version in the options is the one the image ships, so a plain setup never builds anything."""
    dockerfile = (APP / "Dockerfile").read_text()
    shipped = re.search(r"^ARG CADDY_VERSION=(\d+\.\d+\.\d+)$", dockerfile, re.M)
    assert shipped, "Dockerfile must pin ARG CADDY_VERSION=<upstream version>"
    default = str(config["options"]["caddy"]["version"])
    assert default == shipped.group(1), \
        f"config.yaml defaults to Caddy {default}, but the Dockerfile ships {shipped.group(1)}"


def check_log_level_first(config):
    """The Supervisor lists options in schema order, and the log level comes first for every user."""
    for section in ("options", "schema"):
        first = next(iter(config[section]))
        assert first == "log_level", f"{section} must start with log_level, not {first}"


def main():
    config = yaml.safe_load((APP / "config.yaml").read_text())
    check_log_level_first(config)
    check_pinned_caddy_version(config)
    check_against_schema(config["options"], config["schema"])
    check_against_schema(json.loads(FIXTURE.read_text()), config["schema"])
    # An entry of the plugin list with every field filled in.
    check_against_schema({"module": "owner/repo", "version": "v1.2.3", "enabled": False},
                         config["schema"]["caddy"]["modules"][0], "caddy.modules[].")
    print("App consistency checks passed.")


if __name__ == "__main__":
    try:
        main()
    except AssertionError as error:
        sys.exit(f"::error::{error}")
