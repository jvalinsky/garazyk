/**
 * Tests for Path Resolution Logic
 */

import { describe, it } from "node:test";
import assert from "node:assert";
import {
  calculateNewPath,
  calculateNewPaths,
  needsPathResolution,
  splitHref,
  validateResolvedPath,
} from "./path-resolver.js";

describe("splitHref", () => {
  it("should split path and anchor", () => {
    const result = splitHref("file.md#section");
    assert.strictEqual(result.path, "file.md");
    assert.strictEqual(result.fragment, "#section");
  });

  it("should split path and query", () => {
    const result = splitHref("file.md?param=value");
    assert.strictEqual(result.path, "file.md");
    assert.strictEqual(result.fragment, "?param=value");
  });

  it("should split path with both query and anchor", () => {
    const result = splitHref("file.md?param=value#section");
    assert.strictEqual(result.path, "file.md");
    assert.strictEqual(result.fragment, "?param=value#section");
  });

  it("should handle path without fragment", () => {
    const result = splitHref("file.md");
    assert.strictEqual(result.path, "file.md");
    assert.strictEqual(result.fragment, "");
  });

  it("should handle anchor-only href", () => {
    const result = splitHref("#section");
    assert.strictEqual(result.path, "");
    assert.strictEqual(result.fragment, "#section");
  });

  it("should handle query-only href", () => {
    const result = splitHref("?param=value");
    assert.strictEqual(result.path, "");
    assert.strictEqual(result.fragment, "?param=value");
  });

  it("should handle empty href", () => {
    const result = splitHref("");
    assert.strictEqual(result.path, "");
    assert.strictEqual(result.fragment, "");
  });

  it("should handle null/undefined", () => {
    assert.deepStrictEqual(splitHref(null), { path: "", fragment: "" });
    assert.deepStrictEqual(splitHref(undefined), { path: "", fragment: "" });
  });
});

describe("needsPathResolution", () => {
  it("should return true for relative paths", () => {
    assert.strictEqual(needsPathResolution("./file.md"), true);
    assert.strictEqual(needsPathResolution("../file.md"), true);
    assert.strictEqual(needsPathResolution("file.md"), true);
  });

  it("should return false for external URLs", () => {
    assert.strictEqual(needsPathResolution("http://example.com"), false);
    assert.strictEqual(needsPathResolution("https://example.com"), false);
    assert.strictEqual(needsPathResolution("ftp://example.com"), false);
    assert.strictEqual(needsPathResolution("mailto:test@example.com"), false);
  });

  it("should return false for anchor-only links", () => {
    assert.strictEqual(needsPathResolution("#section"), false);
  });

  it("should return false for absolute paths", () => {
    assert.strictEqual(needsPathResolution("/docs/file.md"), false);
  });

  it("should return false for query-only", () => {
    assert.strictEqual(needsPathResolution("?param=value"), false);
  });

  it("should return true for relative paths with anchors", () => {
    assert.strictEqual(needsPathResolution("./file.md#section"), true);
    assert.strictEqual(needsPathResolution("../file.md#section"), true);
  });

  it("should handle empty/null/undefined", () => {
    assert.strictEqual(needsPathResolution(""), false);
    assert.strictEqual(needsPathResolution(null), false);
    assert.strictEqual(needsPathResolution(undefined), false);
  });
});

