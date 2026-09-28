#!/usr/bin/env python3
"""Run one opt-in demo login attempt without writing credentials to reports."""
import importlib.util
import json
import os
import pathlib
import re
import subprocess
import sys
import tempfile


_spec = importlib.util.spec_from_file_location("dyn_process", pathlib.Path(__file__).with_name("dyn-process.py"))
_process = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_process)


MAESTRO_EXPR = "${"


def hierarchy(udid, dirname, env):
    result = _process.run(["maestro", "--device", udid, "hierarchy"],
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          timeout=45, cwd=dirname, env=env)
    if result.returncode:
        raise ValueError("Hierarchy unavailable")
    tree = json.loads(result.stdout.decode("utf-8", "replace"))
    values = set()
    def visit(obj):
        if isinstance(obj, dict):
            attrs = obj.get("attributes", {})
            if isinstance(attrs, dict):
                values.update(v.strip() for k, v in attrs.items()
                              if k in ("text", "accessibilityText") and isinstance(v, str))
            for child in obj.get("children", []):
                visit(child)
        elif isinstance(obj, list):
            for child in obj:
                visit(child)
    visit(tree)
    return values


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
    if (os.getenv("PRECHECK_DEMO_AUTHORIZED_TEST") != "1" or
            os.getenv("PRECHECK_DEMO_ENVIRONMENT") not in ("test", "sandbox")):
        return "SKIP\tdemo login requires explicit authorized test/sandbox environment"
    # Maestro evaluates ${...} as JavaScript inside string parameters and documents no
    # escape, so a value carrying the marker would be evaluated or mangled. Refuse it.
    # Only the field NAME is reported, never the value.
    for what, value in (("username", user), ("password", password), ("username field label", user_field),
                        ("password field label", password_field), ("submit label", submit),
                        ("bundle id", bundle)):
        if MAESTRO_EXPR in value:
            return ("SKIP\tdemo " + what + " contains '${', which Maestro would evaluate as JavaScript; "
                    "login not attempted (choose a demo value without that marker)")
    flow = ("appId: " + json.dumps(bundle) + "\n---\n" +
            "- tapOn: " + json.dumps("^" + re.escape(user_field) + "$") + "\n" +
            "- inputText: " + json.dumps(user) + "\n" +
            "- tapOn: " + json.dumps("^" + re.escape(password_field) + "$") + "\n" +
            "- inputText: " + json.dumps(password) + "\n" +
            "- tapOn: " + json.dumps("^" + re.escape(submit) + "$") + "\n")
    try:
        with tempfile.TemporaryDirectory(prefix="appstore-demo-") as dirname:
            path = pathlib.Path(dirname) / "login.yaml"
            path.write_text(flow)
            path.chmod(0o600)
            env = dict(os.environ, MAESTRO_CLI_NO_ANALYTICS="1")
            # Every driver artifact containing typed values remains disposable.
            debug = pathlib.Path(dirname) / "debug"
            output = pathlib.Path(dirname) / "output"
            before = hierarchy(udid, dirname, env)
            if (len(before) < 4 or not {user_field, password_field, submit}.issubset(before) or
                    success in before or success == failure):
                return "SKIP\tlogin start state/selectors are ambiguous or unavailable"
            run = _process.run(["maestro", "--device", udid, "test",
                                "--debug-output", str(debug), "--test-output-dir", str(output), str(path)],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                 timeout=45, cwd=dirname, env=env)
            if run.returncode:
                return "SKIP\tMaestro could not drive demo login; selectors or driver may be unavailable"
            values = hierarchy(udid, dirname, env)
            if len(values) < 4 or (success in values and failure in values):
                return "SKIP\tlogin postcondition is ambiguous or accessibility evidence is insufficient"
            if success in values:
                return "PASS\tdemo start/action/new success selector observed; backend session scope requires review"
            if failure in values:
                return "SKIP\tlogin rejection observed; backend and account validity require independent evidence"
            return "SKIP\tneither success nor explicit failure selector observed"
    except (OSError, subprocess.TimeoutExpired, subprocess.CalledProcessError, ValueError):
        return "SKIP\tdemo driver timed out or hierarchy was unreadable"


if __name__ == "__main__":
    print(main())
