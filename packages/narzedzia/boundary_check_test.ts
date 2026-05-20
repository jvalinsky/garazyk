import { assertEquals } from "@std/assert";
import { join } from "@std/path";
import { checkBoundaries, type BoundaryRule } from "./boundary_check.ts";

Deno.test("checkBoundaries: detects real violations", async () => {
  const root = join(Deno.cwd(), "../..");
  
  // Define a rule that is guaranteed to fail
  // gruszka must not depend on schemat, but it doesn't.
  // Let's find one that DOES exist.
  // schemat depends on nothing denied.
  // laweta depends on gruszka.
  
  const rules: BoundaryRule[] = [
    {
      packageName: "laweta",
      denied: new Set(["gruszka"]),
      description: "Test violation: laweta must not depend on gruszka",
    }
  ];

  const violations = await checkBoundaries(root, rules, new Set());
  
  // laweta/format.ts imports @garazyk/gruszka/format.ts
  const lawetaToGruszka = violations.find(v => v.specifier.includes("gruszka"));
  assertEquals(!!lawetaToGruszka, true);
  assertEquals(lawetaToGruszka?.file, "packages/laweta/format.ts");
});

Deno.test("checkBoundaries: passes when no violations", async () => {
  const root = join(Deno.cwd(), "../..");
  
  const rules: BoundaryRule[] = [
    {
      packageName: "gruszka",
      denied: new Set(["schemat"]),
      description: "gruszka must not depend on schemat",
    }
  ];

  const violations = await checkBoundaries(root, rules, new Set());
  assertEquals(violations.length, 0);
});
