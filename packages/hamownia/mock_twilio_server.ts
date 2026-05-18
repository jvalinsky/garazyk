#!/usr/bin/env -S deno run -A
import { parseMockTwilioConfig, serveMockTwilio } from "./mock_twilio.ts";
const config = parseMockTwilioConfig(Deno.args);
await serveMockTwilio(config);
