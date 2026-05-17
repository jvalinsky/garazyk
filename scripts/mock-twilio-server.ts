#!/usr/bin/env -S deno run -A
import { parseMockTwilioConfig, serveMockTwilio } from "@garazyk/hamownia/mock-twilio";

const config = parseMockTwilioConfig(Deno.args);
await serveMockTwilio(config);
