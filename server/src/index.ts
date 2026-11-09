import Anthropic from "@anthropic-ai/sdk";

import { buildApp } from "./app.js";
import { AnthropicBatchClient } from "./segmentation/batch.js";
import { ClaudeSegmenter } from "./segmentation/claudeSegmenter.js";
import { SegmentService } from "./segmentation/service.js";
import { MemoryQuotaStore, MemorySegmentCache, MemoryUsageLog } from "./stores/memory.js";

// Credentials resolve from the environment (ANTHROPIC_API_KEY or an `ant auth login` profile).
const client = new Anthropic();
const quota = new MemoryQuotaStore();
const segments = new SegmentService({
  cache: new MemorySegmentCache(),
  quota,
  usage: new MemoryUsageLog(),
  model: new ClaudeSegmenter(client),
  batch: new AnthropicBatchClient(client),
});

const app = buildApp({ segments, quota });
const port = Number(process.env.PORT ?? 8787);
await app.listen({ port, host: "0.0.0.0" });
