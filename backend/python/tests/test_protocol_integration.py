import json, os, queue, subprocess, sys, tempfile, threading, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];SERVER=ROOT/"server.py"
class ProtocolIntegrationTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();root=Path(self.temp.name)
  adb=root/"adb";fastboot=root/"fastboot"
  adb.write_text("#!/usr/bin/env python3\nimport sys\na=sys.argv[1:]\nif a==['devices','-l']:\n print('List of devices attached');print('SERIAL-1 device product:test')\nelif len(a)>=4 and a[:2]==['-s','SERIAL-1'] and a[2]=='shell':print('14')\nelse:sys.exit(2)\n")
  fastboot.write_text("#!/usr/bin/env python3\nimport sys\nif sys.argv[1:]==['devices','-l']:print('FASTBOOT-1 fastboot product:test')\nelse:sys.exit(2)\n")
  adb.chmod(0o755);fastboot.chmod(0o755);env=os.environ.copy();self.adb_calls=root/'adb.calls';self.fastboot_calls=root/'fastboot.calls';env.update(DROIDLAB_ADB_PATH=str(adb),DROIDLAB_FASTBOOT_PATH=str(fastboot),ADB_CALLS=str(self.adb_calls),FASTBOOT_CALLS=str(self.fastboot_calls))
  self.p=subprocess.Popen([sys.executable,"-u",str(SERVER)],cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding="utf-8",env=env,bufsize=1)
  self.events=queue.Queue()
  self.reader=threading.Thread(target=self._read_events,daemon=True);self.reader.start()
 def _read_events(self):
  for line in self.p.stdout:self.events.put(line)
 def tearDown(self):
  if self.p.stdin:self.p.stdin.close()
  try:self.p.wait(timeout=5)
  except subprocess.TimeoutExpired:self.p.kill();self.p.wait(timeout=5)
  self.reader.join(timeout=1);self.temp.cleanup()
 def request(self,rid,operation,args):
  self.p.stdin.write(json.dumps({"version":1,"id":rid,"operation":operation,"args":args})+"\n");self.p.stdin.flush();events=[]
  while True:
   try:line=self.events.get(timeout=10)
   except queue.Empty:self.fail("Timed out waiting for backend response")
   event=json.loads(line)
   if event.get("id")!=rid:continue
   events.append(event)
   if event["type"] in {"completed","failed","cancelled"}:return events
 def test_ping_discovery_and_shell(self):
  self.assertEqual(self.request("ping","system.ping",{})[-1]["result"]["protocol_version"],1)
  devices=self.request("devices","devices.list",{})[-1]["result"]["devices"]
  self.assertEqual({(x["serial"],x["transport"]) for x in devices},{("SERIAL-1","adb"),("FASTBOOT-1","fastboot")})
  shell=self.request("shell","adb.shell",{
   "serial":"SERIAL-1",
   "command":["getprop","ro.build.version.release"],
   "confirmed":True,
   "confirmation":{"operation":"adb.shell","serial":"SERIAL-1","command":["getprop","ro.build.version.release"]}
  })
  self.assertEqual(shell[-1]["type"],"completed");self.assertTrue(any(x["type"]=="preflight" for x in shell))
 def test_destructive_shell_requires_confirmation(self):
  events=self.request("unsafe","adb.shell",{"serial":"SERIAL-1","command":["rm","-rf","/data"]})
  self.assertEqual(events[-1]["type"],"failed");self.assertIn("confirmation",events[-1]["error"]["message"].lower())

 def test_reboot_routes_to_adb_when_android_is_online(self):
  args={"serial":"SERIAL-1","mode":"recovery","confirmed":True,
   "confirmation":{"operation":"adb.reboot","serial":"SERIAL-1","mode":"recovery"}}
  events=self.request("adb-reboot","adb.reboot",args)
  self.assertEqual(events[-1]["type"],"completed")
  self.assertEqual(events[-1]["result"]["transport"],"adb")
  self.assertIn("-s SERIAL-1 reboot recovery",self.adb_calls.read_text())
  self.assertFalse(self.fastboot_calls.exists())
 def test_reboot_routes_to_fastboot_when_serial_is_in_bootloader(self):
  # Switch the fake transports: ADB has no matching serial; Fastboot reports it.
  self.p.stdin.close()
  self.p.wait(timeout=5)
  self.reader.join(timeout=1)
  root=Path(self.temp.name)
  adb=root/"adb";fastboot=root/"fastboot"
  env=os.environ.copy()
  env.update(DROIDLAB_ADB_PATH=str(adb),DROIDLAB_FASTBOOT_PATH=str(fastboot),
   ADB_CALLS=str(self.adb_calls),FASTBOOT_CALLS=str(self.fastboot_calls),
   FASTBOOT_STATE="SERIAL-1 fastboot product:test")
  self.p=subprocess.Popen([sys.executable,"-u",str(SERVER)],cwd=ROOT,stdin=subprocess.PIPE,
   stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding="utf-8",env=env,bufsize=1)
  self.events=queue.Queue();self.reader=threading.Thread(target=self._read_events,daemon=True);self.reader.start()
  args={"serial":"SERIAL-1","mode":"recovery","confirmed":True,
   "confirmation":{"operation":"adb.reboot","serial":"SERIAL-1","mode":"recovery"}}
  events=self.request("fastboot-reboot","adb.reboot",args)
  self.assertEqual(events[-1]["type"],"completed")
  self.assertEqual(events[-1]["result"]["transport"],"fastboot")
  self.assertIn("-s SERIAL-1 reboot recovery",self.fastboot_calls.read_text())
if __name__=="__main__":unittest.main()
