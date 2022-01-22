#! /bin/bash

# When run this test will:
# - create a branch from main as backport target
# - create a branch from main for new changes
# - add a commit to new
# - open a pull request to merge it to main
# - merge the pull request
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
  git branch case1-backport-target
  git push -u origin case1-backport-target

  # create a branch from main for new changes
  git branch case1-new-changes
  git checkout case1-new-changes

  # add a commit to new
  mkdir case1
  echo "A changed line is added" >> case1/file1
  git add case1/file1
  git commit -m "case(1): add changed line"
  git push -u origin case1-new-changes

  # open a pull request to merge it to main
  gh pr create \
    --head case1-new-changes \
    --base main \
    --title "Case(1): Add a changed line" \
    --body "Adds a changed line" \
    --label 'backport case1-backport-target'

  # merge the pull request
  gh pr merge \
    --merge \
    --subject "case(1): merge pull request"

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
  backport_prs=$(gh pr list --base case1-backport-target --json number --jq 'length')
  if [ ! 1 -eq "$backport_prs" ]; then
    echoerr "expected 1 open backport pr for case1, but found $backport_prs open prs"
    exit 20
  fi

  # check that backport pull request contains cherry picked commits
  local backport_commit_matches
  backport_commit_matches=$(gh pr list \
    --base case1-backport-target \
    --json commits \
    --jq "first | .commits | map(.messageBody | match(\".*cherry picked from commit $headSha.*\")) | length")
  if [ ! 1 -eq "$backport_commit_matches" ]; then
    echoerr "expected 1 cherry picked commit for $headSha, but found $backport_commit_matches"
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
  deleteBranch case1-backport-target
  deleteBranch case1-new-changes
  revertCommit "$mergeCommit"
  # we do not have to close the backport pr
  # it closes automatically when we delete its target branch
}

function deleteBranch() {
  git branch --delete "$1"
  git push origin --delete "$1"
}

function revertCommit() {
  if [ ! -z "$1" ]; then
    git pull
    git revert --mainline 1 "$1" --no-edit
    git push
  fi
}

set -ex
mergeCommit=""
trap 'cleanup' EXIT
main
