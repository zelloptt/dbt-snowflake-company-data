# Repo Setup

Delete this file after the first commit. It is bootstrap instructions, not package documentation.

---

## Create the repo

```bash
gh repo create zelloptt/dbt-snowflake-company-data \
  --private \
  --description "dbt package for Snowflake's free public company data: staging models, resolved company entities, and fuzzy matching to join your own accounts." \
  --disable-wiki
```

Then from this directory:

```bash
git init -b main
git add .
git commit -m "chore: scaffold package repo

Apache 2.0, Snowflake-only, targets dbt >=1.10 <3.0 for Fusion compatibility.
Conventions and known data traps recorded in CLAUDE.md."
git remote add origin git@github.com:zelloptt/dbt-snowflake-company-data.git
git push -u origin main
```

## Repo settings

```bash
R=zelloptt/dbt-snowflake-company-data

# Squash-only merges, auto-delete branches. Matches zello-desktop's convention
# and keeps the history readable, which matters because hubcap reviews it.
gh api -X PATCH repos/$R \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -F has_projects=false \
  -F has_wiki=false

# Topics. These drive GitHub search once the repo is public.
gh api -X PUT repos/$R/topics \
  -f names[]=dbt -f names[]=dbt-package -f names[]=snowflake \
  -f names[]=analytics-engineering -f names[]=entity-resolution \
  -f names[]=company-data -f names[]=sec-filings -f names[]=sql

# Secret scanning and push protection. Turn these on now, not at flip time:
# push protection blocks a credential from entering history in the first place,
# which is the only fix that actually works.
gh api -X PATCH repos/$R \
  -f 'security_and_analysis[secret_scanning][status]=enabled' \
  -f 'security_and_analysis[secret_scanning_push_protection][status]=enabled'
```

Branch protection on `main` (add once CI exists, since required checks reference workflow names):

```bash
gh api -X PUT repos/$R/branches/main/protection \
  -f 'required_pull_request_reviews[required_approving_review_count]=1' \
  -f 'required_pull_request_reviews[require_code_owner_reviews]=true' \
  -F 'enforce_admins=false' \
  -F 'required_linear_history=true' \
  -F 'allow_force_pushes=false' \
  -F 'allow_deletions=false'
```

## Give the team access

```bash
# Preferred: create a team once, manage membership there.
gh api -X PUT orgs/zelloptt/teams/data/repos/zelloptt/dbt-snowflake-company-data -f permission=push

# Or individually, using usernames from the org directory:
for u in pestrov natefilipek stone-yehuda bruschke; do
  gh api -X PUT repos/zelloptt/dbt-snowflake-company-data/collaborators/$u -f permission=push
done
```

If you create the `data` team, update `.github/CODEOWNERS` to `* @zelloptt/data` so membership changes stop requiring a PR.

## Before flipping to public

Git history is preserved across the visibility flip. Everything below is about the fact that you cannot un-commit a secret, you can only rotate it.

```bash
# 1. Nothing that looks like a credential, anywhere in history
git log --all -p | grep -inE 'password|secret|private_key|BEGIN [A-Z ]*PRIVATE KEY|account *[:=]|snowflakecomputing\.com' | head -50

# 2. No profiles.yml or key material ever tracked
git log --all --name-only --format='' | sort -u | grep -iE 'profiles\.yml$|\.p8$|\.pem$|\.env$'

# 3. Largest blobs in history, to catch a data extract someone committed once
git rev-list --objects --all \
  | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' \
  | awk '$1=="blob"' | sort -k3 -nr | head -20
```

Then review by hand:

- **Seeds.** Any CSV derived from the Snowflake share is redistribution and Apache 2.0 does not cover it. Fixtures must be synthetic. A SIC code reference seed is fine because SIC is a US government classification.
- **`DISCOVERY.md`.** It will contain your database name and row counts. Neither is sensitive, but scrub any account identifier or internal schema name that crept in.
- **Commit messages and branch names.** Zello convention puts Jira keys in branches (`feature/DATA-123-...`). Squash merges usually carry the PR title into the commit, so decide now whether Jira keys in public history bother you. If they do, keep them out of PR titles from the start; rewriting later is worse than not doing it.
- **CODEOWNERS.** GitHub usernames only, never email addresses.
- **Issue and PR history.** Private-repo issues become public too. Anything internal discussed in an issue is published.

If a credential does land in history, rotate it. Do not rely on rewriting history; forks and caches survive it.

## What is deliberately not here yet

These arrive during the build, not at scaffold time:

- `.github/workflows/` (CI, Fusion lane, auto-release)
- Models, macros, seeds, tests
- `DISCOVERY.md` (written by Phase 0, before any SQL)
- `integration_tests/dbt_project.yml` and fixtures

The `.gitkeep` files hold the directory shape. Delete each one as its directory gets real contents.
