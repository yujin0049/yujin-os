"""yujin-os: agent principals get only the scopes listed for their unit."""
import json
import os
import unittest

from helpers import Env

from grokbotd import perms

UID = os.getuid()
AGENT = "local:uid=%d:unit=yujin-agent.service" % UID
OTHER = "local:uid=%d:unit=other.service" % UID
CLI = "local:uid=%d:exe=/usr/bin/grokbot-os" % UID


class AgentPerms(unittest.TestCase):
    def setUp(self):
        self.env = Env()
        os.environ["GROKBOT_API_GRANTS"] = self.env.path("cfg", "grants.json")
        os.environ["GROKBOT_API_SYS_PERMISSIONS"] = self.env.write("sys.json", json.dumps({
            "local": {"notifications": "allow", "permissions": "allow", "input": "allow"},
            "agents": {"yujin-agent.service": {"notifications": "allow", "files": "ask", "camera": "allow"},
                       "not-a-service": {"input": "allow"}},
        }))
        perms._session.clear()

    def tearDown(self):
        perms._session.clear()
        self.env.close()

    def test_listed_scope(self):
        self.assertEqual(perms.mode_for(AGENT, "notifications", "write"), ("allow", "agent"))
        self.assertEqual(perms.mode_for(AGENT, "files", "read"), ("ask", "agent"))

    def test_unlisted_scope_denied_even_for_reads(self):
        self.assertEqual(perms.mode_for(AGENT, "system", "read"), ("deny", "agent"))
        self.assertEqual(perms.mode_for(AGENT, "permissions", "write"), ("deny", "agent"))
        self.assertEqual(perms.mode_for(AGENT, "input", "write"), ("deny", "agent"))

    def test_always_ask_scopes_still_ask(self):
        self.assertEqual(perms.mode_for(AGENT, "camera", "write")[0], "ask")

    def test_other_local_callers_unchanged(self):
        self.assertEqual(perms.mode_for(OTHER, "system", "read"), ("allow", "builtin"))
        self.assertEqual(perms.mode_for(CLI, "input", "write"), ("allow", "system"))
        self.assertIsNone(perms.agent_unit("local:uid=%d:unit=not-a-service" % UID))

    def test_user_grant_wins(self):
        perms.set_mode(AGENT, "system", "allow", by="test")
        self.assertEqual(perms.mode_for(AGENT, "system", "read"), ("allow", "user"))

    def test_user_file_cannot_add_agents(self):
        self.env.write("cfg/grokbot/api-permissions.json", json.dumps(
            {"agents": {"yujin-agent.service": {"system": "allow"}}}))
        self.assertEqual(perms.mode_for(AGENT, "system", "read"), ("deny", "agent"))

    def test_listed_in_listing(self):
        self.assertIn(AGENT, [x["principal"] for x in perms.listing()])


if __name__ == "__main__":
    unittest.main()
