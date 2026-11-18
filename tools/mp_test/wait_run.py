"""mp-retest: waits for the multiplayer test started at <epoch> to end, then saves its logs.
python wait_run.py <name> <start epoch> [max seconds]
Writes <scratch>/<name>_server.log (the [MPT] lines), <name>_server_raw.log (every line of the test server's log),
<name>_client_<n>_raw.log (every line of each test client's log) and prints the CHECK lines and a count of
warnings and errors per raw log.
"""
import glob, os, re, sys, time, subprocess

name = sys.argv[1]
start = float(sys.argv[2])
limit = float(sys.argv[3]) if len(sys.argv) > 3 else 420
out_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
log_dir = os.path.join(os.environ["LOCALAPPDATA"], "Roblox", "logs")


def read(p):
    try:
        return open(p, encoding="utf-8", errors="replace").read()
    except Exception:
        return ""


def recent():
    return [p for p in glob.glob(os.path.join(log_dir, "*_Studio_*_last.log")) if os.path.getctime(p) >= start - 3]


t0 = time.time()
server = None
while time.time() - t0 < limit:
    if not server:
        for p in recent():
            if re.search(r"\[MPT\] 0001 ", read(p)):
                server = p
                break
    if server and "ENDTEST" in read(server):
        break
    time.sleep(2)
if not server:
    print("NO SERVER LOG within", limit, "s")
    sys.exit(1)
time.sleep(6)  # the processes close
text = read(server)
ended = "ENDTEST" in text
mpt = [l[l.index("[MPT]"):] for l in text.splitlines() if "[MPT]" in l]
open(os.path.join(out_dir, name + "_server.log"), "w", encoding="utf-8").write("\n".join(mpt))
open(os.path.join(out_dir, name + "_server_raw.log"), "w", encoding="utf-8").write(text)
print("server log %s: %d MPT lines, ended=%s, took %.0f s" % (os.path.basename(server), len(mpt), ended, time.time() - t0))
n = 0
for p in sorted(recent(), key=os.path.getctime):
    if p == server:
        continue
    t = read(p)
    m = re.search(r"\[MPT\]\[C:([A-Za-z0-9_]+)\]", t)
    if not m:
        continue
    n += 1
    open(os.path.join(out_dir, "%s_client_%s_raw.log" % (name, m.group(1))), "w", encoding="utf-8").write(t)
for l in mpt:
    if "[CHECK]" in l or "DRIVER ERROR" in l or "RESULTS" in l or "ENDTEST" in l:
        print(l[:1100])
try:
    ps = subprocess.run(["powershell", "-NoProfile", "-Command",
                         "(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'RobloxStudioBeta.exe' -and $_.CommandLine -match '-task Start(Server|Client)' } | Measure-Object).Count; '{0:N1}' -f ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory/1MB)"],
                        capture_output=True, text=True, timeout=60)
    print("test processes left / free GB:", " ".join(ps.stdout.split()))
except Exception as e:
    print("process check failed", e)
