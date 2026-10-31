import sys,threading,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from droidlab.core.process_runner import run_streaming,ProcessCancelledError
class ProcessRunnerTests(unittest.TestCase):
 def test_capture_output(self):
  result=run_streaming([sys.executable,"-c","print('ready')"],timeout=5)
  self.assertEqual(result.returncode,0);self.assertIn("ready",result.stdout)
 def test_cancel_before_launch(self):
  event=threading.Event();event.set()
  with self.assertRaises(ProcessCancelledError):run_streaming([sys.executable,"-c","print('no')"],cancel_event=event)
 def test_cancellation_terminates_running_process(self):
  event=threading.Event();timer=threading.Timer(0.2,event.set);timer.start()
  try:
   with self.assertRaises(ProcessCancelledError):run_streaming([sys.executable,"-c","import time;time.sleep(20)"],timeout=5,cancel_event=event)
  finally:timer.cancel();timer.join(timeout=1)
 def test_output_retention_is_bounded(self):
  result=run_streaming([sys.executable,"-c","print('x'*10000)"],timeout=5,max_output_chars=128)
  self.assertLess(len(result.stdout),256);self.assertIn("output line(s) omitted",result.stdout)
if __name__=="__main__":unittest.main()
