# Week 1 — Container Image Hardening

## Why This Matters

The vuln-bank application ships with a `python:3.9-slim` base image. It contains
a full OS with a shell, package manager, and build tools — none of which belong
in a production container. Every unnecessary package is a potential CVE.

In a Nigerian FI, a container breakout via a base image vulnerability could
expose customer transaction data. The CBN Cybersecurity Framework requires
least-privilege at every layer, including the container runtime.

---

## What You'll Do

1. Scan the current vuln-bank image — record vulnerability count
2. Refactor the Dockerfile: multi-stage build, distroless base image
3. Re-scan — compare before and after
4. Sign the hardened image with CoSign
5. Verify the signature

---

## Prerequisites

- Codespaces running with Docker
- `snyk` authenticated (`snyk auth`)
- `cosign` installed (included in `.devcontainer.json`)
- `docker` CLI available

---

## Step 1 — Baseline: Scan the Current Image

Build the current vuln-bank image and scan it with Snyk Container.

```bash
# Build from the existing Dockerfile
cd /workspaces/vuln-bank-controls
docker build -t vuln-bank:baseline .

# Scan with Snyk Container
snyk container test vuln-bank:baseline --json > baseline-scan.json

# Extract the summary
cat baseline-scan.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f\"Total vulnerabilities: {data.get('uniqueCount', 'N/A')}\")
for sev in ['critical', 'high', 'medium', 'low']:
    count = sum(1 for v in data.get('vulnerabilities', []) if v.get('severity') == sev)
    print(f\"  {sev.upper():8}: {count}\")
"
```

**Expected output (approximate):**

```
Total vulnerabilities: 142
  CRITICAL: 3
     HIGH: 28
   MEDIUM: 54
     LOW: 57
```

> These vulnerabilities come from the base image (`python:3.9-slim`), not from
> your application code. The base image carries an entire Debian userspace.

---

## Step 2 — Refactor the Dockerfile

The refactored Dockerfile uses a multi-stage build:

1. **Build stage** — uses a full `python:3.9-slim` image to install dependencies
2. **Runtime stage** — uses a minimal Chainguard/Wolfi Python image with no
   shell, no package manager, and a non-root user

Create `Dockerfile.hardened`:

```dockerfile
# Stage 1: Build
FROM python:3.9-slim AS build
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# Stage 2: Hardened runtime
FROM cgr.dev/chainguard/python:latest
WORKDIR /app

# Create a non-root user
RUN adduser -D -u 1000 appuser

# Copy only the application (not build tools)
COPY --from=build /app /app
COPY --from=build /usr/local/lib/python3.9/site-packages /usr/local/lib/python3.9/site-packages

# Ensure uploads directory exists
RUN mkdir -p /app/static/uploads && chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

EXPOSE 5000

CMD ["python", "app.py"]
```

### Build the hardened image

```bash
docker build -t vuln-bank:hardened -f Dockerfile.hardened .
```

---

## Step 3 — Re-scan and Compare

```bash
snyk container test vuln-bank:hardened --json > hardened-scan.json

# Compare
cat hardened-scan.json | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(f\"Total vulnerabilities: {data.get('uniqueCount', 'N/A')}\")
for sev in ['critical', 'high', 'medium', 'low']:
    count = sum(1 for v in data.get('vulnerabilities', []) if v.get('severity') == sev)
    print(f\"  {sev.upper():8}: {count}\")
"
```

**Expected output (approximate):**

```
Total vulnerabilities: 4
  CRITICAL: 0
     HIGH: 0
   MEDIUM: 2
     LOW: 2
```

> The Chainguard base image is built from source with only the Python runtime.
> No OS packages, no shell, no package manager. The remaining 4 findings are
> in Python libraries (your application dependencies), not the OS layer.

### Document the comparison

```bash
cat > comparison-table.md << 'EOF'
# Vulnerability Comparison: Baseline vs. Hardened

| Severity | Baseline (`python:3.9-slim`) | Hardened (Chainguard) | Reduction |
|---|---|---|---|
| CRITICAL | 3 | 0 | 100% |
| HIGH | 28 | 0 | 100% |
| MEDIUM | 54 | 2 | 96% |
| LOW | 57 | 2 | 96% |
| **Total** | **142** | **4** | **97%** |
EOF
```

---

## Step 4 — Sign the Hardened Image with CoSign

```bash
# Generate a key pair
cosign generate-key-pair

# Sign the image
cosign sign --key cosign.key ghcr.io/<your-org>/vuln-bank:hardened

# Verify the signature
cosign verify --key cosign.pub ghcr.io/<your-org>/vuln-bank:hardened
```

> If you are not pushing to a registry, you can still sign and verify locally:
> ```bash
> cosign sign --key cosign.key --local vuln-bank:hardened
> cosign verify --key cosign.pub --local vuln-bank:hardened
> ```
> Local signing attaches the signature as a local file instead of pushing to
> a registry. The cryptographic guarantee is identical.

---

## Concepts Extracted

- Base images are the largest source of container vulnerabilities
- Multi-stage builds separate build tools from runtime dependencies
- Minimal base images reduce attack surface but limit debuggability
- Image signing creates a verifiable chain of custody
- The vulnerability reduction (97% in this lab) is typical

---

## Deliverable

Submit `comparison-table.md` containing:
1. Before and after vulnerability counts (all severities)
2. The `Dockerfile.hardened` you created
3. The CoSign verification output
4. Two-sentence summary: "Which vulnerabilities came from your code vs. the
   base image? Would you use this image in production? Why or why not?"
