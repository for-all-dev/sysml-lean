/**
 * Sticky-comment helper: find an existing PR comment carrying a marker HTML
 * comment and update it in place, or create a new one if none exists yet.
 *
 * Octokit types are intentionally loosened to `any` here — the REST response
 * shapes are stable enough for our purposes and fighting the generated types
 * for a handful of fields isn't worth it.
 */

export const STICKY_MARKER = "<!-- sysml-findings-diff -->";

export interface UpsertCommentOptions {
  octokit: any;
  owner: string;
  repo: string;
  issueNumber: number;
  body: string;
  marker?: string;
}

/**
 * Create or update the sticky PR comment identified by `marker`.
 * Returns the comment id that was created/updated.
 */
export async function upsertStickyComment(
  opts: UpsertCommentOptions
): Promise<number> {
  const { octokit, owner, repo, issueNumber, body } = opts;
  const marker = opts.marker ?? STICKY_MARKER;

  const existing = await findStickyComment({
    octokit,
    owner,
    repo,
    issueNumber,
    marker,
  });

  if (existing) {
    await octokit.rest.issues.updateComment({
      owner,
      repo,
      comment_id: existing.id,
      body,
    });
    return existing.id;
  }

  const created = await octokit.rest.issues.createComment({
    owner,
    repo,
    issue_number: issueNumber,
    body,
  });
  return created.data.id;
}

export async function findStickyComment(opts: {
  octokit: any;
  owner: string;
  repo: string;
  issueNumber: number;
  marker?: string;
}): Promise<{ id: number } | undefined> {
  const { octokit, owner, repo, issueNumber } = opts;
  const marker = opts.marker ?? STICKY_MARKER;

  const comments = await octokit.paginate(
    octokit.rest.issues.listComments,
    {
      owner,
      repo,
      issue_number: issueNumber,
      per_page: 100,
    }
  );

  const found = (comments as any[]).find((c) =>
    typeof c.body === "string" && c.body.includes(marker)
  );
  return found ? { id: found.id } : undefined;
}
