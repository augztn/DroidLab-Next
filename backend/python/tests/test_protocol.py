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
 def test_advanced_fastboot_command_requires_confirmation(self):
  with self.assertRaises(PermissionError):
   server.execute("id","fastboot.command",{
    "serial":"SERIAL","command":"getvar all","confirmed":True
   },threading.Event())
 def test_advanced_fastboot_command_rejects_target_override(self):
  with self.assertRaises(ValueError):
   server.execute("id","fastboot.command",{
    "serial":"SERIAL","command":"-s OTHER devices"
   },threading.Event())
 def test_advanced_fastboot_command_is_serialized_as_mutation(self):
  self.assertIn("fastboot.command",server._MUTATING)

 def test_tool_path_reads_legacy_settings_json(self):
  with tempfile.TemporaryDirectory() as directory:
   home=Path(directory);config=home/"DroidLab"/"config.json";config.parent.mkdir()
   executable=home/"adb";executable.write_text("#!/bin/sh\\nexit 0\\n");executable.chmod(0o755)
   config.write_text(__import__("json").dumps({"adb_path":str(executable)}),encoding="utf-8")
   with patch.dict(os.environ,{"HOME":directory},clear=False), patch.object(server.shutil,"which",return_value=None):
    self.assertEqual(server.tool_path("adb"),str(executable))
 def test_adb_reboot_routes_to_fastboot_in_bootloader(self):
  cancel=threading.Event()
  args={"serial":"SERIAL","mode":"recovery","confirmed":True,
   "confirmation":{"operation":"adb.reboot","serial":"SERIAL","mode":"recovery"}}
  adb_scan=type("Result",(),{"stdout":"List of devices attached\\n","returncode":0,"stderr":""})()
  fastboot_scan=type("Result",(),{"stdout":"SERIAL fastboot\\n","returncode":0,"stderr":""})()
  completed=type("Result",(),{"returncode":0,"stdout":"OKAY\\n","stderr":""})()
  with patch.object(server,"tool_path",side_effect=lambda name:name), \\
       patch.object(server,"run_capture",side_effect=[adb_scan,fastboot_scan]), \\
       patch.object(server,"run_streaming",return_value=completed) as run, \\
       patch.object(server,"response"):
    result=server.execute("id","adb.reboot",args,cancel)
  self.assertEqual(result["transport"],"fastboot")
  self.assertEqual(run.call_args.args[0],["fastboot","-s","SERIAL","reboot","recovery"])
 def test_device_info_reads_adb_and_battery_metadata(self):
  cancel=threading.Event()
  scan={"devices":[{"serial":"SERIAL","transport":"adb","state":"device"}],"warnings":[]}
  props=type("Result",(),{"returncode":0,"stdout":"[ro.product.manufacturer]: [Example]\\n[ro.product.model]: [Unit X]\\n[ro.product.device]: [unitx]\\n[ro.build.version.release]: [15]\\n[ro.build.version.sdk]: [35]\\n[ro.boot.slot_suffix]: [_a]\\n","stderr":""})()
  battery=type("Result",(),{"returncode":0,"stdout":"Current Battery Service state:\\n  level: 87\\n","stderr":""})()
  with patch.object(server,"execute",return_value=scan), \\
       patch.object(server,"tool_path",return_value="adb"), \\
       patch.object(server,"run_streaming",side_effect=[props,battery]):
   result=server.execute("id","device.info",{"serial":"SERIAL"},cancel)
  self.assertEqual(result["metadata"]["Brand / Manufacturer"],"Example")
  self.assertEqual(result["metadata"]["Device name / Model"],"Unit X")
  self.assertEqual(result["metadata"]["Codename"],"unitx")
  self.assertEqual(result["metadata"]["Active slot"],"_a")
  self.assertEqual(result["metadata"]["Android Version"],"15")
  self.assertEqual(result["metadata"]["Battery"],"87%")
 def test_fastboot_set_active_requires_exact_confirmation(self):
  args={"serial":"SERIAL","slot":"a","confirmed":True}
  with self.assertRaises(PermissionError):
   server.execute("id","fastboot.set_active",args,threading.Event())
 def test_fastboot_set_active_uses_fallback_syntax(self):
  args={"serial":"SERIAL","slot":"b","confirmed":True,
   "confirmation":{"operation":"fastboot.set_active","serial":"SERIAL","slot":"b"}}
  scan=type("Result",(),{"stdout":"SERIAL fastboot\\n","returncode":0,"stderr":""})()
  failed=type("Result",(),{"returncode":1,"stdout":"unknown command\\n","stderr":""})()
  completed=type("Result",(),{"returncode":0,"stdout":"OKAY\\n","stderr":""})()
  with patch.object(server,"tool_path",return_value="fastboot"), \\
       patch.object(server,"run_capture",return_value=scan), \\
       patch.object(server,"run_streaming",side_effect=[failed,completed]) as run, \\
       patch.object(server,"response"):
   result=server.execute("id","fastboot.set_active",args,threading.Event())
  self.assertEqual(result["slot"],"b")
  self.assertEqual(run.call_args_list[1].args[0],["fastboot","-s","SERIAL","set_active","b"])
 def test_fastboot_set_active_is_serialized(self):
  self.assertIn("fastboot.set_active",server._MUTATING)
if __name__=="__main__":unittest.main()
