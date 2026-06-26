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
REPO_ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), '..', '..'))

PRODUCT_QUERY='''query MyQuery {
  products {
    nodes {
      defaultVariant {
        inventoryCount
      }
    }
  }
}'''



REALM = "Misarch"
CLIENT_ID = "frontend"
USERNAME = "gatling"
PASSWORD = "123"


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
		
def login(cluster_url: str):
    url = f"{cluster_url}/keycloak/realms/{REALM}/protocol/openid-connect/token"
    data = urllib.parse.urlencode({
        "grant_type": "password",
        "client_id": CLIENT_ID,
        "username": USERNAME,
        "password": PASSWORD,
    }).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/x-www-form-urlencoded"
        },
        method="POST",
    )
    with urllib.request.urlopen(request) as response:
        return json.loads(response.read().decode("utf-8"))

def refresh(cluster_url: str, refresh_token: str):
    url = f"{cluster_url}/keycloak/realms/{REALM}/protocol/openid-connect/token"
    data = urllib.parse.urlencode({
        "grant_type": "refresh_token",
        "client_id": CLIENT_ID,
        "refresh_token": refresh_token,
    }).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=data,
        headers={
            "Content-Type": "application/x-www-form-urlencoded"
        },
        method="POST",
    )

    with urllib.request.urlopen(request) as response:
        return json.loads(response.read().decode("utf-8"))


def graphql_query(cluster_url: str, tokens, query, variables=None):
    payload = json.dumps({
        "query": query,
        "variables": variables or {}
    }).encode("utf-8")

    def send_request(access_token):
        request = urllib.request.Request(
            f"{cluster_url}/api/graphql",
            data=payload,
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        with urllib.request.urlopen(request) as response:
            return json.loads(response.read().decode("utf-8"))

    try:
        return send_request(tokens["access_token"])

    except urllib.error.HTTPError as e:
        if e.code != 401:
            raise

        print("Access token expired. Refreshing...")
        new_tokens = refresh(tokens["refresh_token"])
        # Update the existing dict so the caller automatically has the new tokens
        tokens.update(new_tokens)
        return send_request(tokens["access_token"])
	
def read_terraform_output(name: str, terraform_dir=None):
	"""Read a Terraform output value from the repository root or given directory."""
	if terraform_dir is None:
		terraform_dir = REPO_ROOT
	cmd = ["terraform", "output", "-raw", name]
	try:
		result = subprocess.run(cmd, cwd=terraform_dir, capture_output=True, text=True, check=True)
		return result.stdout.strip()
	except FileNotFoundError:
		raise RuntimeError("terraform command not found; ensure Terraform is installed and on PATH")
	except subprocess.CalledProcessError as e:
		stderr = e.stderr.strip() if e.stderr else str(e)
		raise RuntimeError(f"Failed to read Terraform output '{name}': {stderr}")
		
		
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
	
def generate_experiment()->tuple[str,str]:
	'''Generates a new experiment with default values. To override the default load configuration specify a gatling config'''
	url = f"{URL}/experiment/generate?loadType=NormalLoadTest&testDuration=60&maximumArrivingUsersPerSecond=3"
	req = urllib.request.Request(url, method="POST")
	try:
		with urllib.request.urlopen(req, timeout=5) as resp:
			raw = resp.read()
			try:
				data = json.loads(raw)
			except Exception:
				data = raw.decode(errors="replace")
			return tuple(str(data).split(':'))
	except Exception as e:
		raise RuntimeError(f"Failed to generate experiment: {e}")
	

def set_json_config(config: str, e_id: str, e_version: str, url: str):
	'''Set a JSON config (Chaos Toolkit, MiSArch or global)
	
	Arguments:
	config: relative path to the config file from experiments directory or absolute path
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
	'''Set the gatling config of an experiment. Kotlin scripts and user steps CSV are base64 encoded and packaged into a JSON body'''
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
	

def wait_for_event(e_id: str, e_version: str):
	"""Wait for the first server sent event which signifies the experiment is completed
	Note: This works (somehow) but only because the function returns an requests.exceptions.MissingSchema
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
	set_json_config(
		os.path.join('profiles',config['chaosConfig']),
		e_id,
		e_version,
		f"{URL}/experiment/{e_id}/{e_version}/chaosToolkitConfig")
	set_json_config(
		os.path.join('profiles',config['misarchConfig']),
		e_id,
		e_version,
		f"{URL}/experiment/{e_id}/{e_version}/misarchExperimentConfig"
    )
	set_gatling_config(
		config['gatlingConfig'],
		e_id,
		e_version,
		f"{URL}/experiment/{e_id}/{e_version}/gatlingConfig" )
	
	start_experiment(e_id, e_version)
	wait_for_event(e_id, e_version)

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

	# CLI: expect a filename (relative to the top-level `experiments/` folder)
	parser = argparse.ArgumentParser(prog="Experiment runner", description="Run automated experiments against the MiSArch system")
	parser.add_argument('-f', '--file', required=True, help='Filename inside the experiments directory')
	args = parser.parse_args()

	path = make_path_absolute(EXPERIMENTS_DIR, args.file)

	try:
		cluster_url = read_terraform_output("global_domain")
		print(f"Terraform global_domain: {cluster_url}")
	except RuntimeError as e:
		print(f"Warning: could not read Terraform global_domain: {e}", file=sys.stderr)
		cluster_url = None

	print(f"Starting port-forward -n {KUBECTL_NAMESPACE} {KUBECTL_SVC} {LOCAL_PORT}:{REMOTE_PORT}...")
	pf_proc = start_port_forward()
	if pf_proc is None:
		print("Skipping port-forward; attempting to contact localhost directly.")
	else:
		ok = wait_for_port("127.0.0.1", LOCAL_PORT, timeout=10)
		if not ok:
			print("Port-forward did not open within timeout", file=sys.stderr)


	print(f"Opening experiment file: {path}")

	credentials = login(cluster_url)

	try:
		with open(path, 'r') as f:
			d = json.load(f)
			for experiment in d['experiments']:
				print(f"Running experiment {experiment['testName']}")
				start_products=graphql_query(cluster_url, credentials, PRODUCT_QUERY)
				start_time=datetime.datetime.now()
				
				e_id, e_version = run_experiment(experiment)
				
				end_time=datetime.datetime.now()
				end_products=graphql_query(cluster_url, credentials, PRODUCT_QUERY)
				print(f"Experiment {e_id}:{e_version} finished after {(end_time-start_time).total_seconds()}s")
				print(start_products['data']['products']['nodes'])
				print(end_products['data']['products']['nodes'])
				# export_to_csv(e_id, e_version)
				# export all config files to folder
				# expoert start and end products as json to folder
	except FileNotFoundError as e:
		print(e)
		sys.exit(2)
	except json.JSONDecodeError as e:
		print(f"Failed to parse JSON: {e}", file=sys.stderr)
		sys.exit(3)
		
        
if __name__ == "__main__":
	main()


