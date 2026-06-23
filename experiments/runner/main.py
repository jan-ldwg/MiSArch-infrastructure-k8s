import subprocess
import sys
import time
import socket
import urllib.request
import urllib3
import json
import signal
import argparse
import os
import datetime
import base64
import requests
from sseclient import SSEClient


KUBECTL_SVC = "svc/misarch-experiment-executor"
KUBECTL_NAMESPACE = "misarch"
LOCAL_PORT = 4000
REMOTE_PORT = 8888
URL = f"http://127.0.0.1:{LOCAL_PORT}"
EXPERIMENTS_DIR = os.path.normpath(os.path.join(os.path.dirname(__file__), '..'))
LIST_PATH = "/experiment/list"

def make_path_absolute(base_path: str, filename: str)->str:
	if os.path.isabs(filename):
		return filename
	else:
		return os.path.join(base_path, filename)
	
def read_validate_json(file_path: str):
	with open(file_path, 'r') as f:
		try:
			conf_obj = json.load(f)
			return conf_obj
		except Exception as e:
			raise RuntimeError(f"Failed to read/parse config JSON: {e}")

def read_and_b64_encode(file_path: str):
	with open(file_path, 'r') as f:
		try:
			data = f.read()
			encoded = base64.b64encode(bytes(data, "utf-8")).decode("ascii")
			return encoded
		except Exception as e:
			raise RuntimeError(f"Unexpected error reading file {file_path}: {e}")
		
		

def start_port_forward():
	'''Set up a port forward using kubectl'''
	cmd = [
		"kubectl",
		"port-forward",
		"-n",
		KUBECTL_NAMESPACE,
		KUBECTL_SVC,
		f"{LOCAL_PORT}:{REMOTE_PORT}",
	]
	try:
		p = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
		return p
	except FileNotFoundError:
		print("kubectl not found in PATH", file=sys.stderr)
		return None


def wait_for_port(host: str, port: int, timeout: float = 10.0):
	deadline = time.time() + timeout
	while time.time() < deadline:
		try:
			with socket.create_connection((host, port), timeout=1):
				return True
		except Exception:
			time.sleep(0.2)
	return False
	
def generate_experiment(loadType: str = "NormalLoadTest")->tuple[str,str]:
	url = f"{URL}/experiment/generate?loadType=NormalLoadTest&testDuration=60&maximumArrivingUsersPerSecond=3&rate=0.9"
	req = urllib.request.Request(url, method="POST")
	try:
		with urllib.request.urlopen(req, timeout=5) as resp:
			raw = resp.read()
			try:
				data = json.loads(raw)
			except Exception:
				data = raw.decode(errors="replace")
			# response is expected as "id:version"
			return tuple(str(data).split(':'))
	except Exception as e:
		raise RuntimeError(f"Failed to generate experiment: {e}")
	

def set_json_config(config: str, e_id: str, e_version: str, url: str):
	'''Set a JSON config (Chaos Toolkit, MiSArch or global)
	
	Arguments:
	config: relative path to the config file from experiments or absolute path
	url: URL of the API endpoint
	'''
	conf_path = make_path_absolute(EXPERIMENTS_DIR, config)
	
	if not os.path.exists(conf_path):
		raise FileNotFoundError(f"Config not found: {conf_path}")
	
	conf_obj = read_validate_json(conf_path)
	
	body = json.dumps(conf_obj).encode('utf-8')
	headers = {"Content-Type": "application/json"}
	req = urllib.request.Request(url, data=body, headers=headers, method="PUT")
	try:
		with urllib.request.urlopen(req, timeout=10) as resp:
			raw = resp.read()
			try:
				return json.loads(raw)
			except Exception:
				return raw.decode(errors='replace')
	except Exception as e:
		raise RuntimeError((f"Failed to update config at {url}: {e}"))
	
def set_gatling_config(config: str, e_id: str, e_version: str, url: str):
	'''Set the gatling config of an experiment. Kotlin scripts and user steps CSV are base64 encoded and packaged into a JSON body
	
	'''
	conf_obj = []
	for variant in config:
		script_path = make_path_absolute(EXPERIMENTS_DIR, os.path.join("profiles", variant['loadScript']))
		user_path = make_path_absolute(EXPERIMENTS_DIR, os.path.join("profiles", variant['userSteps']))
		
		if not os.path.exists(script_path) or not os.path.exists(user_path):
			raise FileNotFoundError(f"Gatling config not found: {script_path} or {user_path}")
		filename = variant["loadScript"].split("/")[-1][:-3]
		variant_obj = {}
		variant_obj['fileName']= filename
		variant_obj['encodedWorkFileContent'] = read_and_b64_encode(script_path)
		variant_obj['encodedUserStepsFileContent'] = read_and_b64_encode(user_path)
		conf_obj.append(variant_obj)
		
	#url = f"{URL}/experiment/{e_id}/{e_version}/gatlingConfig"
	body = json.dumps(conf_obj).encode('utf-8')
	headers = {"Content-Type": "application/json"}
	req = urllib.request.Request(url, data=body, headers=headers, method="PUT")
	try:
		with urllib.request.urlopen(req, timeout=10) as resp:
			raw = resp.read()
			try:
				return json.loads(raw)
			except Exception:
				return raw.decode(errors='replace')
	except Exception as e:
		raise RuntimeError((f"Failed to update config at {url}: {e}"))
	
