#! /bin/bash

# Test Case 5
# - pr-location: non-fork
# - commits: 2
# - merge-strategy: rebase
# - workflow: backport-pr-closed.yml
# - expects: 1 backport pr opened

# When run this test will:
# - create a branch from main as backport target
# - create a branch from main for new changes
# - add two commits to new
# - open a pull request to merge it to main
# - merge the pull request using rebase
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
  git branch case5-backport-target
  git push -u origin case5-backport-target

  # create a branch from main for new changes
  git branch case5-new-changes
  git checkout case5-new-changes

  # add a commit to new
  mkdir case5
  echo "A changed line is added" >> case5/file1
  git add case5/file1
  git commit -m "case(5): add changed line"
  echo "Another changed line is added" >> case5/file1
  git add case5/file1
  git commit -m "case(5): add another changed line"
  git push -u origin case5-new-changes

  # open a pull request to merge it to main
  gh pr create \
    --head case5-new-changes \
    --base main \
    --title "case(5): Rebase and merge" \
    --body "Adds some changed lines" \
    --label 'backport case5-backport-target' \
    --label 'should_copy'

  # rebase and merge the pull request
  gh pr merge \
    --rebase \
    --auto

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
  backport_prs=$(gh pr list --base case5-backport-target --json number --jq 'length')
  if [ ! 1 -eq "$backport_prs" ]; then
    echoerr "expected 1 open backport pr for case5, but found $backport_prs open prs"
    exit 20
  fi

  # find the backport_branch for later cleanup
  backport_branch=$(gh pr list --base case5-backport-target --json headRefName --jq 'first | .headRefName')

  # check that backport pull request contains two cherry picked commits
  local backport_commit_matches
  backport_commit_matches=$(gh pr list \
    --base case3-backport-target \
    --json commits \
    --jq "first | .commits | map(.messageBody) | match(\".*cherry picked from commit ([a-f0-9]+)\") | .captures[].string | length")
  if [ ! 2 -eq "$backport_commit_matches" ]; then
    echoerr "expected 2 cherry picked commits, but found cherry-picks for the following commits $backport_commit_matches"
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
  deleteBranch case5-backport-target
  deleteBranch "$backport_branch"
  revertCommit "$mergeCommit"
  revertCommit "$mergeCommit^"
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
