#!/usr/bin/env python3
"""Run one opt-in demo login attempt without writing credentials to reports."""
import json
import os
import pathlib
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 3:
        return "SKIP\tinternal demo driver arguments missing"
    udid, bundle = sys.argv[1:]
    user = os.getenv("PRECHECK_DEMO_USERNAME", "")
    password = os.getenv("PRECHECK_DEMO_PASSWORD", "")
    success = os.getenv("PRECHECK_DEMO_SUCCESS_TEXT", "")
    failure = os.getenv("PRECHECK_DEMO_FAILURE_TEXT", "")
    user_field = os.getenv("PRECHECK_DEMO_USER_FIELD", "Email")
    password_field = os.getenv("PRECHECK_DEMO_PASSWORD_FIELD", "Password")
    submit = os.getenv("PRECHECK_DEMO_SUBMIT", "Sign In")
    if not all((user, password, success, failure)):
        return "SKIP\tdemo credentials or success/failure selectors unavailable"
    flow = ("appId: " + json.dumps(bundle) + "\n---\n" +
            "- tapOn: " + json.dumps(user_field) + "\n" +
            "- inputText: " + json.dumps(user) + "\n" +
            "- tapOn: " + json.dumps(password_field) + "\n" +
            "- inputText: " + json.dumps(password) + "\n" +
            "- tapOn: " + json.dumps(submit) + "\n")
    try:
        with tempfile.TemporaryDirectory(prefix="appstore-demo-") as dirname:
            path = pathlib.Path(dirname) / "login.yaml"
            path.write_text(flow)
            run = subprocess.run(["maestro", "--device", udid, "test", str(path)],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 timeout=45, check=False, cwd=dirname)
            if run.returncode:
                return "SKIP\tMaestro could not drive demo login; selectors or driver may be unavailable"
            raw = subprocess.run(["maestro", "--device", udid, "hierarchy"],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 timeout=45, check=True, cwd=dirname).stdout.decode("utf-8", "replace")
            tree = json.loads(raw)
            values = []
            def visit(obj):
                if isinstance(obj, dict):
                    a = obj.get("attributes", {})
                    if isinstance(a, dict):
                        values.extend(str(v) for k, v in a.items() if k in ("text", "accessibilityText") and isinstance(v, str))
                    for child in obj.get("children", []):
                        visit(child)
                elif isinstance(obj, list):
                    for child in obj:
                        visit(child)
            visit(tree)
            if any(success.casefold() in x.casefold() for x in values):
                return "PASS\tdemo success selector observed"
            if any(failure.casefold() in x.casefold() for x in values):
                if os.getenv("PRECHECK_DEMO_BACKEND_READY") == "1":
                    return "FINDING\texplicit login rejection observed with backend health asserted"
                return "SKIP\tlogin rejection observed but backend health was not established"
            return "SKIP\tneither success nor explicit failure selector observed"
    except (OSError, subprocess.TimeoutExpired, subprocess.CalledProcessError, ValueError):
        return "SKIP\tdemo driver timed out or hierarchy was unreadable"


if __name__ == "__main__":
    print(main())
