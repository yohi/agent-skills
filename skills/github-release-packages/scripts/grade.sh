#!/bin/bash
set -euo pipefail

# Grade assertions for github-release-packages skill
# Usage: grade.sh <eval_dir>

EVAL_DIR="$1"
OUTPUTS_DIR="$EVAL_DIR/outputs"
METADATA="$EVAL_DIR/eval_metadata.json"
GRADING="$EVAL_DIR/grading.json"

echo "Grading $EVAL_DIR..." >&2

# Initialize grading.json
echo '{"expectations": []}' > "$GRADING"

# Read assertions and check each one
python3 << EOF
import json
import os
import re

metadata_path = "$METADATA"
outputs_dir = "$OUTPUTS_DIR"
grading_path = "$GRADING"

with open(metadata_path) as f:
    metadata = json.load(f)

expectations = []

for assertion in metadata.get("assertions", []):
    name = assertion["name"]
    text = assertion["text"]
    check = assertion["check"]
    
    passed = False
    evidence = ""
    
    try:
        if check.startswith("file_exists:"):
            filepath = check.split(":", 1)[1]
            full_path = os.path.join(outputs_dir, filepath)
            passed = os.path.exists(full_path)
            evidence = f"File {'exists' if passed else 'does not exist'}: {filepath}"
        
        elif check.startswith("contains:"):
            parts = check.split(":", 2)
            filepath = parts[1]
            expected = parts[2]
            full_path = os.path.join(outputs_dir, filepath)
            if os.path.exists(full_path):
                with open(full_path) as f:
                    content = f.read()
                passed = expected in content
                evidence = f"{'Found' if passed else 'Did not find'} '{expected}' in {filepath}"
            else:
                passed = False
                evidence = f"File does not exist: {filepath}"
    except Exception as e:
        passed = False
        evidence = f"Error checking assertion: {str(e)}"
    
    expectations.append({
        "text": text,
        "passed": passed,
        "evidence": evidence
    })

with open(grading_path, 'w') as f:
    json.dump({"expectations": expectations}, f, indent=2)

passed_count = sum(1 for e in expectations if e["passed"])
total_count = len(expectations)
print(f"Graded: {passed_count}/{total_count} passed")
EOF

echo "Grading complete. Results saved to $GRADING" >&2
