# Backport action test
Automated tests for [zeebe-io/backport-action](https://github.com/zeebe-io/backport-action).

## Why
The backport-action has its own unit and integration tests, but these don't tests at the same level as the action is being used: GitHub.

Users of the action run it in a GitHub workflow using many different configurations:
- triggered by different events: `pull_request`, `pull_request_target`, `issue_comment`, etc.
- merging local and remote pull requsts: whether or not the pull request comes from a forked repo or not
- merging with a specific strategy: `merge-commit`, `rebase`, `squash`

All these should be accounted for in automated tests to improve the reliability of the project and to have confidence when improving it.