describe("calculateNewPath", () => {
  describe("relative paths", () => {
    it("should update path when file moves to deeper directory", () => {
      // plan/oauth2.md -> docs/oauth2/overview.md
      // ../README.md -> ../../README.md
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "../README.md",
      );
      assert.strictEqual(result, "../../README.md");
    });

    it("should update path when file moves to shallower directory", () => {
      // docs/oauth2/overview.md -> plan/oauth2.md
      // ../../README.md -> ../README.md
      const result = calculateNewPath(
        "docs/oauth2/overview.md",
        "plan/oauth2.md",
        "../../README.md",
      );
      assert.strictEqual(result, "../README.md");
    });

    it("should update path when file moves to sibling directory", () => {
      // plan/oauth2.md -> docs/oauth2.md
      // ./other.md -> ../plan/other.md
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2.md",
        "./other.md",
      );
      assert.strictEqual(result, "../plan/other.md");
    });

    it("should handle paths without ./ prefix", () => {
      // plan/oauth2.md -> docs/oauth2.md
      // other.md -> ../plan/other.md
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2.md",
        "other.md",
      );
      assert.strictEqual(result, "../plan/other.md");
    });

    it("should handle complex relative paths", () => {
      // plan/sub/file.md -> docs/guides/file.md
      // ../../other/doc.md -> ../../other/doc.md
      const result = calculateNewPath(
        "plan/sub/file.md",
        "docs/guides/file.md",
        "../../other/doc.md",
      );
      assert.strictEqual(result, "../../other/doc.md");
    });

    it("should handle file in same directory after move", () => {
      // plan/file1.md -> docs/file1.md
      // ./file2.md -> ./file2.md (if file2 also moved)
      // This assumes file2.md also moved to docs/
      const result = calculateNewPath(
        "plan/file1.md",
        "docs/file1.md",
        "./file2.md",
      );
      assert.strictEqual(result, "../plan/file2.md");
    });
  });

  describe("anchor links", () => {
    it("should preserve anchors in relative paths", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "../README.md#setup",
      );
      assert.strictEqual(result, "../../README.md#setup");
    });

    it("should preserve query parameters", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "../README.md?version=2",
      );
      assert.strictEqual(result, "../../README.md?version=2");
    });

    it("should preserve query and anchor", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "../README.md?version=2#setup",
      );
      assert.strictEqual(result, "../../README.md?version=2#setup");
    });

    it("should not modify anchor-only links", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "#section",
      );
      assert.strictEqual(result, "#section");
    });
  });

  describe("absolute paths", () => {
    it("should not modify absolute paths", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "/docs/api.md",
      );
      assert.strictEqual(result, "/docs/api.md");
    });

    it("should preserve anchors in absolute paths", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "/docs/api.md#endpoint",
      );
      assert.strictEqual(result, "/docs/api.md#endpoint");
    });
  });

  describe("external URLs", () => {
    it("should not modify http URLs", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "http://example.com",
      );
      assert.strictEqual(result, "http://example.com");
    });

    it("should not modify https URLs", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "https://example.com/page",
      );
      assert.strictEqual(result, "https://example.com/page");
    });

    it("should not modify mailto links", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "mailto:test@example.com",
      );
      assert.strictEqual(result, "mailto:test@example.com");
    });

    it("should not modify ftp URLs", () => {
      const result = calculateNewPath(
        "plan/oauth2.md",
        "docs/oauth2/overview.md",
        "ftp://ftp.example.com/file",
      );
      assert.strictEqual(result, "ftp://ftp.example.com/file");
    });
  });

  describe("edge cases", () => {
    it("should handle empty inputs", () => {
      assert.strictEqual(calculateNewPath("", "", ""), "");
      assert.strictEqual(calculateNewPath("file.md", "file.md", ""), "");
    });

    it("should handle null/undefined", () => {
      assert.strictEqual(calculateNewPath(null, null, null), "");
      assert.strictEqual(calculateNewPath("a", "b", null), "");
    });

    it("should handle paths with backslashes", () => {
      const result = calculateNewPath(
        "plan\\oauth2.md",
        "docs\\oauth2\\overview.md",
        "..\\README.md",
      );
      assert.strictEqual(result, "../../README.md");
    });

    it("should handle paths with ./ prefix", () => {
      const result = calculateNewPath(
        "./plan/oauth2.md",
        "./docs/oauth2/overview.md",
        "../README.md",
      );
      assert.strictEqual(result, "../../README.md");
    });

    it("should handle root-level files", () => {
      const result = calculateNewPath(
        "README.md",
        "docs/README.md",
        "./CONTRIBUTING.md",
      );
      assert.strictEqual(result, "../CONTRIBUTING.md");
    });
  });
});

describe("calculateNewPaths", () => {
  it("should calculate paths for multiple links", () => {
    const links = [
      { href: "../README.md" },
      { href: "./other.md" },
      { href: "https://example.com" },
      { href: "#section" },
    ];

    const pathMap = calculateNewPaths(
      "plan/oauth2.md",
      "docs/oauth2/overview.md",
      links,
    );

    // Only relative paths should be in the map (changed paths)
    assert.strictEqual(pathMap.size, 2);
    assert.strictEqual(pathMap.get("../README.md"), "../../README.md");
    assert.strictEqual(pathMap.get("./other.md"), "../../plan/other.md");

    // External URLs and anchors should not be in the map (unchanged)
    assert.strictEqual(pathMap.has("https://example.com"), false);
    assert.strictEqual(pathMap.has("#section"), false);
  });

  it("should handle empty links array", () => {
    const pathMap = calculateNewPaths(
      "plan/oauth2.md",
      "docs/oauth2/overview.md",
      [],
    );
    assert.strictEqual(pathMap.size, 0);
  });

  it("should skip links without href", () => {
    const links = [
      { text: "no href" },
      { href: "../README.md" },
    ];

    const pathMap = calculateNewPaths(
      "plan/oauth2.md",
      "docs/oauth2/overview.md",
      links,
    );

    assert.strictEqual(pathMap.size, 1);
    assert.strictEqual(pathMap.get("../README.md"), "../../README.md");
  });

  it("should not include unchanged paths", () => {
    const links = [
      { href: "https://example.com" },
      { href: "#section" },
      { href: "/absolute/path.md" },
    ];

    const pathMap = calculateNewPaths(
      "plan/oauth2.md",
      "docs/oauth2/overview.md",
      links,
    );

    // All paths are unchanged, so map should be empty
    assert.strictEqual(pathMap.size, 0);
  });
});

