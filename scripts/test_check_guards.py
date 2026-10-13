#!/usr/bin/env python3
#
# python3 -m unittest discover -s scripts -p 'test_*.py'
#
# Each test plants one violation in a throwaway git repository holding this
# repository's .guards.json, and asserts the check rejects it with a location
# and a remedy. The last test runs the check over this repository itself.
#

import os
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT = os.path.join(HERE, "check_guards.py")

SI = "modules/masterclass-cms-site-initializer/src/main/resources/site-initializer"
BATCH = "client-extensions/masterclass-cms-data-batch/batch"


class CheckGuardsTest(unittest.TestCase):

	def setUp(self):
		self.repo = tempfile.mkdtemp()
		self.addCleanup(shutil.rmtree, self.repo)

		self.git("init", "-q")
		self.git("config", "core.symlinks", "true")

		shutil.copy(os.path.join(ROOT, ".guards.json"), self.repo)

		self.write(f"{SI}/layouts/home/page-definition.json", '{"classPK": "[#LAYOUT_ID:/home#]"}\n')

	def git(self, *args):
		subprocess.run(["git", *args], check=True, cwd=self.repo)

	def write(self, path, content, mode="w"):
		full = os.path.join(self.repo, path)

		os.makedirs(os.path.dirname(full), exist_ok=True)

		with open(full, mode) as target:
			target.write(content)

	def run_check(self):
		self.git("add", "-A")

		return subprocess.run(
			[sys.executable, SCRIPT], capture_output=True, cwd=self.repo, text=True
		)

	def assert_rejected(self, path, line, guard, remedy):
		result = self.run_check()

		self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
		self.assertIn(f"{path}:{line}: [{guard}]" if line else f"{path}: [{guard}]", result.stdout)
		self.assertIn(remedy, result.stdout)

	def test_clean_tree_passes(self):
		result = self.run_check()

		self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

	def test_hash_token_inside_a_longer_string(self):
		self.write(f"{SI}/layouts/home/page-definition.json", '{\n"url": "/web/x/[#LAYOUT_ID:/home#]"\n}\n')

		self.assert_rejected(f"{SI}/layouts/home/page-definition.json", 2, "hash-token-outside-quotes", "instead:")

	def test_numeric_object_field_key(self):
		self.write(f"{SI}/layouts/blog/page-definition.json", '{\n"fieldKey": "ObjectField_37434#fileURL"\n}\n')

		self.assert_rejected(f"{SI}/layouts/blog/page-definition.json", 2, "numeric-object-field-key", "OBJECT_FIELD_KEY")

	def test_numeric_object_field_key_in_the_batch(self):
		self.write(f"{BATCH}/08-elearning-blog.batch-engine-data.json", '{"x": "ObjectField_12"}\n')

		self.assert_rejected(f"{BATCH}/08-elearning-blog.batch-engine-data.json", 1, "numeric-object-field-key", "ObjectField_<fieldName>")

	def test_generated_relationship_name(self):
		self.write(f"{SI}/layouts/x/page-definition.json", '{"className": "Provider_name7252b11db32e4f01aeb20124"}\n')

		self.assert_rejected(f"{SI}/layouts/x/page-definition.json", 1, "generated-relationship-name", "declared name")

	def test_group_template_grant(self):
		self.write(f"{SI}/resource-permissions.json", '[\n{\n"roleName": "Guest",\n"scope": "3"\n}\n]\n')

		self.assert_rejected(f"{SI}/resource-permissions.json", 4, "group-template-grant", "\"scope\": \"1\"")

	def test_group_template_is_fine_in_roles(self):
		self.write(f"{SI}/roles.json", '[\n{\n"scope": 3,\n"name": "x"\n}\n]\n')

		self.assertEqual(self.run_check().returncode, 0)

	def test_system_flag(self):
		self.write(f"{SI}/object-definitions/01-x.json", '{\n"system": true\n}\n')

		self.assert_rejected(f"{SI}/object-definitions/01-x.json", 2, "system-object-flag", "false")

	def test_restated_skill_router(self):
		self.write(".agents/liferay-rules.md", "## Skill Router\n")
		self.write(".gemini/GEMINI.md", "# Rules\n\n## Skill Router\n")

		self.assert_rejected(".gemini/GEMINI.md", 3, "restated-skill-router", "@.agents/liferay-rules.md")

	def test_invalid_json(self):
		self.write(f"{SI}/site-navigation-menus.json", '[{name: "Main"}]\n')

		self.assert_rejected(f"{SI}/site-navigation-menus.json", None, "json", "")

	def test_latin_1_json(self):
		self.write(f"{SI}/roles.json", '["Caf\xe9"]\n'.encode("latin-1"), mode="wb")

		self.assert_rejected(f"{SI}/roles.json", None, "json", "not UTF-8")

	def test_symlink_committed_as_text(self):
		self.write(".agents/skills/x/card.md", "# Card\n")
		self.write(".agents/rules/card.md", "../skills/x/card.md")

		self.assert_rejected(".agents/rules/card.md", None, "text-symlink", "ln -s ../skills/x/card.md")

	def test_real_symlink_passes(self):
		self.write(".agents/skills/x/card.md", "# Card\n")
		os.makedirs(os.path.join(self.repo, ".agents/rules"))
		os.symlink("../skills/x/card.md", os.path.join(self.repo, ".agents/rules/card.md"))

		self.assertEqual(self.run_check().returncode, 0)

	def test_guard_without_why_is_a_config_error(self):
		self.write(".guards.json", '{"guards": [{"id": "x", "include": ["*"], "instead": "y", "pattern": "z"}]}')

		result = self.run_check()

		self.assertEqual(result.returncode, 2)
		self.assertIn("missing why", result.stderr)

	def test_invalid_config_is_a_config_error(self):
		self.write(".guards.json", "{")

		self.assertEqual(self.run_check().returncode, 2)

	def test_config_is_not_scanned(self):
		result = self.run_check()

		self.assertNotIn(".guards.json", result.stdout)


class RepositoryTest(unittest.TestCase):

	def test_this_repository_passes(self):
		result = subprocess.run(
			[sys.executable, SCRIPT], capture_output=True, cwd=ROOT, text=True
		)

		self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
	unittest.main()
