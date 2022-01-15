#! /bin/bash

# When run this test will:
# - create a branch from main as backport target
# - create a branch from main for new changes
# - add a commit to new
# - open a pull request to merge it to main
# - merge the pull request
# - see the simle.yml workflow run on pull_request[closed]
# - check that pull request is opened to target with cherrypicked commit
# - cleanup: revert merge to main, close backport-pr and delete both new branches

function main() {
  name="Case 1"
  email="case1[bot]@users.noreply.github.com"
  export GIT_AUTHOR_NAME="$name"
  export GIT_AUTHOR_EMAIL="$email"
  export GIT_COMMITTER_NAME="$name"
  export GIT_COMMITTER_EMAIL="$email"

  git branch case1-backport-target
  git push -u origin case1-backport-target

  git branch case1-new-changes
  git checkout case1-new-changes

  mkdir case1
  echo "A changed line is added" >> case1/file1
  git add case1/file1
  git commit -m "case(1): add changed line"
  git push -u origin case1-new-changes

  gh pr create \
    --head case1-new-changes \
    --base main \
    --title "Case(1): Add a changed line" \
    --body "Adds a changed line"

  gh pr merge \
    --merge \
    --subject "case(1): merge pull request"

  mergeCommit=$(gh pr view \
    --json mergeCommit \ 
    --jq '.mergeCommit.oid')

    # wait for workflow to finish
    # check that pull request is opened to target with cherrypicked commit
    # cleanup
}

function cleanup() {
  set +e
  git checkout main
  deleteBranch case1-backport-target
  deleteBranch case1-new-changes
  revertMergeCommit "$mergeCommit"
}

function deleteBranch() {
  git branch --delete "$1"
  git push origin --delete "$1"
}

function revertCommit() {
  if [ ! -z "$1" ]; then
    git pull
    git revert --mainline 1 "$1"
    git push
  fi
}

set -e
mergeCommit=""
trap 'cleanup' EXIT
main
