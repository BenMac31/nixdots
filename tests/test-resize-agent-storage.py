import importlib.util
from pathlib import Path
import stat
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location("resize", Path(__file__).parents[1] / "scripts/resize-agent-storage.py")
resize = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resize)


class Capacity(unittest.TestCase):
    def info(self, size=128, allocated=128, mode=stat.S_IFREG):
        return SimpleNamespace(st_mode=mode, st_size=size * resize.GIB,
                               st_blocks=allocated * resize.GIB // 512)

    def check(self, info, available=188, target=192):
        return resize.check_capacity(info, 128 * resize.GIB, target * resize.GIB,
                                     available * resize.GIB, 96 * resize.GIB)

    def test_growth_retains_host_headroom(self):
        self.assertEqual(self.check(self.info()), 64 * resize.GIB)
        with self.assertRaisesRegex(RuntimeError, "host headroom"):
            self.check(self.info(), available=159)

    def test_interrupted_allocation_is_not_mistaken_for_preallocated_space(self):
        with self.assertRaisesRegex(RuntimeError, "host headroom"):
            self.check(self.info(size=192, allocated=128), available=100)
        self.assertEqual(self.check(self.info(size=192, allocated=192), available=100), 0)

    def test_unexpected_image_type_size_and_shrink_are_refused(self):
        for info in (self.info(mode=stat.S_IFLNK), self.info(size=160)):
            with self.assertRaises(RuntimeError):
                self.check(info)
        with self.assertRaisesRegex(RuntimeError, "only grows"):
            self.check(self.info(), target=128)


if __name__ == "__main__":
    unittest.main()
