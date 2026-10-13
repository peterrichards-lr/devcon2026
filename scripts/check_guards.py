#!/usr/bin/env python3
#
# check_guards.py: fail on bug classes that have already cost us a provision.
#
#   python3 scripts/check_guards.py
#
# Exit 0 when clean, 1 with findings, 2 when .guards.json itself is wrong.
#
# Three kinds of check, all configured or explained in .guards.json:
#
#   guards    a line regex over tracked and untracked (not ignored) files. Each
#             guard must say why it exists and what to do instead, so a finding
#             teaches rather than nags.
#   json      every matching file must be UTF-8 and valid JSON. A bad file stops
#             its initializer handler without a log line of its own.
#   symlinks  no tracked file may be a symlink committed as text. Git writes
#             one when core.symlinks is false, and an agent reading it gets a
#             path instead of the file (rlluis/devcon2026#24, and the portability
#             card in .agents/rules until 2026-10-13).
#
# Zero dependencies, so it runs anywhere python3 does.
#

import fnmatch
import json
import os
import re
import subprocess
import sys

CONFIG = ".guards.json"

REQUIRED = ("id", "include", "instead", "pattern", "why")


class ConfigError(Exception):
	pass


def git(*args):
	return subprocess.run(
		["git", *args], capture_output=True, check=True, text=True
	).stdout


def files():
	tracked = git("ls-files", "-z").split("\0")
	untracked = git("ls-files", "-z", "--others", "--exclude-standard").split("\0")

	return sorted(
		path
		for path in set(tracked + untracked)
		if path and path != CONFIG and os.path.isfile(path)
	)


def load_config():
	try:
		with open(CONFIG, encoding="utf-8") as config_file:
			config = json.load(config_file)
	except (OSError, ValueError) as error:
		raise ConfigError(f"{CONFIG}: {error}")

	guards = config.get("guards")

	if not isinstance(guards, list) or not guards:
		raise ConfigError(f"{CONFIG}: \"guards\" must be a non-empty list")

	ids = set()

	for guard in guards:
		missing = [key for key in REQUIRED if not guard.get(key)]

		if missing:
			raise ConfigError(
				f"{CONFIG}: guard {guard.get('id', '?')} is missing {', '.join(missing)}"
			)

		if guard["id"] in ids:
			raise ConfigError(f"{CONFIG}: duplicate guard id {guard['id']}")

		ids.add(guard["id"])

		try:
			guard["regex"] = re.compile(guard["pattern"])
		except re.error as error:
			raise ConfigError(f"{CONFIG}: guard {guard['id']} pattern: {error}")

	json_globs = config.get("json", [])

	if not isinstance(json_globs, list):
		raise ConfigError(f"{CONFIG}: \"json\" must be a list of globs")

	return guards, json_globs


def matches(path, globs):
	return any(fnmatch.fnmatchcase(path, glob) for glob in globs)


def check_guards(paths, guards):
	findings = []

	for guard in guards:
		for path in paths:
			if not matches(path, guard["include"]) or matches(
				path, guard.get("exclude", [])
			):
				continue

			try:
				with open(path, encoding="utf-8") as source:
					lines = source.read().splitlines()
			except (OSError, UnicodeDecodeError):
				continue

			for number, line in enumerate(lines, 1):
				if guard["regex"].search(line):
					findings.append(
						f"{path}:{number}: [{guard['id']}] {guard['why']}\n"
						f"    instead: {guard['instead']}"
					)

	return findings


def check_json(paths, globs):
	findings = []

	for path in paths:
		if not matches(path, globs):
			continue

		try:
			with open(path, "rb") as source:
				json.loads(source.read().decode("utf-8"))
		except UnicodeDecodeError as error:
			findings.append(f"{path}: [json] not UTF-8 at byte {error.start}")
		except ValueError as error:
			findings.append(f"{path}: [json] {error}")

	return findings


def check_symlinks():
	findings = []

	for entry in git("ls-files", "-s", "-z").split("\0"):
		if not entry:
			continue

		meta, path = entry.split("\t", 1)

		if not meta.startswith("100644") or os.path.islink(path):
			continue

		try:
			if os.path.getsize(path) > 512:
				continue

			with open(path, encoding="utf-8") as source:
				content = source.read()
		except (OSError, UnicodeDecodeError):
			continue

		target = content.strip()

		if (
			target
			and "\n" not in target
			and " " not in target
			and target.startswith(("../", "./"))
			and os.path.exists(os.path.join(os.path.dirname(path), target))
		):
			findings.append(
				f"{path}: [text-symlink] holds the path {target} instead of linking to it\n"
				f"    instead: rm {path} && ln -s {target} {path}"
			)

	return findings


def main():
	os.chdir(git("rev-parse", "--show-toplevel").strip())

	try:
		guards, json_globs = load_config()
	except ConfigError as error:
		print(error, file=sys.stderr)

		return 2

	paths = files()

	findings = (
		check_guards(paths, guards) + check_json(paths, json_globs) + check_symlinks()
	)

	for finding in findings:
		print(finding)

	if findings:
		print(f"\n{len(findings)} finding(s). See {CONFIG} for why each guard exists.")

		return 1

	print(f"{len(paths)} files clean against {len(guards)} guards, JSON and symlink checks.")

	return 0


if __name__ == "__main__":
	sys.exit(main())
