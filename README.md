# Backport action test
[![Test](https://github.com/korthout/backport-action-test/actions/workflows/test.yml/badge.svg)](https://github.com/korthout/backport-action-test/actions/workflows/test.yml)

Automated end-to-end tests for [korthout/backport-action](https://github.com/korthout/backport-action).

## Why does this exist?
To improve the reliability of the backport-action and to have confidence when improving it.

Users of the backport-action run it in different ways:
- triggered by different events: [`pull_request`](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request) , [`pull_request_target`](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#pull_request_target), [`issue_comment`](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#issue_comment), etc.
- using local or remote pull requests (whether or not the pull request comes from a forked repo)
- using one of the merge strategies: [`merge-commit`](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/about-pull-request-merges), [`rebase`](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/about-pull-request-merges#rebase-and-merge-your-pull-request-commits), [`squash`](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/about-pull-request-merges#squash-and-merge-your-pull-request-commits)

All of these scenarios should be accounted for in automated tests.
Of course, there are unit and integration tests but these don't really show that the action works in the above cases.

## Which cases are covered?
This test suite covers the following cases:

| case.               | event                 | pull request | merge strategy  |
| ------------------- | --------------------- | ------------ | --------------- |
| [1.](test/case1.sh) | `pull_request`        | `local`      | `merge-commit`  |
| [2.](test/case2.sh) | `pull_request_target` | `fork`       | `merge-commit`  |
| [3.](test/case3.sh) | `pull_request`        | `local`      | `squash`        |

## How does it work?
The tests in this repository simulate user behavior: they commit changes, open pull requests and merge them.
They also wait for the backport-action to create the relevant pull requests, and inspect that these contain the right changes.
In other words, they seek to answer: could the backport-action successfully backport the changes in this scenario?

The [Test workflow](.github/workflows/test.yml) orchestrates the test case execution.
Each case is represented by a job.
They all checkout this repo (note, cases dealing with forked repos checkout a fork of this repo),
and then run the related [test case](test/) script.
The test case script then commits changes, opens and merges the pull request and verifies the created backport pull request.
The scripts also do their own clean-up, e.g. closing any left-over pull requests.

For each case, a specific backport-action workflow is defined,
e.g. [backport-pr-closed.yml](.github/workflows/backport-pr-closed.yml) belongs to case 1.
To make sure they are [triggered as a result of the _Test workflow_](https://github.community/t/github-action-trigger-on-release-not-working-if-releases-was-created-by-automation/16559), each job provides a 
[PAT](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token)
instead of the [`GITHUB_TOKEN`](https://docs.github.com/en/actions/security-guides/automatic-token-authentication#about-the-github_token-secret).

## How can I run the tests?
If you want to run the test against the backport-action, then:
- Navigate to the [Test workflow](https://github.com/korthout/backport-action-test/actions/workflows/test.yml)
- Click `Run workflow`
- (Optionally) choose case: all, 1, 2, etc

If you want to run the tests against a specific version, then:
- Refer to your specific version or branch in all the `backport-pr-*.yml` workflow files,
  e.g. [.github/workflows/backport-pr-closed.yml](https://github.com/korthout/backport-action-test/blob/ebf96ba361706772b427f0cd137ecf6aa162b701/.github/workflows/backport-pr-closed.yml#L20).
- Commit (e.g. `test: backport-action/pull/255`) and push this to `main`
- Run the test as described above
- Don't forget to revert the commit you pushed to `main`
