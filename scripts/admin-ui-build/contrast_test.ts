const TOKENS_PATH = "Garazyk/Sources/AdminUIServer/Assets/css/tokens.css";
const MIN_TEXT_CONTRAST = 4.5;

type Color = readonly [number, number, number];

function tokenValues(css: string, name: string): string[] {
  const pattern = new RegExp(`--${name}:\\s*([^;]+);`, "g");
  const values = [...css.matchAll(pattern)].map((match) => match[1].trim());
  if (values.length === 0) {
    throw new Error(`Missing --${name} token`);
  }
  return values;
}

function parseColor(value: string): Color {
  if (value === "white") return [1, 1, 1];

  const match = value.match(/^oklch\(([\d.]+)%\s+([\d.]+)\s+([\d.]+)\)$/);
  if (!match) throw new Error(`Unsupported color token value: ${value}`);

  const lightness = Number(match[1]) / 100;
  const chroma = Number(match[2]);
  const hue = Number(match[3]) * Math.PI / 180;
  const a = chroma * Math.cos(hue);
  const b = chroma * Math.sin(hue);
  const l = (lightness + 0.3963377774 * a + 0.2158037573 * b) ** 3;
  const m = (lightness - 0.1055613458 * a - 0.0638541728 * b) ** 3;
  const s = (lightness - 0.0894841775 * a - 1.291485548 * b) ** 3;

  return [
    Math.max(
      0,
      Math.min(1, 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    ),
    Math.max(
      0,
      Math.min(1, -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    ),
    Math.max(
      0,
      Math.min(1, -0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
    ),
  ];
}

function relativeLuminance([red, green, blue]: Color): number {
  return 0.2126 * red + 0.7152 * green + 0.0722 * blue;
}

function contrastRatio(left: Color, right: Color): number {
  const leftLuminance = relativeLuminance(left);
  const rightLuminance = relativeLuminance(right);
  return (Math.max(leftLuminance, rightLuminance) + 0.05) /
    (Math.min(leftLuminance, rightLuminance) + 0.05);
}

function assertContrast(
  label: string,
  foreground: Color,
  background: Color,
): void {
  const ratio = contrastRatio(foreground, background);
  if (ratio < MIN_TEXT_CONTRAST) {
    throw new Error(
      `${label} has ${
        ratio.toFixed(2)
      }:1 contrast; expected at least ${MIN_TEXT_CONTRAST}:1`,
    );
  }
}

Deno.test("Admin UI semantic foreground and action-fill tokens meet text contrast", async () => {
  const css = await Deno.readTextFile(TOKENS_PATH);
  const foregroundNames = [
    "accent",
    "destructive",
    "success",
    "warning",
    "info",
  ];
  const backgroundNames = ["bg-primary", "bg-tertiary"];

  for (const mode of [0, 1]) {
    const modeName = mode === 0 ? "light" : "dark";
    for (const foregroundName of foregroundNames) {
      const foreground = parseColor(
        tokenValues(css, `color-foreground-${foregroundName}`)[mode],
      );
      for (const backgroundName of backgroundNames) {
        const background = parseColor(
          tokenValues(css, `color-${backgroundName}`)[mode],
        );
        assertContrast(
          `${modeName} ${foregroundName} on ${backgroundName}`,
          foreground,
          background,
        );
      }
    }
  }

  for (const name of foregroundNames) {
    const action = parseColor(tokenValues(css, `color-${name}`)[0]);
    const onAction = parseColor(tokenValues(css, `color-on-${name}`)[0]);
    assertContrast(`text on ${name} action fill`, onAction, action);
  }
});
