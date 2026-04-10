#!/bin/bash
# ============================================================
# Pre-Release Safety Check
# Blocks releases if safety violations are detected.
# Usage: bash scripts/pre_release_check.sh [project_dir]
# ============================================================

set -e

PROJECT_DIR="${1:-.}"

echo "[pre-release] Starting safety checks for: $(cd "$PROJECT_DIR" && pwd)"
echo "========================================"

EXIT_CODE=0

# 1. Run safety checker
echo ""
echo "[1/5] Running safety scanner..."
CHECKER="$(dirname "$0")/check_project_safety.py"
if [ -f "$CHECKER" ]; then
    if ! python3 "$CHECKER" --dir "$PROJECT_DIR" --skip-required 2>&1; then
        echo "[pre-release] ❌ Safety scan FAILED - blocking release"
        EXIT_CODE=1
    else
        echo "[pre-release] ✅ Safety scan passed"
    fi
else
    echo "[pre-release] ⚠️  check_project_safety.py not found, skipping"
fi

# 2. Check required documentation
echo ""
echo "[2/5] Checking documentation..."
for file in README.md SKILL.md skill.json; do
    if [ ! -f "$PROJECT_DIR/$file" ]; then
        echo "[pre-release] ❌ Missing: $file"
        EXIT_CODE=1
    else
        echo "[pre-release] ✅ $file exists"
    fi
done

# 3. Check .env.example exists
echo ""
echo "[3/5] Checking credential template..."
if [ ! -f "$PROJECT_DIR/.env.example" ]; then
    echo "[pre-release] ❌ Missing: .env.example - users have no credential template"
    EXIT_CODE=1
else
    echo "[pre-release] ✅ .env.example exists"
    # Verify .env.example has no real secrets
    if grep -E "github_pat_|ghp_[a-zA-Z0-9]{36}|sk-[a-zA-Z0-9]{20,}|ufFAY[A-Za-z0-9]{10,}" "$PROJECT_DIR/.env.example" >/dev/null 2>&1; then
        echo "[pre-release] ❌ .env.example contains what looks like a real secret - use placeholder values"
        EXIT_CODE=1
    fi
fi

# 4. Check no .env or secrets are tracked in git
echo ""
echo "[4/5] Checking git for accidentally committed secrets..."
if [ -d "$PROJECT_DIR/.git" ]; then
    TRACKED=$(cd "$PROJECT_DIR" && git ls-files 2>/dev/null | grep -E "^\.env$|config/\.env|secrets\.|credential" || true)
    if [ -n "$TRACKED" ]; then
        echo "[pre-release] ❌ Tracked secret files found:"
        echo "$TRACKED" | while read -r f; do echo "  - $f"; done
        EXIT_CODE=1
    else
        echo "[pre-release] ✅ No secret files tracked in git"
    fi

    # Check staged/committed secrets in recent commits
    if cd "$PROJECT_DIR" && git log --oneline -5 2>/dev/null | head -3; then
        RECENT_SECRETS=$(cd "$PROJECT_DIR" && git log -p --name-only -3 2>/dev/null | grep -E "github_pat_|ghp_|ufFAY|sk-[a-zA-Z0-9]{20,}" || true)
        if [ -n "$RECENT_SECRETS" ]; then
            echo "[pre-release] ⚠️  Recent commits may contain secrets (run git filter-repo to clean)"
        fi
    fi
fi

# 5. Check .gitignore exists
echo ""
echo "[5/5] Checking .gitignore..."
if [ ! -f "$PROJECT_DIR/.gitignore" ]; then
    echo "[pre-release] ❌ Missing: .gitignore - credentials may leak"
    EXIT_CODE=1
else
    echo "[pre-release] ✅ .gitignore exists"
fi

# Summary
echo ""
echo "========================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo "[pre-release] ✅ ALL CHECKS PASSED - release allowed"
else
    echo "[pre-release] ❌ SAFETY CHECKS FAILED - release BLOCKED"
    echo "[pre-release] Fix the issues above before releasing"
fi

exit $EXIT_CODE
