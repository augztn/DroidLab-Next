import json, os, queue, subprocess, sys, tempfile, threading, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];SERVER=ROOT/"server.py"
class ProtocolIntegrationTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();root=Path(self.temp.name)
  adb=root/"adb";fastboot=root/"fastboot"
  adb.write_text("#!/usr/bin/env python3\nimport sys,os,shutil\na=sys.argv[1:]\nopen(os.environ['ADB_CALLS'],'a').write(' '.join(a)+'\\n')\nif a==['devices','-l']:\n print('List of devices attached');print(os.environ.get('ADB_STATE','SERIAL-1 device product:test'))\nelif len(a)>=4 and a[:2]==['-s','SERIAL-1'] and a[2]=='shell':print('14')\nelif len(a)>=5 and a[:2]==['-s','SERIAL-1'] and a[2]=='pull':shutil.copyfile(os.environ['PULL_SOURCE'],os.path.join(a[4],os.path.basename(a[3])))\nelif len(a)>=5 and a[:2]==['-s','SERIAL-1'] and a[2]=='push':print('1 file pushed')\nelif len(a)>=3 and a[:2]==['-s','SERIAL-1'] and a[2]=='reboot':print('reboot accepted')\nelse:sys.exit(2)\n")
  fastboot.write_text("#!/usr/bin/env python3\nimport sys,os\na=sys.argv[1:]\nopen(os.environ['FASTBOOT_CALLS'],'a').write(' '.join(a)+'\\n')\nif a==['devices','-l']:print(os.environ.get('FASTBOOT_STATE','FASTBOOT-1 fastboot product:test'))\nelif len(a)>=3 and a[:2]==['-s','SERIAL-1'] and a[2]=='reboot':print('reboot accepted')\nelse:sys.exit(2)\n")
  adb.chmod(0o755);fastboot.chmod(0o755);env=os.environ.copy();self.adb_calls=root/'adb.calls';self.fastboot_calls=root/'fastboot.calls';self.pull_source=root/'device-file.txt';self.pull_source.write_text('pulled data');env.update(DROIDLAB_ADB_PATH=str(adb),DROIDLAB_FASTBOOT_PATH=str(fastboot),ADB_CALLS=str(self.adb_calls),FASTBOOT_CALLS=str(self.fastboot_calls),PULL_SOURCE=str(self.pull_source))
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
 def test_invalid_cancel_request_is_rejected(self):
  events=self.request("bad-cancel","system.cancel",{"request_id":""})
  self.assertEqual(events[-1]["type"],"failed")
  self.assertIn("request_id",events[-1]["error"]["message"])
 def test_whitespace_only_request_id_is_ignored_without_killing_backend(self):
  self.p.stdin.write(json.dumps({"version":1,"id":"   ","operation":"system.ping","args":{}})+"\n")
  self.p.stdin.flush()
  events=self.request("after-invalid","system.ping",{})
  self.assertEqual(events[-1]["type"],"completed")
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
 def test_adb_pull_publishes_downloaded_file(self):
  root=Path(self.temp.name)
  destination=root/'downloads';destination.mkdir()
  args={"serial":"SERIAL-1","direction":"pull","source_path":"/sdcard/device-file.txt",
   "destination_path":str(destination),"confirmed":True,
   "confirmation":{"operation":"adb.transfer","serial":"SERIAL-1","direction":"pull",
    "source_path":"/sdcard/device-file.txt","destination_path":str(destination)}}
  events=self.request("adb-pull","adb.transfer",args)
  self.assertEqual(events[-1]["type"],"completed")
  result=events[-1]["result"]
  self.assertEqual(result["direction"],"pull")
  self.assertEqual(Path(result["path"]).read_text(),"pulled data")
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
   FASTBOOT_STATE="SERIAL-1 fastboot product:test", ADB_STATE="OTHER-1 device product:test")
  self.p=subprocess.Popen([sys.executable,"-u",str(SERVER)],cwd=ROOT,stdin=subprocess.PIPE,
   stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,encoding="utf-8",env=env,bufsize=1)
  self.events=queue.Queue();self.reader=threading.Thread(target=self._read_events,daemon=True);self.reader.start()
  args={"serial":"SERIAL-1","mode":"recovery","confirmed":True,
   "confirmation":{"operation":"adb.reboot","serial":"SERIAL-1","mode":"recovery"}}
  events=self.request("fastboot-reboot","adb.reboot",args)
  self.assertEqual(events[-1]["type"],"completed")
  self.assertEqual(events[-1]["result"]["transport"],"fastboot")
  self.assertIn("-s SERIAL-1 reboot recovery",self.fastboot_calls.read_text())
  fastbootd_args={"serial":"SERIAL-1","mode":"fastboot","confirmed":True,
   "confirmation":{"operation":"adb.reboot","serial":"SERIAL-1","mode":"fastboot"}}
  fastbootd_events=self.request("fastbootd-reboot","adb.reboot",fastbootd_args)
  self.assertEqual(fastbootd_events[-1]["type"],"completed")
  self.assertIn("-s SERIAL-1 reboot fastboot",self.fastboot_calls.read_text())
 def test_adb_push_is_reported_as_device_mutation(self):
  root=Path(self.temp.name);source=root/'upload.txt';source.write_text('upload data')
  destination='/sdcard/Download/upload.txt'
  intent={"operation":"adb.transfer","serial":"SERIAL-1","direction":"push",
   "source_path":str(source),"destination_path":destination}
  events=self.request("adb-push","adb.transfer",{
   "serial":"SERIAL-1","direction":"push","source_path":str(source),
   "destination_path":destination,"confirmed":True,"confirmation":intent})
  self.assertEqual(events[-1]["type"],"completed")
  preflight=next(event for event in events if event["type"]=="preflight")
  self.assertTrue(preflight["destructive"])

if __name__=="__main__":unittest.main()
