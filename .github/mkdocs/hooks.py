"""MkDocs hook: links from docs/ to files outside docs/ (root README, terraform/,
Helmsman/, ...) work on GitHub but not on the site. Rewrite them to GitHub URLs
so the site keeps them working and `mkdocs build --strict` still catches broken
links inside docs/."""
import os
import posixpath
import re

REPO_BLOB = "https://github.com/mosip/infra/blob/develop/"
REPO_TREE = "https://github.com/mosip/infra/tree/develop/"
LINK = re.compile(r"(\]\()([^)\s]+)(\))")


def on_page_markdown(markdown, page, config, files):
    docs_dir = config["docs_dir"]
    repo_root = os.path.dirname(os.path.abspath(docs_dir))
    page_dir = posixpath.dirname(page.file.src_uri)

    def rewrite(match):
        target = match.group(2)
        if re.match(r"^([a-z][a-z0-9+.-]*:|#|/)", target, re.I):
            return match.group(0)
        path, _, frag = target.partition("#")
        rel_to_docs = posixpath.normpath(posixpath.join(page_dir, path))
        if not rel_to_docs.startswith("../"):
            return match.group(0)  # inside docs/: MkDocs resolves and validates it
        repo_path = posixpath.normpath(posixpath.join("docs", rel_to_docs))
        abs_path = os.path.join(repo_root, repo_path)
        base = REPO_TREE if os.path.isdir(abs_path) else REPO_BLOB
        url = base + repo_path.rstrip("/") + (("#" + frag) if frag else "")
        return f"{match.group(1)}{url}{match.group(3)}"

    return LINK.sub(rewrite, markdown)
