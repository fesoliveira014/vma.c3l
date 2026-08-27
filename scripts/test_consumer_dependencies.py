import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


class ConsumerDependencyTests(unittest.TestCase):
    def test_sdl3_is_not_a_repository_dependency(self) -> None:
        entry = git("ls-files", "--stage", "--", "test/libs/sdl3.c3l")
        self.assertEqual("", entry)

    def test_vulkan_test_binding_is_opt_in_and_shallow(self) -> None:
        prefix = "submodule.test/libs/vk.c3l"
        self.assertEqual(
            "none",
            git("config", "-f", ".gitmodules", "--get", f"{prefix}.update"),
        )
        self.assertEqual(
            "true",
            git("config", "-f", ".gitmodules", "--get", f"{prefix}.shallow"),
        )


if __name__ == "__main__":
    unittest.main()
