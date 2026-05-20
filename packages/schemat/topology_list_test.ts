import { assert, assertEquals } from "@std/assert";
import { listTopologyPresets } from "./topology_list.ts";

Deno.test("listTopologyPresets: returns preset summaries sorted by name", async () => {
  const presets = await listTopologyPresets();

  assert(presets.length > 0, "should return at least one preset");
  for (const preset of presets) {
    assert(typeof preset.name === "string", "preset name should be a string");
    assert(preset.name.length > 0, "preset name should not be empty");
    if (preset.description !== undefined) {
      assert(
        typeof preset.description === "string",
        "preset description should be a string when present",
      );
    }
  }

  // Verify lexicographic ordering.
  for (let i = 1; i < presets.length; i++) {
    assert(
      presets[i].name >= presets[i - 1].name,
      `presets should be sorted: ${presets[i - 1].name} > ${presets[i].name}`,
    );
  }
});

Deno.test("listTopologyPresets: returns unique preset names", async () => {
  const presets = await listTopologyPresets();
  const names = presets.map((p) => p.name);
  assertEquals(names, [...new Set(names)].sort(), "preset names should be unique");
});

Deno.test("listTopologyPresets: known presets are included", async () => {
  const presets = await listTopologyPresets();
  const names = new Set(presets.map((p) => p.name));

  // These presets ship with schemat and should always resolve.
  const expected = ["reference-plc", "allegedly-plc"];
  for (const name of expected) {
    assert(names.has(name), `expected preset "${name}" should be present`);
  }
});
