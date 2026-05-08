import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { registerRegistrationGuard } from "./src/commands/registrationGuard.js";
import { registerScenarios } from "./src/commands/scenarios.js";
import { registerServices } from "./src/commands/services.js";
import { registerTestAudit } from "./src/commands/testAudit.js";
import { registerTestNav } from "./src/commands/testnav.js";
import { registerXTest } from "./src/commands/xtest.js";

export default function garazykTestConsole(pi: ExtensionAPI): void {
	registerXTest(pi);
	registerRegistrationGuard(pi);
	registerTestNav(pi);
	registerScenarios(pi);
	registerServices(pi);
	registerTestAudit(pi);

	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		ctx.ui.setStatus("garazyk-test-console", "tests: /xtest /testnav /scenarios /services /test-audit");
	});
}
