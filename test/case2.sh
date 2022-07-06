#! /bin/bash

# Test Case 2
# - pr-location: fork
# - commits: 1
# - merge-strategy: merge commit
# - workflow: backport-pr-target-closed.yml
# - expects: 1 backport pr opened

# This test is expected to be run in a checked out forked repo
# It also expects that the forked repo is in sync or at least close to origin

# When run this test will:
# - create a branch from main as backport target
# - create a branch from main for new changes
# - add a commit to new
# - open a pull request to merge it to main on origin
# - merge the pull request
# - find the commit sha of the commit that merged the pr
# - find the commit sha of the head of the pr
# - find the backport-pr-target-closed.yml workflow run on pull_request[closed]
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

  # add the upstream repo as upstream
  # the gh cli will use the knowledge of both origin and upstream remotes
  # to determine where to create the pr
  git remote add --fetch \
    upstream https://github.com/korthout/backport-action-test.git

  # assume that a branch exists on origin as backport target
  # git branch case2-backport-target
  # git push -u origin case2-backport-target

  # create a branch from main for new changes
  git branch case2-new-changes
  git checkout case2-new-changes

  # add a commit to new
  mkdir case2
  echo "A changed line is added" >> case2/file1
  git add case2/file1
  git commit -m "case(2): add changed line"
  git push -u origin case2-new-changes

  # open a pull request to upstream
  gh pr create \
    --head backport-action:case2-new-changes \
    --title "Case(2): Add a changed line" \
    --body "Adds a changed line" \
    --label 'backport case2-backport-target'

  # merge the pull request
  gh pr merge \
    --merge \
    --subject "case(2): merge pull request"

  # find the commit sha of the commit that merged the pr
  mergeCommit=$(gh pr view --json mergeCommit --jq '.mergeCommit.oid')

  # find the commit sha of the head of the pr
  headSha=$(gh pr view --json commits --jq '.commits | map(.oid) | last' | cat)

  # find the backport-pr-target-closed.yml workflow run on pull_request[closed]
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
  echo "found backport-pr-target-closed workflow run: $backport_run_id"

  # wait for workflow to finish
  gh run watch "$backport_run_id" \
    && echo "backport-pr-target-closed workflow run $backport_run_id finished"

  # check that backport pull request is opened to target
  local backport_prs
  backport_prs=$(gh pr list --base case2-backport-target --json number --jq 'length')
  if [ ! 1 -eq "$backport_prs" ]; then
    echoerr "expected 1 open backport pr for case2, but found $backport_prs open prs"
    exit 20
  fi

  # find the backport_branch for later cleanup
  backport_branch=$(gh pr list --base case2-backport-target --json headRefName --jq 'first | .headRefName')

  # check that backport pull request contains cherry picked commits
  local backport_commit_matches
  backport_commit_matches=$(gh pr list \
    --base case2-backport-target \
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
      --workflow backport-pr-target-closed.yml \
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
  # dont delete the backport-target, this script has no permissions to recreate it
  # deleteBranch case2-backport-target
  deleteBranch case2-new-changes
  revertCommit "$headSha"
  # we have to close the backport pr directly
  # we cannot automatically close it by deleting its branch
  # because the branch exists on upstream
  # #deleteBranch "$backport_branch"
  gh pr close "$backport_branch" --delete-branch
}

function deleteBranch() {
  if [ -n "$1" ]; then
    git branch --delete "$1"
    git push origin --delete "$1"
  fi
}

function revertCommit() {
  if [ -n "$1" ]; then
    gh repo sync \
      --force \
      --source korthout/backport-action-test \
      backport-action/backport-action-test
    git checkout main
    git pull
    git branch case2-revert
    git checkout case2-revert
    git revert --mainline 1 "$1" --no-edit
    git push -u origin HEAD
    
    # open a pull request to upstream
    gh pr create \
      --head backport-action:case2-revert \
      --title "Case(2): Revert" \
      --body "Reverts the changes of case 2"

    # merge the pull request
    gh pr merge \
      --merge \
      --subject "case(2): revert"
    git checkout main
    deleteBranch case2-revert
  fi
}

# Initialise clean up
mergeCommit=""
headSha=""
backport_branch=""
trap 'cleanup' EXIT

# Run script
set -ex
main