describe("validateResolvedPath", () => {
  it("should validate correct relative path resolution", () => {
    const isValid = validateResolvedPath(
      "docs/oauth2/overview.md",
      "../../README.md",
      "README.md",
    );
    assert.strictEqual(isValid, true);
  });

  it("should detect incorrect relative path resolution", () => {
    const isValid = validateResolvedPath(
      "docs/oauth2/overview.md",
      "../README.md", // Wrong - should be ../../README.md
      "README.md",
    );
    assert.strictEqual(isValid, false);
  });

  it("should validate absolute paths", () => {
    const isValid = validateResolvedPath(
      "docs/oauth2/overview.md",
      "/docs/api.md",
      "/docs/api.md",
    );
    assert.strictEqual(isValid, true);
  });

  it("should validate external URLs as always valid", () => {
    const isValid = validateResolvedPath(
      "docs/oauth2/overview.md",
      "https://example.com",
      "anything",
    );
    assert.strictEqual(isValid, true);
  });

  it("should validate anchor-only links as always valid", () => {
    const isValid = validateResolvedPath(
      "docs/oauth2/overview.md",
      "#section",
      "anything",
    );
    assert.strictEqual(isValid, true);
  });

  it("should handle paths with anchors", () => {
    const isValid = validateResolvedPath(
      "docs/oauth2/overview.md",
      "../../README.md#setup",
      "README.md#setup",
    );
    assert.strictEqual(isValid, true);
  });

  it("should handle empty/null inputs", () => {
    assert.strictEqual(validateResolvedPath("", "", ""), false);
    assert.strictEqual(validateResolvedPath(null, null, null), false);
  });
});

describe("integration tests", () => {
  it("should handle complete file migration scenario", () => {
    // Scenario: Moving plan/oauth2.md to docs/oauth2/overview.md
    const oldPath = "plan/oauth2.md";
    const newPath = "docs/oauth2/overview.md";

    const links = [
      { href: "../README.md#quick-start" },
      { href: "./implementation.md" },
      { href: "../AGENTS.md" },
      { href: "https://atproto.com/specs/oauth" },
      { href: "#introduction" },
      { href: "/docs/api/endpoints.md" },
    ];

    const pathMap = calculateNewPaths(oldPath, newPath, links);

    // Verify relative paths are updated
    assert.strictEqual(pathMap.get("../README.md#quick-start"), "../../README.md#quick-start");
    assert.strictEqual(pathMap.get("./implementation.md"), "../../plan/implementation.md");
    assert.strictEqual(pathMap.get("../AGENTS.md"), "../../AGENTS.md");

    // Verify external URLs, anchors, and absolute paths are not in map
    assert.strictEqual(pathMap.has("https://atproto.com/specs/oauth"), false);
    assert.strictEqual(pathMap.has("#introduction"), false);
    assert.strictEqual(pathMap.has("/docs/api/endpoints.md"), false);

    // Validate the resolved paths
    assert.strictEqual(
      validateResolvedPath(
        newPath,
        pathMap.get("../README.md#quick-start"),
        "README.md#quick-start",
      ),
      true,
    );
    assert.strictEqual(
      validateResolvedPath(newPath, pathMap.get("./implementation.md"), "plan/implementation.md"),
      true,
    );
  });

  it("should handle multiple files moving to same directory", () => {
    // Both files move from plan/ to docs/guides/
    const file1Old = "plan/guide1.md";
    const file1New = "docs/guides/guide1.md";
    const file2Old = "plan/guide2.md";
    const file2New = "docs/guides/guide2.md";

    // Link from guide1 to guide2
    const link = "./guide2.md";

    // Calculate new path for the link in guide1
    const newPath = calculateNewPath(file1Old, file1New, link);

    // The link should now point to ../../plan/guide2.md
    // (because guide2.md hasn't moved yet from plan/)
    assert.strictEqual(newPath, "../../plan/guide2.md");

    // If we want them to link correctly after both move,
    // we'd need to update links after all files are moved
    // or use absolute paths during migration
  });
});