def start_experiment(e_id: str, e_version: str):
	start_url=f"{URL}/experiment/{e_id}/{e_version}/start"
	start_req=urllib.request.Request(start_url, method="POST")
	try:
		with urllib.request.urlopen(start_req, timeout=10) as res:
			if res.code == 200:
				print("Experiment started sucessfully")
			else:
				raise RuntimeError("Failed to start experiment")
	except Exception as e:
		raise RuntimeError(f"Failed to start experiment")
	
# wait for experiment to finish — server returns when finished; 504 means still running
def wait_for_event(e_id: str, e_version: str):
	"""Stream the event endpoint (SSE) and return on first `data:` field.

	This implementation uses `urllib3` directly and parses SSE lines.
	It returns parsed JSON when possible, otherwise returns the raw text.
	On errors it retries with exponential backoff up to `max_retries`.
	"""
	event_url = f"{URL}/experiment/{e_id}/{e_version}/events"
	headers = {"Accept": "text/event-stream"}
	
	def with_urllib3(url: str):
		"""Get a streaming response for the given event feed using urllib3."""
		http = urllib3.PoolManager()
		res = http.request('GET', url, preload_content=False, headers=headers)
		yield from SSEClient(res).events()
		
	try:
		for msg in with_urllib3(event_url):
			print(msg)
			return
	except requests.exceptions.MissingSchema as e:
		return
		
	
	
def run_experiment(config):
	e_id, e_version = generate_experiment()
	print(f"Created experiment {e_id}:{e_version}")
	#set_json_config(
	#	os.path.join('profiles',config['chaosConfig']),
	#	e_id,
	#	e_version,
	#	f"{URL}/experiment/{e_id}/{e_version}/chaosToolkitConfig")
	#set_json_config(
	#	os.path.join('profiles',config['misarchConfig']),
	#	e_id,
	#	e_version,
	#	f"{URL}/experiment/{e_id}/{e_version}/misarchExperimentConfig"
    #)
	#set_json_config(
	#	os.path.join('profiles',config['globalConfig']),
	#	e_id,
	#	e_version,
	#	f"{URL}/experiment/{e_id}/{e_version}/config"
    #)
	#set_gatling_config(
	#	config['gatlingConfig'],
	#	e_id,
	#	e_version,
	#	f"{URL}/experiment/{e_id}/{e_version}/gatlingConfig" )
	
	#start_experiment(e_id, e_version)
	#wait_for_event(e_id, e_version)

	return (e_id, e_version)
	
	
        

def main():
	pf_proc = None

	def _cleanup(signum=None, frame=None):
		if pf_proc and pf_proc.poll() is None:
			pf_proc.terminate()
			try:
				pf_proc.wait(timeout=2)
			except Exception:
				pf_proc.kill()
		if signum:
			sys.exit(0)

	signal.signal(signal.SIGINT, _cleanup)
	signal.signal(signal.SIGTERM, _cleanup)

	print(f"Starting port-forward -n {KUBECTL_NAMESPACE} {KUBECTL_SVC} {LOCAL_PORT}:{REMOTE_PORT}...")
	pf_proc = start_port_forward()
	if pf_proc is None:
		print("Skipping port-forward; attempting to contact localhost directly.")
	else:
		ok = wait_for_port("127.0.0.1", LOCAL_PORT, timeout=10)
		if not ok:
			print("Port-forward did not open within timeout", file=sys.stderr)

	# CLI: expect a filename (relative to the top-level `experiments/` folder)
	parser = argparse.ArgumentParser(prog="Experiment runner", description="Run automated experiments against the MiSArch system")
	parser.add_argument('-f', '--file', required=True, help='Filename inside the experiments directory')
	args = parser.parse_args()

	path = make_path_absolute(EXPERIMENTS_DIR, args.file)

	print(f"Opening experiment file: {path}")

	try:
		with open(path, 'r') as f:
			d = json.load(f)
			for experiment in d['experiments']:
				print(f"Running experiment {experiment['testName']}")
				start_time=datetime.datetime.now()
				e_id, e_version = run_experiment(experiment)
				#start_experiment("43f37247-c081-46fd-a1ea-198764774240","v14")
				#wait_for_event("43f37247-c081-46fd-a1ea-198764774240","v14")
				
				end_time=datetime.datetime.now()
				print(f"Experiment {e_id}:{e_version} finished after {(end_time-start_time).total_seconds()}s")
				#print("Finished")
				# export_to_bucket(e_id, e_version)
	except FileNotFoundError as e:
		print(e)
		# print(f"File not found: {path}", file=sys.stderr)
		sys.exit(2)
	except json.JSONDecodeError as e:
		print(f"Failed to parse JSON: {e}", file=sys.stderr)
		sys.exit(3)
		
        
if __name__ == "__main__":
	main()


