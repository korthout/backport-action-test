# Backport action test
[![Test](https://github.com/korthout/backport-action-test/actions/workflows/test.yml/badge.svg)](https://github.com/korthout/backport-action-test/actions/workflows/test.yml)

Automated end-to-end tests for [zeebe-io/backport-action](https://github.com/zeebe-io/backport-action).

## Why
The backport-action has its own unit and integration tests, but these don't tests at the same level as the action is being used: GitHub.

Users of the action run it in a GitHub workflow using many different configurations:
- triggered by different events: `pull_request`, `pull_request_target`, `issue_comment`, etc.
- merging local and remote pull requsts: whether or not the pull request comes from a forked repo or not
- merging with a specific strategy: `merge-commit`, `rebase`, `squash`

All these should be accounted for in automated tests to improve the reliability of the project and to have confidence when improving it.

## Covered cases
The following cases are covered by this test suite:

| case | event                 | pull request | merge strategy  |
| ---- | --------------------- | ------------ | --------------- |
| 1.   | `pull_request`        | `local`      | `merge-commit`  |
| 2.   | `pull_request_target` | `fork`       | `merge-commit`  |

## How to run the tests?
If you want to run the test against the `master` branch of [zeebe-io/backport-action](https://github.com/zeebe-io/backport-action), then:
- Navigate to the [Test workflow](https://github.com/korthout/backport-action-test/actions/workflows/test.yml)
- Click `Run workflow`
- (Optionally) choose case: all, 1, 2, etc
- Each case is a job in the Test workflow
- Each case verifies the related created backport PRs
- Each case does its own cleanup

If you want to run the tests against another branch, then:
- Checkout a new branch in this repo
- Change the version of the backport-action in all the `backport-pr-*.yml` workflow files,
  e.g. [.github/workflows/backport-pr-closed.yml](https://github.com/korthout/backport-action-test/blob/ebf96ba361706772b427f0cd137ecf6aa162b701/.github/workflows/backport-pr-closed.yml#L20)
- Run the test as described above, but choose your own branch to run the workflow from instead of `main`
