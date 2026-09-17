# Issue tracker: GitHub

Issues and specifications live in GitHub Issues for `jcergolj/metator-for-laravel`. Use the `gh` CLI for GitHub operations. When a skill says to publish a ticket or specification, create a GitHub issue; when it says to fetch a ticket, read its full body, labels, comments, and dependencies.

## Common operations

- Read: `gh issue view <number> --repo jcergolj/metator-for-laravel --comments`.
- List: `gh issue list --repo jcergolj/metator-for-laravel --state open --json number,title,labels,url`.
- Create: `gh issue create --repo jcergolj/metator-for-laravel --title "..." --body-file <file>`.
- Edit: `gh issue edit <number> --repo jcergolj/metator-for-laravel --body-file <file>`.
- Comment: `gh issue comment <number> --repo jcergolj/metator-for-laravel --body "..."`.
- Label: `gh issue edit <number> --repo jcergolj/metator-for-laravel --add-label "..."` or `--remove-label "..."`.
- Close: `gh issue close <number> --repo jcergolj/metator-for-laravel --reason completed --comment "..."`; use `--reason 'not planned'` with an explanation for superseded or deferred work.

Review existing issues before creating new ones. Preserve useful discussion when revising a brief and link replacements when consolidating issues. Closing an obsolete issue preserves its history; do not delete it merely to clean up the backlog.

## Blocking dependencies

GitHub native issue dependencies are the canonical blocking relationships. Keep each issue's readable **Blocked by** section consistent with them.

- Read blockers: `gh api repos/jcergolj/metator-for-laravel/issues/<number>/dependencies/blocked_by --paginate --jq '.[] | {number, title, state, state_reason}'`.
- Obtain a blocker's numeric database ID: `gh api repos/jcergolj/metator-for-laravel/issues/<blocker-number> --jq .id`.
- Add a blocker: `gh api --method POST repos/jcergolj/metator-for-laravel/issues/<number>/dependencies/blocked_by -F issue_id=<blocker-database-id>`.
- Remove an obsolete relationship: `gh api --method DELETE repos/jcergolj/metator-for-laravel/issues/<number>/dependencies/blocked_by/<blocker-database-id>`.

The dependency API requires the numeric database ID, not the issue number or GraphQL node ID. GitHub's `issue_dependencies_summary.blocked_by` counts open blockers.

Work on actionable issues whose blockers are resolved. A `ready-for-agent` label alone does not authorize starting blocked work. If a blocker was closed as deferred or superseded, check whether the required capability was actually delivered or the dependency needs revision.

Publish approved tickets in dependency order, with self-contained behavior and acceptance criteria. Include meaningful verification in each implementation slice rather than deferring all testing to the final release gate.

## Pull requests as a triage surface

**PRs as a request surface: no.**

Pull requests remain implementation/review artifacts, not an additional feature-request triage queue. This setting can be changed explicitly later.
