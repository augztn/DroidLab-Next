import os,sys,tempfile,threading,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import server
class ProtocolTests(unittest.TestCase):
 def test_ping(self):
  result=server.execute("id","system.ping",{},threading.Event())
  self.assertEqual(result["status"],"ok");self.assertEqual(result["protocol_version"],1)
 def test_configured_tool_path(self):
  with tempfile.TemporaryDirectory() as directory:
   executable=Path(directory)/"adb";executable.write_text("#!/bin/sh\nexit 0\n");executable.chmod(0o755)
   with patch.dict(os.environ,{"DROIDLAB_ADB_PATH":str(executable)}):self.assertEqual(server.tool_path("adb"),str(executable))
 def test_invalid_partition_rejected(self):
  with tempfile.TemporaryDirectory() as directory:
   image=Path(directory)/"boot.img";image.write_bytes(b"image")
   with self.assertRaises(ValueError):server.execute("id","fastboot.flash",{"serial":"SERIAL","partition":"../userdata","image_path":str(image),"confirmed":True},threading.Event())
 def test_mutation_requires_confirmation(self):
  with self.assertRaises(PermissionError):server.require_confirmation({},"Fastboot flash")
 def test_fastboot_reboot_rejects_unknown_mode(self):
  with self.assertRaises(ValueError):
   server.execute("id","fastboot.reboot",{"serial":"SERIAL","mode":"unsupported"},threading.Event())
 def test_fastboot_wipe_requires_exact_confirmation(self):
  with self.assertRaises(PermissionError):
   server.execute("id","fastboot.wipe",{"serial":"SERIAL","confirmed":True},threading.Event())
 def test_fastboot_wipe_is_serialized_as_mutation(self):
  self.assertIn("fastboot.wipe",server._MUTATING)
if __name__=="__main__":unittest.main()
