#! /bin/bash

# Test Case 3
# - pr-location: non-fork
# - commits: 2
# - merge-strategy: squash
# - workflow: backport-pr-closed.yml
# - expects: 1 backport pr opened

# When run this test will:
# - create a branch from main as backport target
# - create a branch from main for new changes
# - add two commits to new
# - open a pull request to merge it to main
# - merge the pull request using squash
# - find the commit sha of the commit that merged the pr
# - find the commit sha of the head of the pr
# - find the backport-pr-closed.yml workflow run on pull_request[closed]
# - wait for workflow to finish
# - check that backport pull request is opened to target
# - check that backport pull request contains cherry picked commits
# - cleanup: revert merge to main, close backport-pr and delete both new branches

# Non-zero exitcodes:
# 10: Unable to find backport workflow run caused by merging a PR after trying for 60 seconds
# 20: Unable to find backport pr (expected only 1, but is either none, or multiple)
# 30: Backport pr does not contain expected cherry picked commits
function main() {
  name="github-actions[bot]"
  email="github-actions[bot]@users.noreply.github.com"
  export GIT_AUTHOR_NAME="$name"
  export GIT_AUTHOR_EMAIL="$email"
  export GIT_COMMITTER_NAME="$name"
  export GIT_COMMITTER_EMAIL="$email"

  # create a branch from main as backport target
  git branch case3-backport-target
  git push -u origin case3-backport-target

  # create a branch from main for new changes
  git branch case3-new-changes
  git checkout case3-new-changes

  # add a commit to new
  mkdir case3
  echo "A changed line is added" >> case3/file1
  git add case3/file1
  git commit -m "case(3): add changed line"
  echo "Another changed line is added" >> case3/file1
  git add case3/file1
  git commit -m "case(3): add another changed line"
  git push -u origin case3-new-changes

  # open a pull request to merge it to main
  gh pr create \
    --head case3-new-changes \
    --base main \
    --title "case(3): Squash and merge" \
    --body "Adds a changed line" \
    --label 'backport case3-backport-target' \
    --label 'should_copy'

  # squash and merge the pull request
  gh pr merge \
    --squash \
    --auto \
    --subject "case(3): squash and merge pull request"

  # find the commit sha of the commit that merged the pr
  mergeCommit=$(gh pr view --json mergeCommit --jq '.mergeCommit.oid')

  # find the commit sha of the head of the pr
  local headSha
  headSha=$(gh pr view --json commits --jq '.commits | map(.oid) | last' | cat)

  # find the backport-pr-closed.yml workflow run on pull_request[closed]
  local backport_run_id
  local checks_index=0
  while [ -z "$backport_run_id" ]; do
    sleep 1
    findBackportRun "$headSha"
    (("checks_index+=1"))
    if [ "$checks_index" -gt 60 ]; then
      exit 10
    fi
  done
  echo "found backport-pr-closed workflow run: $backport_run_id"

  # wait for workflow to finish
  gh run watch "$backport_run_id" \
    && echo "backport-pr-closed workflow run $backport_run_id finished"

  # check that backport pull request is opened to target
  local backport_prs
  backport_prs=$(gh pr list --base case3-backport-target --json number --jq 'length')
  if [ ! 1 -eq "$backport_prs" ]; then
    echoerr "expected 1 open backport pr for case3, but found $backport_prs open prs"
    exit 20
  fi

  # find the backport_branch for later cleanup
  backport_branch=$(gh pr list --base case3-backport-target --json headRefName --jq 'first | .headRefName')

  # check that backport pull request contains cherry picked commits
  local backport_commit_matches
  backport_commit_matches=$(gh pr list \
    --base case3-backport-target \
    --json commits \
    --jq "first | .commits | map(.messageBody | match(\".*cherry picked from commit $mergeCommit.*\")) | length")
  if [ ! 1 -eq "$backport_commit_matches" ]; then
    echoerr "expected 1 cherry picked commit for $mergeCommit, but found $backport_commit_matches"
    exit 30
  fi
}

# Find the run of the backport workflow that was triggered for a specific head sha
# Usage findBackportRun $expectedHeadSha
# Sets the backport_run_id variable when found, otherwise does nothing
function findBackportRun() {
  local wf_id
  wf_id=$(gh run list \
      --workflow backport-pr-closed.yml \
      --json headSha,databaseId \
      --limit 10 \
      --jq "map(select(.headSha == \"$1\")) | first | \"\(.databaseId)\"")
  if [ ! "$wf_id" = "null" ]; then
    backport_run_id="$wf_id"
  fi
}

function echoerr() {
  printf "%s\n" "$*" >&2;
}

function cleanup() {
  set +e
  git checkout main
  deleteBranch case3-backport-target
  deleteBranch "$backport_branch"
  revertCommit "$mergeCommit"
  # we do not have to close the backport pr
  # it closes automatically when we delete its target branch
}

function deleteBranch() {
  if [ -n "$1" ]; then
    git branch --delete "$1"
    git push origin --delete "$1"
  fi
}

function revertCommit() {
  if [ -n "$1" ]; then
    git pull
    git revert --mainline 1 "$1" --no-edit
    git push
  fi
}

# Initialise clean up
mergeCommit=""
backport_branch=""
trap 'cleanup' EXIT

# Run script
set -ex
main
