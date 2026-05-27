# Week 5 — Supply Chain Integrity: Measuring and Improving Trust

## Why This Matters

SLSA (Supply-chain Levels for Software Artifacts) is a framework that tells you
how trustworthy your software supply chain is. Level 1 means "we use version
control." Level 4 means "every build is hermetic, reproducible, and fully
attested."

Most Nigerian FIs operate at SLSA Level 1 — source code is in Git, but builds
are manual or poorly attested. The CBN Cybersecurity Framework (Domain 2.4)
and global regulations (US Executive Order 14028) are moving toward requiring
supply chain attestation.

---

## What You'll Do

1. Map the Course 1 capstone pipeline to SLSA levels
2. Identify gaps to reach the next level
3. Generate a SLSA provenance attestation
4. Document current vs. target SLSA level

---

## Prerequisites

- Understanding of the Course 1 capstone pipeline (6 security gates)
- Access to a GitHub repository (any public repo will work)

---

## Step 1 — Map Controls to SLSA Levels

Open the SLSA mapping template:

```bash
cat templates/slsa-mapping-template.csv
```

The template contains the 6 Course 1 capstone gates plus 4 additional
controls from Course 2. For each one, identify the SLSA level it
satisfies.

### SLSA Level Reference

| Level | Requirements | How to Achieve |
|---|---|---|
| **L1** | Source code version-controlled | Code in GitHub/GitLab with history |
| **L2** | Build is automated, provenance generated | CI/CD pipeline generates build metadata |
| **L3** | Source and build steps verified, provenance authenticated | Image signing + verified provenance attestation |
| **L4** | Hermetic + reproducible builds | Build in isolated environment, pinned deps, identical output |

### Fill the template

For each control in the template:

1. Check whether your pipeline implements it
2. Determine which SLSA level the control satisfies
3. Note what evidence supports the claim

**Example row (filled):**

| Control | Does Your Pipeline Have It? | SLSA Level | Evidence |
|---|---|---|---|
| Source code version-controlled | Yes | L1 | GitHub repository with commit history |
| Build pipeline automated | Yes | L2 | GitHub Actions workflow |
| Image signed with CoSign | Yes | L3 | Cosign signature on GHCR image |
| Hermetic build | No | — | Missing — would need isolated build env |

---

## Step 2 — Gap Analysis

Use the gap analysis template to identify what's missing for the next level.

```bash
cat templates/slsa-gap-analysis-template.md
```

### Typical gaps for the Course 1 pipeline

| Current Level | Next Level | Gap | How to Close |
|---|---|---|---|
| L2 → L3 | L3 | No provenance attestation | Add `actions/attest-build-provenance` to the workflow |
| L2 → L3 | L3 | Build process not verified | Pin all GitHub Actions to SHA hashes instead of version tags |
| L3 → L4 | L4 | Build not hermetic | Use hermetic build container with no network access |
| L3 → L4 | L4 | Build not reproducible | Pin all dependency versions, lock dependency trees |

---

## Step 3 — Generate SLSA Provenance

SLSA provenance is a cryptographically signed attestation that records exactly
how a build artifact was produced.

### Using the GitHub SLSA generator

Add this step to any GitHub Actions workflow that produces a container image:

```yaml
# Add to your workflow after the image is built and pushed
- name: Generate SLSA provenance
  uses: actions/attest-build-provenance@v1
  with:
    subject-name: ghcr.io/${{ github.repository_owner }}/vuln-bank
    subject-digest: sha256:${{ steps.build-image.outputs.digest }}
    push-to-registry: true
```

For a workflow that doesn't push to a registry, use:

```yaml
- name: Generate SLSA provenance
  uses: actions/attest-build-provenance@v1
  with:
    subject-path: "${{ runner.temp }}/image.tar"
```

### Verify the attestation

```bash
gh attestation verify oci://ghcr.io/<your-org>/vuln-bank:latest --owner <your-org>
```

**Expected output:**

```
Loaded attestation 1:
  - Subject: ghcr.io/<your-org>/vuln-bank@sha256:abc123...
  - Issuer: https://token.actions.githubusercontent.com
  - Build: https://github.com/<your-org>/<your-repo>/actions/runs/12345
  - Source: https://github.com/<your-org>/<your-repo>.git
  - SLSA Level: 3
```

---

## Step 4 — Document the Assessment

Create `slsa-assessment.md`:

```markdown
# SLSA Assessment Report

## Summary
- Current SLSA level: L2
- Target SLSA level: L3
- Gap to close: Provenance attestation

## Control Mapping

| Control | Present | SLSA Level | Evidence |
|---|---|---|---|
| Source version control | Yes | L1 | GitHub repo |
| Automated build | Yes | L2 | GitHub Actions workflow |
| Image signing | Yes | L3 | Cosign signature |
| Provenance attestation | No | — | Missing |
| Hermetic build | No | — | Missing |

## Gap Remediation Plan

1. Add `actions/attest-build-provenance` to the build workflow
2. Pin all GitHub Actions to SHA hashes
3. Review hermetic build requirements for L4

## Next Target

SLSA Level 3 is achievable with these changes. Level 4 requires
infrastructure investment (hermetic build environment, dependency
pinning, reproducible builds).
```

---

## Concepts Extracted

- SLSA provides a structured maturity model for supply chain security
- Image signing contributes to SLSA L3 but is not sufficient alone
- Provenance attestation is the evidence that links an artifact to its build
- Hermetic builds are the hardest requirement (L4)
- Most teams should target L2–L3; L4 is aspirational

---

## Deliverable

Submit `slsa-assessment.md` containing:
1. Current and target SLSA levels
2. Completed control mapping table (at least 8 rows)
3. Gap analysis with remediation steps
4. The GitHub Actions provenance workflow snippet
5. The output of `gh attestation verify`
6. Three-sentence summary: "What SLSA level is the pipeline at today? What
   is needed to reach the next level? Is that investment justified for your
   organisation?"
