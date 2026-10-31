import sys
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from droidlab.core.command_guards import explicit_device_selector,is_adb_target_connected,is_destructive_adb,is_destructive_fastboot,is_fastboot_target_connected,is_valid_partition_name,validate_device_selector
import server
class CommandGuardTests(unittest.TestCase):
 def test_adb_destructive_detection(self):
  self.assertTrue(is_destructive_adb(["shell","rm","-rf","/data"]))
  self.assertTrue(is_destructive_adb(["shell","sh","-c","rm -rf /data"]))
  self.assertTrue(is_destructive_adb(["reboot","bootloader"]))
  self.assertFalse(is_destructive_adb(["shell","getprop","ro.build.version.release"]))
 def test_fastboot_destructive_detection(self):
  self.assertTrue(is_destructive_fastboot(["flash","boot","boot.img"]))
  self.assertTrue(is_destructive_fastboot(["-w"]))
  self.assertTrue(is_destructive_fastboot(["flashing","unlock"]))
  self.assertFalse(is_destructive_fastboot(["getvar","product"]))
 def test_partition_validation(self):
  self.assertTrue(is_valid_partition_name("vendor_boot_a"))
  for value in ("",".","../userdata","-boot","boot/../system"):self.assertFalse(is_valid_partition_name(value))
 def test_serial_selector(self):
  self.assertEqual(explicit_device_selector(["-s","serial-1","shell"],"adb"),"serial-1")
  with self.assertRaises(ValueError):explicit_device_selector(["-s","one","-s","two","shell"],"adb")
  with self.assertRaises(ValueError):validate_device_selector(["-s","other","shell"],"adb","selected")
 def test_transport_states(self):
  adb="List of devices attached\nSERIAL device product:foo\nRECOVERY recovery\nOFFLINE offline\n"
  self.assertTrue(is_adb_target_connected("SERIAL",adb))
  self.assertFalse(is_adb_target_connected("OFFLINE",adb))
  self.assertTrue(is_adb_target_connected("RECOVERY",adb,allowed_states=("recovery",)))
  self.assertTrue(is_fastboot_target_connected("FB-1","FB-1 fastboot product:foo\n"))
  self.assertFalse(is_fastboot_target_connected("FB-1","FB-1 fastboot\n",returncode=1))
 def test_confirmation_is_bound_to_exact_operation_intent(self):
  intent={"operation":"fastboot.erase","serial":"DEVICE-1","partition":"userdata"}
  server.require_confirmation({"confirmed":True,"confirmation":intent},"Fastboot erase",intent)
  with self.assertRaises(PermissionError):server.require_confirmation({"confirmed":True,"confirmation":{**intent,"partition":"boot"}},"Fastboot erase",intent)

 def test_require_adb_explains_unauthorized_device_without_dispatch(self):
  output="List of devices attached\\n1bf3c2b0 unauthorized usb:1-1\\n"
  with unittest.mock.patch.object(server,"tool_path",return_value="adb"), unittest.mock.patch.object(server,"run_capture",return_value=__import__("subprocess").CompletedProcess(["adb","devices","-l"],0,output,"")):
   with self.assertRaisesRegex(RuntimeError,"accept the.*RSA fingerprint prompt"):
    server.require_adb("1bf3c2b0")
if __name__=="__main__":unittest.main()
