import unittest
from execution.publish_online_test_frontends import target_paths


class TestFrontendTargets(unittest.TestCase):
    def test_only_the_named_test_web_roots_are_allowed(self):
        for name in ('usertest', 'clienttest'):
            web, releases, static = target_paths(name)
            self.assertEqual(web.as_posix(), '/var/www/defensys-' + name)
            self.assertEqual(releases.as_posix(), web.as_posix() + '-releases')
            self.assertEqual(static.as_posix(), web.as_posix() + '-static')
        for name in ('production', 'defensys', '../defensys', '', '/var/www/defensys'):
            with self.assertRaises(ValueError):
                target_paths(name)


if __name__ == '__main__':
    unittest.main()
